extends Node3D
class_name Wall

var despawn_z: float
var speed: float
static var pool: Array = []   # untyped on purpose: entries can be freed on scene change
var _pooled := false

static func acquire() -> Wall:
	while not pool.is_empty():
		var w: Variant = pool.pop_back()
		if is_instance_valid(w) and (w as Wall).is_inside_tree():
			return w as Wall
	return null

func recycle() -> void:
	if _pooled: return
	_pooled = true
	visible = false
	set_physics_process(false)
	var area := $WallMeshOrientation/WallArea as Area3D
	area.monitorable = false
	area.monitoring = false
	pool.append(self)

func clear_from_track() -> void:
	recycle()

func _physics_process(delta: float) -> void:
	if Scoreboard.paused: return
	
	#transform.origin.z += speed * delta
	
	# remove children that go to far
	#if transform.origin.z > despawn_z:
	#	queue_free()
	
	transform.origin += speed * delta * transform.basis.z
	var rz := global_transform.origin.dot(transform.basis.z)
	
	if rz > despawn_z:
		recycle()
		return

	#transform.origin.x += speed * delta * sin(rotation.y)
	#transform.origin.z += speed * delta * cos(rotation.y)
	#
	#var rz := global_transform.rotated(Vector3(0,1,0), -rotation.y).origin.z
	#if rz > despawn_z:
	#	queue_free()
	

func spawn(wall_info: ObstacleInfo, current_beat: float) -> void:
	_pooled = false
	visible = true
	set_physics_process(true)
	var area := $WallMeshOrientation/WallArea as Area3D
	area.monitorable = true
	area.monitoring = true
	var mesh := $WallMeshOrientation/WallMesh as MeshInstance3D
	var x_size := wall_info.width * Settings.LANE_DISTANCE_X
	var y_size := wall_info.height * Constants.LANE_DISTANCE_Y
	var z_size := wall_info.duration * Constants.BEAT_DISTANCE
	var depth := z_size * 0.5
	var wall_size := Vector3(
	x_size if absf(x_size) > 0.001 else 0.001,
	y_size if absf(y_size) > 0.001 else 0.001,
	z_size if absf(z_size) > 0.001 else 0.001)
	mesh.scale = wall_size
	($WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D).scale = wall_size
	mesh.set_instance_shader_parameter(&"size", wall_size)
	despawn_z = Constants.MISS_Z + depth
	
	var x := (0.5 * wall_info.width + wall_info.line_index - 2) * Settings.LANE_DISTANCE_X
	var y := (0.5 * wall_info.height + wall_info.line_layer) * Constants.LANE_DISTANCE_Y
	var z := (current_beat - wall_info.beat) * Constants.BEAT_DISTANCE - depth
	
	var c := cos(wall_info.rotation)
	var s := sin(wall_info.rotation)
	
	transform.origin.x = c * x - s * z
	transform.origin.y = y
	transform.origin.z = s * x + c * z
		
	rotation.y = -wall_info.rotation
	
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute / 60.0
	($AnimationPlayer as AnimationPlayer).play(&"Spawn")
