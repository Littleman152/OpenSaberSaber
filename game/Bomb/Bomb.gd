extends Cuttable
class_name Bomb

@export var min_speed := 0.5
@onready var collision_shape := $Area3D/CollisionShape3D as CollisionShape3D

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
	
	transform.origin.x = Settings.LANE_DISTANCE_X * float(info.line_index) + Settings.LANE_ZERO_X
	transform.origin.y = Constants.LANE_DISTANCE_Y * float(info.line_layer) + Constants.LAYER_ZERO_Y
	transform.origin.z = -distance * Constants.BEAT_DISTANCE * speed_scale
	
	add_lane_rotation(info.rotation)
	
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.get_object_njs(info.beat) / 9.0
	anim.speed_scale = maxf(min_speed, anim_speed)
	anim.play(&"Spawn")
	($Area3D/CollisionShape3D as CollisionShape3D).disabled = not info.interactable or info.fake
