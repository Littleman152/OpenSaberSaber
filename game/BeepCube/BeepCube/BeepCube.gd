# BeepCube is the standard cube that will get cut by the sabers
extends Cuttable
class_name BeepCube

# emitted when the cube gets cutted, correct_saber is true if the right saber was used
signal cutted(correct_saber: bool)

@onready var mi := $BeepCubeMesh as MeshInstance3D
@onready var collision_big := $BeepCube_Big/CollisionBig as CollisionShape3D
@onready var collision_small := $BeepCube_Small/CollisionSmall as CollisionShape3D
@onready var slice_particles := $SliceParticles as BeepCubeSliceParticles

var which_saber: int
var is_dot: bool

# we store the mesh here as part of the BeepCube for easier access because we will
# reuse it when we create the cut cube pieces
var _mesh: Mesh
var _mat: ShaderMaterial
@export var min_speed := 0.5

var piece_left : CutPiece = null
var piece_right : CutPiece = null
var arc_head = false
var arc_tail = false
var chain_head = false
var counts_for_score := true

# Noodle: notes with Noodle data are placed by NoodleMotion every frame instead of flying straight
var _nm: NoodleMotion = null
var _cur_color := Color.WHITE
var _coll_on := false
var _last_dissolve := -1.0
var _last_arrow := -1.0
var _last_color := Color(-1, -1, -1)
func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mesh = mi.mesh
	
	# init our cut pieces with unique copies of our own material for reference,
	# and enable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	
	# slice_particles are within cube's tree, but want then to move in global space
	slice_particles.top_level = true
	
func spawn(note_info: ColorNoteInfo, current_beat: float) -> void:
	# re-enable our process_mode first otherwise it seems like Godot-internals
	# can behave weirdly (ex. AnimationPlayer won't always play correctly)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_nm = null
	var color := Map.color_left if note_info.color == 0 else Map.color_right
	if note_info.noodle != null and note_info.noodle.nd_has_color:
		color = note_info.noodle.nd_color
	_cur_color = color
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667
	beat = note_info.beat
	which_saber = note_info.color
	is_dot = note_info.cut_angle >= Constants.DIRECTION8_COMPARE
	
	if is_dot:
		(collision_big.shape as BoxShape3D).size.y = 0.8
	else:
		(collision_big.shape as BoxShape3D).size.y = 0.5
		
	scale = Vector3(Settings.block_size/100.,Settings.block_size/100.,Settings.block_size/100.)
	transform.origin.x = Settings.LANE_DISTANCE_X * float(note_info.line_index) + Settings.LANE_ZERO_X
	transform.origin.y = Constants.LANE_DISTANCE_Y * float(note_info.line_layer) + Constants.LAYER_ZERO_Y
	transform.origin.z = -(note_info.beat - current_beat) * Constants.BEAT_DISTANCE
	
	add_lane_rotation(note_info.rotation)
	
	rotation.z = note_info.cut_angle
	
	piece_left.set_color(color, is_dot)
	piece_right.set_color(color, is_dot)
	_mat.set_shader_parameter(&"color", color)
	_mat.set_shader_parameter(&"is_dot", is_dot)
	_mat.set_shader_parameter(&"arrows_enabled", Settings.arrows_enabled)
	# since cube instances get recycled, we gotta reset cubes that were chain
	# heads in a past life
	_mat.set_shader_parameter(&"is_chain_head", false)
	piece_left.set_chain_head(false)
	piece_right.set_chain_head(false)
	chain_head = false
	
	# separate cube collision layers to allow a diferent collider on right/wrong cuts.
	# opposing collision layers (ie. right note & left saber) will be placed on the
	# smalling collision shape, while similar collision layers (ie right note &
	# right saber) are placed on the larger collision shape.
	var is_left_note := note_info.color == 0
	var big_coll_area := $BeepCube_Big as Area3D
	big_coll_area.collision_layer = 0x0
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, is_left_note)
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, not is_left_note)
	var small_coll_area := $BeepCube_Small as Area3D
	small_coll_area.collision_layer = 0x0
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, not is_left_note)
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, is_left_note)
	
	# play the spawn animation when this cube enters the scene
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed,anim_speed)
	anim.play(&"Spawn")
	if note_info.noodle != null:
		# Noodle notes skip the spawn animation: jump to its end state
		anim.seek(anim.current_animation_length, true)
		anim.stop(true)
	
	slice_particles.reset()
	mi.visible = true
	
	# Noodle: fake / uninteractable notes can't be cut and never count as a miss
	counts_for_score = note_info.interactable and not note_info.fake
	set_collision_disabled(not counts_for_score)
	# fake / uninteractable notes only show their arrow or dot
	_mat.set_shader_parameter(&"glyph_only", not counts_for_score)
	_mat.set_shader_parameter(&"dissolve", 0.0)
	_mat.set_shader_parameter(&"dissolve_arrow", 0.0)
	# the shader's own spawn dissolve works on world z, Noodle notes fade in through NoodleMotion instead
	_mat.set_shader_parameter(&"spawn_dissolve_length", 0.0 if note_info.noodle != null else 6.0)
	_last_dissolve = 0.0
	_last_arrow = 0.0
	_last_color = color
	_coll_on = false
	if note_info.noodle != null:
		_setup_noodle(note_info, current_beat)

func _setup_noodle(note_info: ColorNoteInfo, current_beat: float) -> void:
	lane_rotation = note_info.rotation
	_nm = NoodleMotion.new()
	var lane_xy := Vector2(
		Settings.LANE_DISTANCE_X * float(note_info.line_index) + Settings.LANE_ZERO_X,
		Constants.LANE_DISTANCE_Y * float(note_info.line_layer) + Constants.LAYER_ZERO_Y)
	_nm.setup(note_info.noodle, note_info.beat, current_beat, note_info.rotation, lane_xy, note_info.cut_angle, Map.get_speed_scale(note_info.beat))
	_nm.scale_mul = Vector3.ONE * (Settings.block_size / 100.0)
	mi.visible = false   # hidden until NoodleMotion says it is alive
	set_collision_disabled(true)   # switched on by _physics_process when the note is within reach

func _physics_process(delta: float) -> void:
	if _nm == null:
		super(delta)
		return
	if Scoreboard.paused or not Map.current_info:
		return
	if not _nm.update():
		hide_cube()
		release()
		return
	if not _nm.visible:
		mi.visible = false
		return
	transform = _nm.xf
	mi.visible = _nm.opacity > 0.004
	_apply_noodle_visuals()

	if counts_for_score:
		# time based reach / miss window (a straight flight can't be assumed any more)
		var rel := _nm.beat_now - beat   # beats until (<0) / since (>0) the note reaches the player
		var reachable := mi.visible and rel > -(3.0 / Constants.BEAT_DISTANCE)
		if reachable != _coll_on:
			_coll_on = reachable
			set_collision_disabled(not reachable)
		if rel > Constants.MISS_Z / Constants.BEAT_DISTANCE:
			on_miss()

func _apply_noodle_visuals() -> void:
	var d := 1.0 - _nm.opacity
	if not is_equal_approx(d, _last_dissolve):
		_last_dissolve = d
		_mat.set_shader_parameter(&"dissolve", d)
	var a := 1.0 - _nm.arrow_opacity
	if not is_equal_approx(a, _last_arrow):
		_last_arrow = a
		_mat.set_shader_parameter(&"dissolve_arrow", a)
	if _nm.has_color and _nm.color != _last_color:
		_last_color = _nm.color
		_cur_color = _nm.color
		_mat.set_shader_parameter(&"color", _nm.color)

# call this when clearing the track
func clear_from_track() -> void:
	hide_cube()
	piece_left.hide_piece()
	piece_right.hide_piece()
	if ! is_released():
		release()

func hide_cube() -> void:
	_nm = null
	mi.visible = false
	set_collision_disabled(true)
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED

func make_chain_head() -> void:
	_mat.set_shader_parameter(&"is_chain_head", true)
	piece_left.set_chain_head(true)
	piece_right.set_chain_head(true)
	chain_head = true

func on_miss() -> void:
	if counts_for_score:
		Scoreboard.bad_cut(global_transform.origin+Vector3(0,0,-3.5), lane_rotation, "miss")
	hide_cube()
	release()

func set_collision_disabled(value: bool) -> void:
	collision_big.disabled = value
	collision_small.disabled = value
	
func set_arc_head() -> void:
	arc_head = true

func set_arc_tail() -> void:
	arc_tail = true

func cut(saber: LightSaber, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> void:
	if not counts_for_score:
		return
	# compute the angle between the cube orientation and the cut direction
	cut_speed = cut_speed.rotated(Vector3(0,1,0), -rotation.y)
	var cut_direction_xy := -Vector3(cut_speed.x, cut_speed.y, 0.0).normalized()
	var base_cut_angle_accuracy := global_transform.basis.orthonormalized().y.dot(cut_direction_xy)
	var cut_distance := cut_plane.distance_to(global_transform.origin)
	var distance_scale := 100./Settings.block_size
	
	if saber.type == which_saber or Map.one_saber or Settings.handedness != 0:
		var cut_angle_accuracy := clampf((base_cut_angle_accuracy-0.7)/0.3, 0.0, 1.0)
		if is_dot or not Settings.arrows_enabled: #ignore angle if is a dot
			cut_angle_accuracy = 1.0
		var cut_distance_accuracy := clampf((0.1 - absf(cut_distance*distance_scale))/0.1, 0.0, 1.0)
		var travel_distance_factor := controller.movement_aabb.get_longest_axis_size()
		travel_distance_factor = clampf((travel_distance_factor-0.5)/0.5, 0.0, 1.0)
		# allows a bit of save margin where the beat is considered 100% correct
		var dz := global_transform.origin.z
		if _nm != null:
			dz = (_nm.beat_now - beat) * Constants.BEAT_DISTANCE   # Noodle notes don't sit on a straight line
		var beat_accuracy := clampf((1.0 - absf(dz)) / 0.5, 0.0, 1.0)
		Scoreboard.note_cut(saber, transform.origin, lane_rotation, beat_accuracy, cut_angle_accuracy, cut_distance_accuracy, travel_distance_factor, arc_head, arc_tail, chain_head)
		cutted.emit(true)
	else:
		Scoreboard.bad_cut(transform.origin, lane_rotation, "wrong saber")
		cutted.emit(false)
	
	# reset the movement tracking volume for the next cut
	controller.reset_movement_aabb()
	
	hide_cube()
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release() # release now instead of waiting for cut pieces to die off

# cut the cube by creating two rigid bodies and using a CSGBox to create
# the cut plane
func _start_cut_pieces(cutplane: Plane) -> void:
	piece_left.set_color(_cur_color, is_dot)   # Noodle may have animated the color since spawn
	piece_right.set_color(_cur_color, is_dot)
	piece_left.scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	piece_right.scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	piece_left.global_transform = global_transform
	piece_right.global_transform = global_transform
	
	# calculate angle and position of the cut
	#var cut_angle_abs := Vector2(cutplane.normal.x, cutplane.normal.y).angle()
	
	_piece_death_count = 0

	var p := cutplane # ARP: fix rot global_transform * 
	piece_left.start_cut_plane(-p.normal, -p.d) # ARP: scale p.d for block size?
	piece_right.start_cut_plane(p.normal, p.d)
	
	# some impulse so the cube half moves
	var split_vector := p.normal * 2.0
	piece_left.apply_central_impulse(-split_vector) #piece_left.transform * -split_vector)
	piece_right.apply_central_impulse(split_vector)#piece_right.transform * split_vector)
	
	#slice_particles.global_transform.origin = global_transform.origin
	#slice_particles.rotation.z = cut_angle_abs+TAU*0.25
	#slice_particles.fire()
