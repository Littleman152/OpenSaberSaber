extends GameState
class_name GameStatePlaying

func _ready(game: BeepSaber_Game) -> void:
	game.main_menu._hide()
	game.settings_canvas._hide()
	game.show_MapSourceDialogs(false)
	game.endscore._hide()
	game.pause_menu._hide()
	game.highscore_canvas._hide()
	game.name_selector_canvas._hide()
	if Settings.handedness == 0:
		if Map.one_saber:
			if Settings.left_handed:
				game.right_saber._hide()
				game.left_saber._show()
			else:
				game.left_saber._hide()
				game.right_saber._show()
		else:
			game.right_saber._show()
			game.left_saber._show()
	elif Settings.handedness == Constants.HANDEDNESS_FORCE_LEFT:
		game.right_saber._hide()
		game.left_saber._show()
	elif Settings.handedness == Constants.HANDEDNESS_FORCE_RIGHT:
		game.right_saber._show()
		game.left_saber._hide()
	elif Settings.handedness == Constants.HANDEDNESS_IGNORE:
		game.right_saber._show()
		game.left_saber._show()
	game.multiplier_label.visible = true
	game.point_label.visible = true
	game.percent_indicator.visible = true
	game.track.visible = true
	game.left_ui_raycast.visible = false
	game.right_ui_raycast.visible = false
	game.highscore_keyboard._hide()
	game.online_search_keyboard._hide()
	game.left_saber.set_swingcast_enabled(true)
	game.right_saber.set_swingcast_enabled(true)
	Scoreboard.paused = false

func _physics_process(game: BeepSaber_Game) -> void:
	if game.left_controller.by_just_pressed() or game.left_controller.menu_just_pressed():
		game._transition_game_state(game.gamestate_paused)
	if game._audio_synced_after_restart:
		_process_map(game)
	else:
		# 0.5 seconds is a pretty concervative number to use for the audio
		# resync check. Having this duration be this long might only be an
		# issue for maps that spawn notes extremely early into the song.
		if absf(game.song_player.get_playback_position() - game.audio_start_position) < 0.5:
			game._audio_synced_after_restart = true

var bomb_template := load("res://game/Bomb/Bomb.tscn") as PackedScene
var wall_template := load("res://game/Wall/Wall.tscn") as PackedScene
var wall_batch: WallBatch   # draws all uninteractable (Noodle) walls with one draw call
var wall_batch_translucent: WallBatch
var _batch_stack: Array[ObstacleInfo] = []   # uninteractable walls, earliest spawn last
var _batch_stack_ready := false            # set to false when a map (re)starts
var arc_template := load("res://game/Arc/Arc.tscn") as PackedScene
const BEATS_AHEAD := 4.0
var _noodle_bombs: Array[BombInfo] = []   # bombs with Noodle data, earliest spawn last
var _note_batch_arrow: NoteBatch
var _note_batch_dot: NoteBatch

func _get_note_batch(game: BeepSaber_Game, dot: bool) -> NoteBatch:
	if dot:
		if _note_batch_dot == null or not is_instance_valid(_note_batch_dot):
			_note_batch_dot = NoteBatch.new()
			_note_batch_dot.setup(true)
			game.track.add_child(_note_batch_dot)
		return _note_batch_dot
	if _note_batch_arrow == null or not is_instance_valid(_note_batch_arrow):
		_note_batch_arrow = NoteBatch.new()
		_note_batch_arrow.setup(false)
		game.track.add_child(_note_batch_arrow)
	return _note_batch_arrow

func _bomb_spawn_beat(b: BombInfo) -> float:
	return b.beat - maxf(WallBatch._half_jump(b.noodle, Map.current_info.beats_per_minute), BEATS_AHEAD)


func _process_map(game: BeepSaber_Game) -> void:
	if (Map.current_info == null):
		return
	if not _batch_stack_ready:
		_build_batch_stack()
	
	var current_beat := game.song_player.get_playback_position() * Map.current_info.beats_per_minute * 0.016666666666666667
	var look_ahead := current_beat + BEATS_AHEAD
	if NoodleTracks.current != null:
		NoodleTracks.current.begin_frame(current_beat)
		NoodleMotion.song_beat = current_beat
		game.player_rig.transform = NoodleTracks.current.player_transform()
		game.chroma_env.update_tracks()
		if Engine.get_physics_frames() % 60 == 0:
			var cam := game.xr_origin.get_node("XRCamera3D") as Node3D
	if not _noodle_notes_ready:
		_build_noodle_notes()
	
	# chains connect to a regular colornote and modify it, so we have to keep
	# track of what notes were spawned this frame, in case any become the head
	# of a chain.
	# why did they do this?
	var note_info_refs: Array[ColorNoteInfo] = []
	var cube_refs: Array[BeepCube] = []
	
	# spawn notes
	while not Map.note_stack.is_empty() and Map.note_stack[-1].beat <= look_ahead:
		var note_info := Map.note_stack.pop_back() as ColorNoteInfo
		if note_info.noodle != null:
			continue   # spawned below, at its own half-jump distance
		var note := GlobalReferences.cube_pool.acquire() as BeepCube
		note.spawn(note_info, current_beat)
		if Map.is_v4 and (Settings.show_debug_info or Map.DEBUG_PRINT_NOTE_NJS):
			Map.note_njs_debug(note_info)
		note_info_refs.append(note_info)
		cube_refs.append(note)

	while not _noodle_notes.is_empty() and _note_spawn_beat(_noodle_notes[-1]) <= current_beat:
		var ni := _noodle_notes.pop_back() as ColorNoteInfo
		if not (ni.interactable and not ni.fake):
			# visual only: drawn by a batch, no node, nothing to cut
			_get_note_batch(game, ni.cut_angle >= Constants.DIRECTION8_COMPARE).add_note(ni, current_beat)
			continue
		var nn := GlobalReferences.cube_pool.acquire() as BeepCube
		nn.spawn(ni, current_beat)
		note_info_refs.append(ni)
		cube_refs.append(nn)
	
	# spawn bombs
	while not Map.bomb_stack.is_empty() and Map.bomb_stack[-1].beat <= look_ahead:
		var bomb_info := Map.bomb_stack.pop_back() as BombInfo
		if bomb_info.noodle != null:
			continue   # spawned below, at its own half-jump distance
		var bomb := bomb_template.instantiate() as Bomb
		bomb.spawn(bomb_info, current_beat)
		game.track.add_child(bomb)
	
	while not _noodle_bombs.is_empty() and _bomb_spawn_beat(_noodle_bombs[-1]) <= current_beat:
		var nbi := _noodle_bombs.pop_back() as BombInfo
		var nb := bomb_template.instantiate() as Bomb
		nb.spawn(nbi, current_beat)
		game.track.add_child(nb)
	
	# spawn obstacles (walls)
	while not Map.obstacle_stack.is_empty() and Map.obstacle_stack[-1].beat <= look_ahead:
		var wall_info := Map.obstacle_stack.pop_back() as ObstacleInfo
		if not wall_info.interactable:
			continue   # uninteractable walls are spawned below, at their own half-jump distance
		# normal wall: pooled node with collision
		var wall := Wall.acquire()
		if wall == null:
			wall = wall_template.instantiate() as Wall
			game.track.add_child(wall)
		wall.spawn(wall_info, current_beat)

	# uninteractable walls: spawn at beat - hjd, the batch hides them until they are alive
	while not _batch_stack.is_empty() and _batch_spawn_beat(_batch_stack[-1]) <= current_beat:
		var bi := _batch_stack.pop_back() as ObstacleInfo
		var translucent := bi.nd_alpha > 0.0 and bi.nd_alpha < 0.999
		_get_wall_batch(game, translucent).add_wall(bi, current_beat)
	
	while not Map.arc_stack.is_empty() and Map.arc_stack[-1].head_beat <= look_ahead:
		var arc := arc_template.instantiate() as Arc
		var arc_info := Map.arc_stack.pop_back() as ArcInfo
		
		# find starting cube to use as magnet trigger and mark start and end cubes as arc head/tail
		var head_cube : BeepCube
		var cube_id := cube_refs.size()-1
		var have_head := false
		var have_tail := false
		while cube_id >= 0:
			var current_cube : BeepCube = cube_refs[cube_id]
			if current_cube.which_saber == arc_info.color:
				if current_cube.beat == arc_info.head_beat:
					current_cube.set_arc_head()
					head_cube = current_cube
					if have_tail:
						break
					have_head = true
				if current_cube.beat == arc_info.tail_beat:
					current_cube.set_arc_tail()
					if have_head:
						break
					have_tail = true
			cube_id -= 1
		
		if have_head:
			arc.spawn(arc_info, current_beat, head_cube)
			game.track.add_child(arc)
	
	while not Map.chain_stack.is_empty() and Map.chain_stack[-1].head_beat <= look_ahead:
		var chain_info := Map.chain_stack.pop_back() as ChainInfo
		if chain_info.slice_count > 1: # skip if the chain doesn't have any links
			ChainLink.construct_chain(chain_info, current_beat, note_info_refs, cube_refs)
	
	while not Map.event_stack.is_empty() and Map.event_stack[-1].beat <= current_beat:
		game.event_driver.process_event(Map.event_stack.pop_back() as EventInfo)

func _get_wall_batch(game: BeepSaber_Game, translucent := false) -> WallBatch:
	if translucent:
		if wall_batch_translucent == null or not is_instance_valid(wall_batch_translucent):
			wall_batch_translucent = WallBatch.new()
			wall_batch_translucent.setup(true)
			game.track.add_child(wall_batch_translucent)
		return wall_batch_translucent
	if wall_batch == null or not is_instance_valid(wall_batch):
		wall_batch = WallBatch.new()
		wall_batch.setup(false)
		game.track.add_child(wall_batch)
	return wall_batch
	
func reset_batch_stack() -> void:
	_noodle_notes_ready = false
	_batch_stack_ready = false
	
func _batch_spawn_beat(o: ObstacleInfo) -> float:
	var hjd := 4.0
	if o.noodle:
		hjd = WallBatch._half_jump(o, Map.current_info.beats_per_minute)
	return o.beat - maxf(hjd, BEATS_AHEAD)

func _build_batch_stack() -> void:
	_batch_stack_ready = true
	_batch_stack.clear()
	for o: ObstacleInfo in Map.obstacle_stack:
		if not o.interactable:
			_batch_stack.append(o)
	_batch_stack.sort_custom(func(a: ObstacleInfo, b: ObstacleInfo) -> bool:
		return _batch_spawn_beat(a) > _batch_spawn_beat(b))
		
var _noodle_notes: Array[ColorNoteInfo] = []   # notes with Noodle data, earliest spawn last
var _noodle_notes_ready := false

func _note_spawn_beat(n: ColorNoteInfo) -> float:
	return n.beat - maxf(WallBatch._half_jump(n.noodle, Map.current_info.beats_per_minute), BEATS_AHEAD)

func _build_noodle_notes() -> void:
	_noodle_notes_ready = true
	_noodle_notes.clear()
	for n: ColorNoteInfo in Map.note_stack:
		if n.noodle != null:
			_noodle_notes.append(n)
	_noodle_notes.sort_custom(func(a: ColorNoteInfo, b: ColorNoteInfo) -> bool:
		return _note_spawn_beat(a) > _note_spawn_beat(b))
	_noodle_bombs.clear()
	for b: BombInfo in Map.bomb_stack:
		if b.noodle != null:
			_noodle_bombs.append(b)
	_noodle_bombs.sort_custom(func(a: BombInfo, b: BombInfo) -> bool:
		return _bomb_spawn_beat(a) > _bomb_spawn_beat(b))
