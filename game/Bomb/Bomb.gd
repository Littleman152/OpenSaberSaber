extends Cuttable
class_name Bomb

@export var min_speed := 0.5
@onready var collision_shape := $Area3D/CollisionShape3D as CollisionShape3D

# Noodle: bombs with Noodle data (tracks, animation, own NJS/offset) are placed by NoodleMotion every
# frame instead of flying straight. Fake / uninteractable ones just never get a collision shape.
var _nm: NoodleMotion = null
var _can_hit := false      # interactable and not fake
var _coll_on := false

func set_collision_disabled(value: bool) -> void:
	collision_shape.disabled = value

@warning_ignore("unused_parameter")
func cut(saber: LightSaber, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> void:
	Scoreboard.bad_cut(transform.origin, lane_rotation, "bomb")
	queue_free()

func on_miss() -> void:
	queue_free()

func spawn(info: BombInfo, current_beat: float) -> void:
	var speed_scale := Map.get_speed_scale(info.beat) # v4 VNJS, 1.0 on every other map
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute / 60.0 * speed_scale
	beat = info.beat
	
	var distance: float = info.beat - current_beat
	var lane_xy := Vector2(
		Settings.LANE_DISTANCE_X * float(info.line_index) + Settings.LANE_ZERO_X,
		Constants.LANE_DISTANCE_Y * float(info.line_layer) + Constants.LAYER_ZERO_Y)
	transform.origin = Vector3(lane_xy.x, lane_xy.y, -distance * Constants.BEAT_DISTANCE * speed_scale)
	
	add_lane_rotation(info.rotation)
	_can_hit = info.interactable and not info.fake
	($Area3D/CollisionShape3D as CollisionShape3D).disabled = not _can_hit
	
	_nm = null
	_coll_on = false
	if info.noodle != null:
		_nm = NoodleMotion.new()
		_nm.setup(info.noodle, info.beat, current_beat, info.rotation, lane_xy, 0.0, speed_scale)
		# the scene's spawn animation is not played for these bombs: use its end state
		($BombAnimation as Node3D).transform = Transform3D.IDENTITY
		($BombAnimation as Node3D).visible = false   # hidden until NoodleMotion says it is alive
		($Area3D/CollisionShape3D as CollisionShape3D).disabled = true   # switched on when in reach
		return
	
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.get_object_njs(info.beat) / 9.0
	anim.speed_scale = maxf(min_speed, anim_speed)
	anim.play(&"Spawn")

func _physics_process(delta: float) -> void:
	if _nm == null:
		super(delta)
		return
	if Scoreboard.paused or not Map.current_info:
		return
	if not _nm.update():
		queue_free()
		return
	var mesh := $BombAnimation as Node3D
	if not _nm.visible:
		mesh.visible = false
		return
	transform = _nm.xf
	mesh.visible = _nm.opacity > 0.5
	
	if _can_hit:
		# time based reach / miss window, like Noodle notes
		var rel := _nm.beat_now - beat   # beats until (<0) / since (>0) the bomb reaches the player
		var reachable := mesh.visible and rel > -(3.0 / Constants.BEAT_DISTANCE)
		if reachable != _coll_on:
			_coll_on = reachable
			collision_shape.disabled = not reachable
		if rel > Constants.MISS_Z / Constants.BEAT_DISTANCE:
			on_miss()
