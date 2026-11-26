class_name NoodleMotion
extends RefCounted
# Shared Noodle Extensions motion for notes (later also bombs and chain links).
# Every frame update() works out where one object is, from its own _animation, its tracks,
# the track parents and the path animations, and leaves the result in xf / opacity / color.

# Playing.gd sets this once per frame, so every Noodle object uses the same song clock.
static var song_beat := 0.0
static var _dbg_frame := -1

const PRE_SPAWN_BEATS := 4.0    # visible at least this many beats ahead, like normal notes
const FADE_IN_BEATS := 0.75     # fade in after appearing (the cube shader dissolves it)
const MAX_FROZEN_BEATS := 64.0  # safety: an object held by a track's "time" is dropped after this

var info: ObstacleInfo
var tracks := PackedStringArray()
var anim := {}
var resolved := true
var spawn_beat := 0.0
var start_beat := 0.0           # beat - half jump distance
var visible_from := 0.0
var life_beats := 1.0
var hjd := 4.0
var beat_now := 0.0
var lane_angle := 0.0
var lane_xy := Vector2.ZERO
var roll := 0.0                 # extra rotation around z (the cut direction of a note)
var speed_scale := 1.0
var scale_mul := Vector3.ONE    # e.g. the block size setting

var _world_basis := Basis.IDENTITY
var _local_basis := Basis.IDENTITY
var _base_scale := Vector3.ONE
var _offset := Vector3.ZERO

# results of the last update()
var xf := Transform3D.IDENTITY
var opacity := 1.0
var arrow_opacity := 1.0
var has_color := false
var color := Color.WHITE
var visible := false


func setup(nd: ObstacleInfo, object_beat: float, current_beat: float, p_lane_angle: float, p_lane_xy: Vector2, p_roll := 0.0, p_speed_scale := 1.0) -> void:
	info = nd
	tracks = nd.tracks
	var bpm: float = Map.current_info.beats_per_minute
	hjd = WallBatch._half_jump(nd, bpm)
	start_beat = object_beat - hjd
	visible_from = minf(start_beat, object_beat - PRE_SPAWN_BEATS)
	life_beats = 2.0 * hjd
	beat_now = current_beat
	spawn_beat = current_beat
	lane_angle = p_lane_angle
	lane_xy = p_lane_xy
	roll = p_roll
	speed_scale = p_speed_scale
	anim = nd.anim
	resolved = tracks.is_empty()
	_world_basis = WallBatch._euler_basis(nd.nd_rotation)
	_local_basis = WallBatch._euler_basis(nd.nd_local_rotation)
	_base_scale = nd.nd_scale if nd.has_scale else Vector3.ONE
	var unit := Vector3(Settings.LANE_DISTANCE_X, Constants.LANE_DISTANCE_Y, Settings.LANE_DISTANCE_X)
	_offset = Vector3(nd.nd_position.x * unit.x, nd.nd_position.y * unit.y, 0.0)


func _resolve_paths(trk: NoodleTracks) -> void:
	resolved = true
	var merged := info.anim.duplicate()
	if trk != null:
		for tname: String in tracks:
			var pa: Dictionary = trk.path_animation(tname, spawn_beat)
			for k: String in pa:
				merged[k] = pa[k]
	anim = merged


# Returns false when the object is finished and should be released.
func update() -> bool:
	var trk := NoodleTracks.current
	if not resolved and trk != null:
		_resolve_paths(trk)

	beat_now = song_beat
	if beat_now < visible_from:
		visible = false
		return true

	var life_t := (beat_now - start_beat) / life_beats
	if life_t >= 1.0:
		return false

	# a track's "time" overrides how far along its lifetime the object is (0.5 = at the player)
	var t := life_t
	if trk != null:
		for tname: String in tracks:
			var tm := trk.state(tname).time
			if tm >= 0.0:
				t = tm
	if t >= 1.0 or beat_now > start_beat + life_beats + MAX_FROZEN_BEATS:
		return false
	t = maxf(t, 0.0)   # before its own start the animation stays on its first frame

	var unit := Vector3(Settings.LANE_DISTANCE_X, Constants.LANE_DISTANCE_Y, Settings.LANE_DISTANCE_X)
	var sc := _base_scale * scale_mul
	var world_b := _world_basis
	var local_b := _local_basis
	var alpha := info.nd_alpha
	opacity = 1.0
	arrow_opacity = 1.0
	has_color = info.nd_has_color
	color = info.nd_color
	var anim_pos := Vector3.ZERO

	if anim.has("position"):
		var av := NoodleAnim.sample(anim["position"], t)
		anim_pos = Vector3(av.x * unit.x, av.y * unit.y, -av.z * unit.z)
	if anim.has("scale"):
		var sv := NoodleAnim.sample(anim["scale"], t)
		sc *= Vector3(sv.x, sv.y, sv.z)
	if anim.has("rotation"):
		world_b = Basis(NoodleAnim.sample_rotation(anim["rotation"], t))
	if anim.has("local_rotation"):
		local_b = Basis(NoodleAnim.sample_rotation(anim["local_rotation"], t))
	if anim.has("dissolve"):
		opacity = clampf(NoodleAnim.sample(anim["dissolve"], t).x, 0.0, 1.0)
	if anim.has("dissolve_arrow"):
		arrow_opacity = clampf(NoodleAnim.sample(anim["dissolve_arrow"], t).x, 0.0, 1.0)
	if anim.has("color"):
		var cv := NoodleAnim.sample(anim["color"], t)
		color = Color(cv.x, cv.y, cv.z, 1.0)
		has_color = true
		alpha = cv.w

	var trk_pos := Vector3.ZERO
	var parent_xf := Transform3D.IDENTITY
	if trk != null and not tracks.is_empty():
		for tname: String in tracks:
			var ts := trk.state(tname)
			sc *= ts.scale
			trk_pos += ts.position
			world_b = Basis(ts.rot_q) * world_b
			local_b = local_b * Basis(ts.local_rot_q)
			opacity *= ts.dissolve
			if ts.has_color:
				color = Color(ts.color.r, ts.color.g, ts.color.b, 1.0)
				has_color = true
				alpha = ts.color.a
		parent_xf = trk.parent_transform(tracks[0])
	if alpha >= 0.0:
		opacity *= minf(alpha, 1.0)

	# smooth fade in after appearing (the cube shader turns this into its burning dissolve)
	opacity *= clampf((beat_now - visible_from) / FADE_IN_BEATS, 0.0, 1.0)

	var z := (t * life_beats - hjd) * Constants.BEAT_DISTANCE * speed_scale
	var cs := cos(lane_angle)
	var sn := sin(lane_angle)
	var pos := Vector3(cs * lane_xy.x - sn * z, lane_xy.y, sn * lane_xy.x + cs * z)
	var b := Basis(Vector3.UP, -lane_angle) * Basis(Vector3(0.0, 0.0, 1.0), roll)
	if anim.has("def_pos"):
		var pv := NoodleAnim.sample(anim["def_pos"], t)
		pos = Vector3(pv.x * unit.x, pv.y * unit.y, -pv.z * unit.z)
		if WallBatch.POSITION_ADDS_TO_DEFINITE:
			pos += _offset
		b = Basis(Vector3(0.0, 0.0, 1.0), roll)
	else:
		pos += _offset
	pos += trk_pos + anim_pos
	pos = world_b * pos
	b = world_b * b * local_b

	var world_xf := Transform3D.IDENTITY
	if trk != null:
		world_xf = trk.player_inverse()
	xf = world_xf * parent_xf * Transform3D(b.scaled_local(sc), pos)
	visible = true
	return true
