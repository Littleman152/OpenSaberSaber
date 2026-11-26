# This is a stand-alone version of the demo game Beep Saber. It started (and is still included)
# in the godot oculus quest toolkit (https://github.com/NeoSpark314/godot_oculus_quest_toolkit)
# But this stand-alone version as additional features and will be developed independently
# This file contains the main game logic for the BeepSaber demo implementation
extends Node3D
class_name BeepSaber_Game

var version : String = ProjectSettings.get_setting("application/config/version", "0.0.0")
var gamestate_bootup := GameState.new()
var gamestate_mapcomplete := GameStateMapComplete.new()
var gamestate_mapselection := GameStateMapSelection.new()
var gamestate_newhighscore := GameStateNewHighScore.new()
var gamestate_paused := GameStatePaused.new()
var gamestate_playing := GameStatePlaying.new()
var gamestate_practice := GameStatePractice.new()
var gamestate_settings := GameStateSettings.new()
var gamestate: GameState = gamestate_bootup
var current_health := Constants.HEALTH_START

@onready var xr_origin := $XROrigin3D as XROrigin3D
@onready var left_controller := $XROrigin3D/LeftController as BeepSaberController
@onready var right_controller := $XROrigin3D/RightController as BeepSaberController
@onready var left_saber := $XROrigin3D/LeftController/LeftLightSaber as LightSaber
@onready var right_saber := $XROrigin3D/RightController/RightLightSaber as LightSaber
@onready var left_ui_raycast := $XROrigin3D/LeftController/LeftLightSaber/UIRaycast as UIRaycast
@onready var right_ui_raycast := $XROrigin3D/RightController/RightLightSaber/UIRaycast as UIRaycast
@onready var goggles_shader := ($XROrigin3D/XRCamera3D/VRGoggles as MeshInstance3D).material_override as ShaderMaterial
@onready var debug_info_label := $XROrigin3D/XRCamera3D/PlayerHead/DebugInfoLabel as MeshInstance3D

@onready var main_menu := $MainMenu_OQ_UI2DCanvas as OQ_UI2DCanvas
@onready var pause_menu := $PauseMenu_canvas as OQ_UI2DCanvas
# the practice menu, see the setup steps. the game still runs without it.
@onready var practice_canvas := get_node_or_null("Practice_canvas") as OQ_UI2DCanvas
@onready var pause_countdown := $Pause_countdown as OQ_UI2DLabel
@onready var settings_canvas := $Settings_canvas as OQ_UI2DCanvas
@onready var settings_panel := settings_canvas.ui_control as SettingsPanel
@onready var highscore_canvas := $Highscores_Canvas as OQ_UI2DCanvas
@onready var highscore_panel := highscore_canvas.ui_control as HighscorePanel
@onready var name_selector_canvas := $NameSelector_Canvas as OQ_UI2DCanvas
@onready var highscore_keyboard := $Keyboard_highscore as OQ_UI2DKeyboard
@onready var endscore := $EndScore as EndScore

@onready var points_label_driver := $Points_label_driver as PointsLabelDriver
@onready var event_driver := $event_driver as EventDriver

@onready var multiplier_label := $Multiplier_Label as MeshInstance3D
@onready var point_label := $Point_Label as MeshInstance3D
@onready var percent_indicator := $Percent_Indicator as PercentIndicator

@onready var map_source_dialogs := $MapSourceDialogs as Node3D
@onready var online_search_keyboard := $Keyboard_online_search as OQ_UI2DKeyboard

@onready var cube_template := preload("res://game/BeepCube/BeepCube.tscn").instantiate() as BeepCube

@onready var track := $Track as Node3D
@onready var chroma_env := ChromaEnvironment.new(event_driver.get_node("Level") as Node3D)
@onready var standing_ground := $StandingGround as Floor

@onready var song_player := $SongPlayer as AudioStreamPlayer

@onready var menu := main_menu.ui_control as MainMenu

var _audio_synced_after_restart := false
var _in_wall := false
var pause_position := 0.0

# --- practice mode ---
const PRACTICE_LEAD_IN := 3.0
var practice_active := false
var practice_start_seconds := 0.0
var audio_start_position := 0.0
var _saved_music_speed := -1

var player_rig: Node3D
var _sky_sphere: Node3D
var _sky_offset := Vector3.ZERO

func start_map(info: MapInfo, map_difficulty: DifficultyInfo) -> void:
	var map_data := Utils.binary_to_json(Utils.read_binary_file(info.filepath, map_difficulty.beatmap_filename))
	
	if (map_data.is_empty()):
		vr.log_error("Could not read map data from " + info.filepath + "/" + map_difficulty.beatmap_filename)
	if not map_difficulty.lightshow_filename.is_empty():
		var lightshow := Utils.binary_to_json(Utils.read_binary_file(info.filepath, map_difficulty.lightshow_filename))
		if not lightshow.is_empty():
			map_data["lightshow"] = lightshow
	NoodleAnim.set_point_definitions(map_data)
	if not Map.load_beatmap(info, map_difficulty, map_data):
		return
	
	audio_start_position = 0.0
	if practice_active:
		var start_beat := practice_start_seconds * Map.current_info.beats_per_minute / 60.
		Map.skip_to_beat(start_beat)
		audio_start_position = maxf(0.0, practice_start_seconds - PRACTICE_LEAD_IN)
		
	event_driver.set_background_texture()
	
	update_left_color(Map.color_left)
	update_right_color(Map.color_right)
	event_driver.set_background()
	
	if Map.event_stack.is_empty():
		event_driver.set_all_on(Map.color_left, Map.color_right)
	else:
		event_driver.set_all_off()
	
	var filename := info.filepath + info.song_filename
	vr.log_info("loading: " + filename)
	if FileAccess.file_exists(filename):
		song_player.stream = AudioStreamOggVorbis.load_from_file(filename)
	else:
		var audio_data : PackedByteArray
		audio_data = Utils.read_binary_file(info.filepath, info.song_filename)
		if len(audio_data) > 0:
			song_player.stream = AudioStreamOggVorbis.load_from_buffer(audio_data)
		else:
			vr.log_info("playing silence")
			var wav := AudioStreamWAV.new()
			wav.set_stereo(false)
			wav.set_format(AudioStreamWAV.FORMAT_8_BITS)
			wav.set_mix_rate(11025)
			var length := ceili((Map.current_info.get_length_seconds() + 2) * wav.mix_rate)
			var data := PackedByteArray()
			data.resize(length) 
			data.fill(0)
			wav.set_data(data)
			song_player.stream = wav
	
	_audio_synced_after_restart = false
	song_player.play(audio_start_position)
	song_player.volume_db = 0.0
	song_player.pitch_scale = Settings.music_speed / 100.
	_in_wall = false
	Scoreboard.restart()
	
	_display_points()
	percent_indicator.start_map()
	percent_indicator.set_health_mode(Settings.health_mode)
	if Settings.health_mode:
		current_health = Constants.HEALTH_START
		percent_indicator.update_percent(current_health / Constants.HEALTH_MAX)
	
	_clear_track()
	chroma_env.hidden_registry = event_driver.chroma_hidden
	chroma_env.apply(map_data)
	chroma_env.apply(map_data)
	chroma_env.apply_removal(map_difficulty.custom_data)
	NoodleTracks.load_map(map_data)
	_transition_game_state(gamestate_playing)

func start_practice(info: MapInfo, map_difficulty: DifficultyInfo, speed_percent: int, start_seconds: float) -> void:
	if _saved_music_speed < 0:
		_saved_music_speed = Settings.music_speed
	Settings.music_speed = speed_percent
	practice_active = true
	practice_start_seconds = start_seconds
	start_map(info, map_difficulty)

func _end_practice() -> void:
	practice_active = false
	if _saved_music_speed >= 0:
		Settings.music_speed = _saved_music_speed
		_saved_music_speed = -1

var _practice_info: MapInfo
var _practice_difficulty: DifficultyInfo

func _on_practice_requested(info: MapInfo, difficulty: DifficultyInfo) -> void:
	_practice_info = info
	_practice_difficulty = difficulty
	(practice_canvas.ui_control as PracticePanel).setup(info, difficulty)
	_transition_game_state(gamestate_practice)

func _on_practice_start(speed_percent: int, start_seconds: float) -> void:
	start_practice(_practice_info, _practice_difficulty, speed_percent, start_seconds)

func _on_practice_back() -> void:
	_transition_game_state(gamestate_mapselection)

func update_health(delta: float) -> void:
	if Settings.health_mode:
		current_health += delta
		if current_health > Constants.HEALTH_MAX:
			current_health = Constants.HEALTH_MAX
		percent_indicator.update_percent(current_health / Constants.HEALTH_MAX)
		if current_health < 0:
			_on_song_ended()
			
func _transition_game_state(next_state: GameState) -> void:
	if next_state == gamestate_mapselection:
		_end_practice()
	if practice_canvas:
		practice_canvas._hide()
	if next_state != gamestate_playing:
		player_rig.transform = Transform3D.IDENTITY
	gamestate = next_state
	gamestate._ready(self)

func show_MapSourceDialogs(showing: bool = true) -> void:
	map_source_dialogs.visible = showing
	for c in map_source_dialogs.get_children():
		if c is OQ_UI2DCanvas:
			(c as OQ_UI2DCanvas)._hide()
	if showing:
		var first_dialog := map_source_dialogs.get_child(0)
		if first_dialog is OQ_UI2DCanvas:
			(first_dialog as OQ_UI2DCanvas)._show()

func _submit_highscore(player_name: String) -> void:
	if gamestate == gamestate_newhighscore:
		Highscores.add_highscore(
			Map.current_info,
			Map.current_difficulty.difficulty_rank,
			player_name,
			Scoreboard.points)
			
		_transition_game_state(gamestate_mapcomplete)

func _check_and_update_saber(controller: BeepSaberController, saber: LightSaber) -> void:
	if ((not song_player.playing)
		and (controller.ax_just_pressed() or controller.by_just_pressed())
		and (not saber._anim.is_playing())):
		if (saber.is_extended()): saber._hide()
		else: saber._show()
		
	if _in_wall:
		Scoreboard.enter_wall()
	
	if not controller.is_simple_rumbling(): 
		if _in_wall:
			controller.simple_rumble(0.3, 0.3)
		elif saber.get_overlapping_areas().size() > 0 or saber.get_overlapping_bodies().size() > 0:
			controller.simple_rumble(0.5, 0.1)
		else:
			controller.simple_rumble(0.0, 0.1)

func _update_noodle_player_rig() -> void:
	if player_rig == null:
		return
	if gamestate != gamestate_playing:
		player_rig.transform = Transform3D.IDENTITY
		return
	var trk := NoodleTracks.current
	if trk != null and trk.MOVE_PLAYER:
		player_rig.transform = trk.player_transform()
	else:
		player_rig.transform = Transform3D.IDENTITY

func _physics_process(_dt: float) -> void:
	Scoreboard.score_changed.emit()
	
	if debug_info_label.visible:
		var dbg_text := "FPS: %d\nCube Pool: %d free of %d\nLink Pool: %d free of %d" % [
			Engine.get_frames_per_second(),
			GlobalReferences.cube_pool.free_count(), GlobalReferences.cube_pool.total_count(),
			GlobalReferences.link_pool.free_count(), GlobalReferences.link_pool.total_count()]
		if Map.is_v4 and Map.current_info != null and Map.current_difficulty != null:
			var now_beat := song_player.get_playback_position() * Map.current_info.beats_per_minute / 60.0
			dbg_text += "\nv4 NJS base: %.1f  now: %.1f\nlast note NJS: %.1f (beat %.2f)\nNJS events: %d" % [
				Map.current_difficulty.note_jump_movement_speed, Map.get_njs_at_beat(now_beat),
				Map.last_note_njs, Map.last_note_beat, Map.njs_events.size()]
		(debug_info_label.mesh as TextMesh).text = dbg_text
	
	gamestate._physics_process(self)
	_update_noodle_player_rig()
	if _sky_sphere != null:
		_sky_sphere.global_position = player_rig.global_position + _sky_offset
	
	_check_and_update_saber(left_controller, left_saber)
	_check_and_update_saber(right_controller, right_saber)

func _enter_tree() -> void:
	GlobalReferences.main_game_scene = self
	
	@warning_ignore("return_value_discarded")
	Settings.changed.connect(on_settings_changed)

func _ready() -> void:
	_create_player_rig()
	
	GlobalReferences.cube_pool = $BeepCubePool
	GlobalReferences.link_pool = $ChainLinkPool
	GlobalReferences.cube_pool.presize(160)
	GlobalReferences.link_pool.presize(100)
	
	var xr_camera := xr_origin.get_node("XRCamera3D") as XRCamera3D
	vr.initialize(
		xr_origin,
		xr_camera,
		left_controller,
		right_controller
	)
	
	vr.pose_recentered.connect(recenter)

	debug_info_label.visible = Settings.show_debug_info
	set_colors_from_settings()
	($WorldEnvironment as WorldEnvironment).environment.glow_enabled = Settings.glare
	
	if not vr.inVR:
		xr_origin.add_child(preload("res://OQ_Toolkit/OQ_ARVROrigin/Feature_VRSimulator.tscn").instantiate())
	
	UI_AudioEngine.attach_children(highscore_keyboard)
	UI_AudioEngine.attach_children(online_search_keyboard)
	
	var upload_label := settings_panel.find_child("upload_url", true, false) as Label
	if upload_label:
		if menu.song_uploader_ref and menu.song_uploader_ref.active:
			upload_label.text = "Manually Upload Songs/Backgrounds: \n%s" % [
				menu.song_uploader_ref.get_server_url()
			]
		else:
			upload_label.text = ""
	
	if practice_canvas:
		var practice_panel := practice_canvas.ui_control as PracticePanel
		practice_panel.start_pressed.connect(_on_practice_start)
		practice_panel.back_pressed.connect(_on_practice_back)
		menu.practice_requested.connect(_on_practice_requested)
	
	_transition_game_state(gamestate_mapselection)
	
	@warning_ignore("return_value_discarded")
	Scoreboard.score_changed.connect(_display_points)
	@warning_ignore("return_value_discarded")
	Scoreboard.points_awarded.connect(points_label_driver.show_points)
	
	($pre_renderer as Node3D).visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	($pre_renderer as Node3D).queue_free()
	
	set_background_texture()
	
	recenter()

func set_background_texture() -> void:
	var environment : Environment = $WorldEnvironment.environment
	var panorama : PanoramaSkyMaterial = environment.sky.sky_material 
	panorama.panorama = load(Settings.background_texture)	
	
func on_settings_changed(key: StringName) -> void:
	await get_tree().process_frame
	match key:
		&"left_handed":
			if Settings.left_handed:
				left_ui_raycast.active = true
				right_ui_raycast.active = false
			else:
				left_ui_raycast.active = false
				right_ui_raycast.active = true
		&"color_left":
			update_left_color(Settings.color_left)
		&"color_right":
			update_right_color(Settings.color_right)
		&"width":
			event_driver.set_background()
		&"background":
			event_driver.set_background()
		&"background_texture":
			set_background_texture()
			event_driver.set_background_texture()
		&"show_debug_info":
			debug_info_label.visible = Settings.show_debug_info
		&"glare":
			($WorldEnvironment as WorldEnvironment).environment.glow_enabled = Settings.glare
		&"player_height_offset":
			xr_origin.transform.origin.y = Settings.player_height_offset

func set_colors_from_settings() -> void:
	update_left_color(Settings.color_left)
	update_right_color(Settings.color_right)
	event_driver.set_background()

func update_left_color(color: Color) -> void:
	if !left_saber:
		await get_tree().process_frame
	left_saber.set_color(color)
	Arc.left_material.set_shader_parameter(&"color", color)
	Arc.left_material_magnet.set_shader_parameter(&"color", color)
	goggles_shader.set_shader_parameter(&"left_color", color)
	event_driver.update_left_color(color)
	standing_ground.update_left_color(color)

func update_right_color(color: Color) -> void:
	if !left_saber:
		await get_tree().process_frame
	right_saber.set_color(color)
	Arc.right_material.set_shader_parameter(&"color", color)
	Arc.right_material_magnet.set_shader_parameter(&"color", color)
	goggles_shader.set_shader_parameter(&"right_color", color)
	event_driver.update_right_color(color)
	standing_ground.update_right_color(color)

func _clear_track() -> void:
	player_rig.transform = Transform3D.IDENTITY
	gamestate_playing.reset_batch_stack()
	chroma_env.restore()
	for c in track.get_children():
		if c.has_method("clear_from_track"):
			c.clear_from_track()
		else:
			track.remove_child(c)
			c.queue_free()

func _display_points() -> void:
	var hit_rate: float
	if Scoreboard.right_notes+Scoreboard.wrong_notes > 0:
		hit_rate = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	else:
		hit_rate = 1.0
	
	var minutes = 0
	var seconds = 0
	if Map.current_info != null:
		var time_left = Map.current_info.get_length_seconds() - get_current_time()
		if time_left < 0:
			time_left = 0
		minutes = int(time_left) / 60
		seconds = int(time_left) % 60
	var display = "Score %6d\n%02d:%02d" % [Scoreboard.points,minutes,seconds]
	if (point_label.mesh as TextMesh).text != display:
		(point_label.mesh as TextMesh).text = display
	display = "x %d\nCombo %d" % [Scoreboard.multiplier, Scoreboard.combo]
	if (multiplier_label.mesh as TextMesh).text != display:
		(multiplier_label.mesh as TextMesh).text = display
	if not Settings.health_mode:
		percent_indicator.update_percent(hit_rate)

func _name_selector() -> NameSelector:
	return name_selector_canvas.ui_control

func _on_PlayerHead_area_entered(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = -15.0
		_in_wall = true
		Scoreboard.enter_wall()

func _on_PlayerHead_area_exited(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = 0.0
		_in_wall = false
		Scoreboard.exit_wall()
		
func get_current_time() -> float:
	return song_player.get_playback_position()

func _on_song_ended() -> void:
	song_player.stop()
	if not practice_active:
		PlayCount.increment_play_count(Map.current_info,Map.current_difficulty.difficulty_rank)
	
	var new_record := false
	var highscore := Highscores.get_highscore(Map.current_info,Map.current_difficulty.difficulty_rank)
	if practice_active:
		highscore = Scoreboard.points
	elif highscore == -1:
		highscore = Scoreboard.points
	elif Scoreboard.points > highscore:
		highscore = Scoreboard.points
		new_record = true

	var current_percent : float
	if Settings.health_mode and current_health <= 0:
		current_percent = -1
	else:
		current_percent = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes) 
	endscore.show_score(
		Scoreboard.points,
		highscore,
		current_percent,
		"%s By %s\n%s     Map author: %s" % [
			Map.current_info.song_name,
			Map.current_info.song_author_name,
			Map.current_difficulty.get_display_name(),
			Map.current_info.level_author_name],
		Scoreboard.full_combo,
		new_record
	)
	
	if not practice_active and Highscores.is_new_highscore(Map.current_info,Map.current_difficulty.difficulty_rank,Scoreboard.points):
		_transition_game_state(gamestate_newhighscore)
	else:
		_transition_game_state(gamestate_mapcomplete)

func _restart_button() -> void:
	start_map(Map.current_info, Map.current_difficulty)
	endscore.visible = false
	pause_menu.visible = false

func _main_menu_button() -> void:
	_clear_track()
	_transition_game_state(gamestate_mapselection)

func _unpause_button() -> void:
	pause_menu.visible = false
	pause_countdown.visible = true
	track.visible = true
	pause_countdown.set_label_text("3")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("2")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("1")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.visible = false
	
	song_player.play(pause_position)
	_transition_game_state(gamestate_playing)

func _on_BeepSaberMainMenu_difficulty_changed(map_info: MapInfo, diff_rank: int) -> void:
	if diff_rank < 0:
		if highscore_canvas:
			highscore_canvas.hide()
		return
		
	if not highscore_canvas:
		await self.ready
	
	highscore_canvas._show()
	highscore_panel.load_highscores(map_info,diff_rank)

func _settings_button() -> void:
	settings_panel._update_backgrounds()
	_transition_game_state(gamestate_settings)

func _on_settings_Panel_apply() -> void:
	set_colors_from_settings()
	_transition_game_state(gamestate_mapselection)

func _on_ScenePool_new_scene_instanced(obj: Node3D, during_presizing: bool) -> void:
	track.add_child(obj)
	
	if during_presizing:
		obj.position.z = -2.0
		await get_tree().process_frame
		
		if obj is BeepCube:
			obj.hide_cube()
		elif obj is ChainLink:
			obj.hide_cube()
		else:
			obj.visible = false

func recenter():
	var xr_camera := xr_origin.get_node("XRCamera3D") as XRCamera3D
	var cam := player_rig.global_transform.affine_inverse() * xr_camera.global_transform
	xr_origin.rotation.y -= cam.basis.get_euler(EULER_ORDER_YXZ).y
	xr_origin.position -= (cam.origin * Vector3(1, 0, 1)) - Vector3(0, 0, 1)

func _set_hand(right: bool, hand: bool) -> void:
	var angle_offset := -45. if hand else 0.
	if right:
		right_saber.second_extra_offset_rot.x=angle_offset
		right_saber._update_size_and_angle()
	else:
		left_saber.second_extra_offset_rot.x=angle_offset
		left_saber._update_size_and_angle()

func _on_right_controller_profile_changed(role: String) -> void:
	if role.ends_with("/simple_controller"):
		_set_hand(true, true)
	else:
		_set_hand(true, false)

func _on_left_controller_profile_changed(role: String) -> void:
	if role.ends_with("/simple_controller"):
		_set_hand(false, true)
	else:
		_set_hand(false, false)

func _create_player_rig() -> void:
	player_rig = Node3D.new()
	player_rig.name = "PlayerRig"
	add_child(player_rig)
	xr_origin.reparent(player_rig, false)
	for n: String in ["Multiplier_Label", "Point_Label", "Percent_Indicator", "event_driver", "StandingGround"]:
		var node := get_node_or_null(n) as Node3D
		if node != null:
			node.reparent(player_rig, false)
	# the backdrop sphere follows the player's position only, never its rotation
	_sky_sphere = event_driver.get_node_or_null("Level/Sphere") as Node3D
	if _sky_sphere != null:
		_sky_offset = _sky_sphere.global_position   # the rig is still at identity here
		_sky_sphere.top_level = true                # keeps its current global transform, then ignores the parents
