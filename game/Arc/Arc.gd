extends Node3D
class_name Arc

static var left_material := load("res://game/Arc/Arc.material").duplicate() as ShaderMaterial
static var right_material := left_material.duplicate() as ShaderMaterial

static var left_material_magnet := left_material.duplicate() as ShaderMaterial
static var right_material_magnet := right_material.duplicate() as ShaderMaterial

@onready var visual: CSGPolygon3D = $Path3D/Visual

var arc_info: ArcInfo
var activator_cube: BeepCube

var speed: float
var despawn_z: float

func spawn(info: ArcInfo, current_beat: float, _activator_cube: BeepCube = null) -> void:
	arc_info = info
	
	if abs(arc_info.head_rotation-arc_info.tail_rotation) > Constants.ROTATION_EPS: # or abs(arc_info.tail_rotation) > Constants.ROTATION_EPS:
		# TODO: arcs will twist if rotations are different
		queue_free()
		return
	
	# the whole arc uses the speed of its head note (v4 VNJS, 1.0 on every other map)
	var speed_scale := Map.get_speed_scale(info.head_beat)
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute * 0.016666666666666667 * speed_scale
	var path := $Path3D as Path3D
	visual = $Path3D/Visual
	visual.material_override = right_material if arc_info.color == 1 else left_material
	activator_cube = _activator_cube
	if activator_cube:
		activator_cube.cutted.connect(_on_activator_cube_cutted)
	else:
		start_magnet()
	
	var curve := info.curve
	if absf(speed_scale - 1.0) > 0.001:
		# stretch a copy of the curve along z, the same way the notes are
		var z_scale := Vector3(1.0, 1.0, speed_scale)
		curve = info.curve.duplicate() as Curve3D
		for point_id in curve.point_count:
			curve.set_point_position(point_id, curve.get_point_position(point_id) * z_scale)
			curve.set_point_in(point_id, curve.get_point_in(point_id) * z_scale)
			curve.set_point_out(point_id, curve.get_point_out(point_id) * z_scale)
	path.set_curve(curve)
	despawn_z = Constants.MISS_Z - speed_scale * (info.tail_pos.z + current_beat*Constants.BEAT_DISTANCE)
	
	# sets the origin of the tail at the tail point to use in the shader for a fade out effect
	path.position = Vector3(info.tail_pos.x, info.tail_pos.y, speed_scale * (info.tail_pos.z + current_beat*Constants.BEAT_DISTANCE))
	rotation.y = -arc_info.head_rotation

func _on_activator_cube_cutted(correct_saber: bool) -> void:
	if activator_cube and activator_cube.cutted.is_connected(_on_activator_cube_cutted):
		activator_cube.cutted.disconnect(_on_activator_cube_cutted)
	if correct_saber:
		start_magnet()

# sets the magnet version of the material (and ensures correct magnet parameter)
func start_magnet() -> void:
	visual.material_override = right_material_magnet if arc_info.color == 1 else left_material_magnet
	visual.material_override.set_shader_parameter(&"saber_magnet", arc_info.color+1)

func _process(delta: float) -> void:
	if Scoreboard.paused or not is_visible_in_tree() or not Map.current_info: return
	transform.origin += speed * delta * transform.basis.z
	if transform.origin.dot(transform.basis.z) >= despawn_z:
		if activator_cube and activator_cube.cutted.is_connected(_on_activator_cube_cutted):
			activator_cube.cutted.disconnect(_on_activator_cube_cutted)
		queue_free()
