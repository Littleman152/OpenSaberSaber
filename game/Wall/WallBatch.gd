extends MultiMeshInstance3D
class_name WallBatch
# Draws every uninteractable wall (Noodle text, tunnels, lasers...) with ONE draw call.
# Supports Noodle per-wall data: _scale, _position, _rotation, _localRotation, _color and
# _animation (_definitePosition, _scale, _rotation, _localRotation, _dissolve, _color).
# Not supported yet: track events (AnimateTrack / AssignTrackParent / AssignPathAnimation).
# Assumes the Track node sits at the origin.

const BASE_MATERIAL := "res://game/Wall/wall_new2.material"
const BATCH_SHADER := "res://game/Wall/wall_batched.gdshader"
const MAX_WALLS := 4096
const SPAWN_ANIM_TIME := 1.0     # matches the "Spawn" animation in Wall.tscn (non-Noodle walls)
const SPAWN_ANIM_EASE := 0.0883885

# ---- TUNING: my assumptions about Noodle, change these if the result looks off ----
# If true, "_position" is added on top of "_definitePosition" (default: definite wins).
const POSITION_ADDS_TO_DEFINITE := false

class W extends RefCounted:
	var origin := Vector3.ZERO      # legacy path position (moves along dir)
	var dir := Vector3.BACK         # direction of travel (basis.z)
	var lane_basis := Basis.IDENTITY
	var size := Vector3.ONE         # base size in meters
	var age := 0.0
	var despawn_z := 0.0
	# Noodle
	var noodle := false
	var info: ObstacleInfo = null
	var start_beat := 0.0
	var life_beats := 1.0
	var has_def := false
	var offset := Vector3.ZERO      # static "_position" offset in meters (game space)
	var world_basis := Basis.IDENTITY
	var local_basis := Basis.IDENTITY

var _mm := MultiMesh.new()
var _walls: Array[W] = []
var _speed := 0.0
var _beat_now := 0.0
var _beats_per_sec := 1.0
var _dbg_frames := 0   # DEBUG, remove later

func setup() -> void:
	var unit_box := BoxMesh.new()   # default size is 1 x 1 x 1
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true      # rgb = wall color, a = dissolve (size comes from the instance transform)
	_mm.mesh = unit_box             # set the flags above BEFORE instance_count
	_mm.instance_count = MAX_WALLS
	_mm.visible_instance_count = 0
	multimesh = _mm

	var base := load(BASE_MATERIAL) as ShaderMaterial
	var mat := base.duplicate() as ShaderMaterial
	mat.shader = load(BATCH_SHADER) as Shader
	material_override = mat

	layers = 3                      # same render layers as WallMesh in Wall.tscn
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-300, -100, -300), Vector3(600, 200, 600))

static func _nonzero(v: float) -> float:
	return v if absf(v) > 0.001 else 0.001

func _unit() -> Vector3:
	return Vector3(Settings.LANE_DISTANCE_X, Constants.LANE_DISTANCE_Y, Settings.LANE_DISTANCE_X)

# Unity euler degrees (ZXY order) -> game basis. The game's z axis is mirrored
# relative to Beat Saber, so x and y rotations flip sign.
static func _euler_basis(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-deg.x), deg_to_rad(-deg.y), deg_to_rad(deg.z)), EULER_ORDER_YXZ)

static func _half_jump(info: ObstacleInfo, bpm: float) -> float:
	var njs: float = info.nd_njs if info.has_njs else Map.get_object_njs(info.beat)
	var hjd := 4.0
	var sec_per_beat := 60.0 / bpm
	while njs * sec_per_beat * hjd > 17.999:
		hjd /= 2.0
	hjd += info.nd_offset
	return maxf(hjd, 0.25)

func add_wall(wall_info: ObstacleInfo, current_beat: float) -> void:
	if _walls.size() >= MAX_WALLS:
		return
	var unit := _unit()
	var x_size := wall_info.width * Settings.LANE_DISTANCE_X
	var y_size := wall_info.height * Constants.LANE_DISTANCE_Y
	var z_size := wall_info.duration * Constants.BEAT_DISTANCE
	var depth := z_size * 0.5

	var x := (0.5 * wall_info.width + wall_info.line_index - 2) * Settings.LANE_DISTANCE_X
	var y := (0.5 * wall_info.height + wall_info.line_layer) * Constants.LANE_DISTANCE_Y
	var z := (current_beat - wall_info.beat) * Constants.BEAT_DISTANCE - depth
	var c := cos(wall_info.rotation)
	var s := sin(wall_info.rotation)

	var w := W.new()
	var b := Basis(Vector3.UP, -wall_info.rotation)   # same as rotation.y = -rotation in Wall.gd
	w.lane_basis = b
	w.dir = b.z
	w.origin = Vector3(c * x - s * z, y, s * x + c * z)
	w.size = Vector3(_nonzero(x_size), _nonzero(y_size), _nonzero(z_size))
	w.despawn_z = Constants.MISS_Z + depth

	var bpm: float = Map.current_info.beats_per_minute
	_beats_per_sec = bpm / 60.0
	_speed = Constants.BEAT_DISTANCE * _beats_per_sec
	_beat_now = current_beat   # resync the batch's beat clock

	if wall_info.noodle:
		w.noodle = true
		w.info = wall_info
		var hjd := _half_jump(wall_info, bpm)
		w.start_beat = wall_info.beat - hjd
		w.life_beats = 2.0 * hjd + wall_info.duration
		w.has_def = wall_info.anim.has("def_pos")
		if wall_info.has_scale:
			w.size = Vector3(
				_nonzero(wall_info.nd_scale.x * unit.x),
				_nonzero(wall_info.nd_scale.y * unit.y),
				_nonzero(wall_info.nd_scale.z * unit.z))
		w.offset = Vector3(wall_info.nd_position.x * unit.x, wall_info.nd_position.y * unit.y, 0.0)
		w.world_basis = _euler_basis(wall_info.nd_rotation)
		w.local_basis = _euler_basis(wall_info.nd_local_rotation)
	_walls.append(w)
	# visible_instance_count is raised in the next _physics_process, after the transform is written

func _physics_process(delta: float) -> void:
	if Scoreboard.paused or _walls.is_empty():
		return
	_beat_now += delta * _beats_per_sec
	if NoodleTracks.current != null:
		NoodleTracks.current.begin_frame(_beat_now)
	var step := _speed * delta
	var i := 0
	while i < _walls.size():
		var w := _walls[i]
		w.age += delta
		var t := 0.0
		var done := false
		if w.noodle:
			t = (_beat_now - w.start_beat) / w.life_beats
			done = t >= 1.0
		if not w.has_def:
			w.origin += step * w.dir
			if w.origin.dot(w.dir) > w.despawn_z:
				done = true
		if done:
			_remove(i)
			continue   # slot i now holds the former last wall, process it again
		_write_instance(i, w, t)
		i += 1
	_mm.visible_instance_count = _walls.size()
	# DEBUG, remove later: once per second describe the first wall that has a track
	_dbg_frames += 1
	if _dbg_frames % 60 == 0 and NoodleTracks.current != null:
		for dw in _walls:
			if dw.noodle and not dw.info.tracks.is_empty():
				var dt: float = (_beat_now - dw.start_beat) / dw.life_beats
				print("[WALLTRACK] beat=", snappedf(_beat_now, 0.01), " walls=", _walls.size(), " wall t=", snappedf(dt, 0.001), " track chain: ", NoodleTracks.current.describe(dw.info.tracks[0]))
				break

func _write_instance(i: int, w: W, t: float) -> void:
	var sz := w.size
	var color := Color.WHITE
	var dissolve := 0.0
	var b := w.lane_basis
	var pos := w.origin
	var parent_xf := Transform3D.IDENTITY

	if not w.noodle:
		if w.age < SPAWN_ANIM_TIME:
			sz.y *= lerpf(0.1, 1.0, ease(w.age / SPAWN_ANIM_TIME, SPAWN_ANIM_EASE))
	else:
		if t < 0.0:
			# not alive yet in Noodle time: keep it tiny and out of sight
			_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0.0, -1000.0, 0.0)))
			return
		var a := w.info.anim
		var unit := _unit()
		var world_b := w.world_basis
		var local_b := w.local_basis
		color = w.info.nd_color
		if a.has("scale"):
			var sv := NoodleAnim.sample(a["scale"], t)
			sz *= Vector3(sv.x, sv.y, sv.z)
		if a.has("rotation"):
			var rv := NoodleAnim.sample(a["rotation"], t)
			world_b = _euler_basis(Vector3(rv.x, rv.y, rv.z))
		if a.has("local_rotation"):
			var lv := NoodleAnim.sample(a["local_rotation"], t)
			local_b = _euler_basis(Vector3(lv.x, lv.y, lv.z))
		if a.has("dissolve"):
			dissolve = clampf(NoodleAnim.sample(a["dissolve"], t).x, 0.0, 1.0)
		if a.has("color"):
			var cv := NoodleAnim.sample(a["color"], t)
			color = Color(cv.x, cv.y, cv.z, 1.0)
		# Noodle track events: the wall's tracks add their animation on top of its own
		var trk_pos := Vector3.ZERO
		var trk := NoodleTracks.current
		if trk != null and not w.info.tracks.is_empty():
			for tname: String in w.info.tracks:
				var ts := trk.state(tname)
				sz *= ts.scale
				trk_pos += ts.position
				world_b = NoodleTracks.euler_basis(ts.rotation) * world_b
				local_b = local_b * NoodleTracks.euler_basis(ts.local_rotation)
				dissolve = clampf(dissolve + ts.dissolve, 0.0, 1.0)
				if ts.has_color:
					color = Color(color.r * ts.color.r, color.g * ts.color.g, color.b * ts.color.b, 1.0)
			parent_xf = trk.parent_transform(w.info.tracks[0])
		if w.has_def:
			var pv := NoodleAnim.sample(a["def_pos"], t)
			pos = Vector3(pv.x * unit.x, pv.y * unit.y, -pv.z * unit.z)
			if POSITION_ADDS_TO_DEFINITE:
				pos += w.offset
			b = Basis.IDENTITY
		else:
			pos = w.origin + w.offset
		pos += trk_pos
		pos = world_b * pos            # "_rotation" turns the object around the player
		b = world_b * b * local_b

	_mm.set_instance_transform(i, parent_xf * Transform3D(b.scaled_local(sz), pos))
	_mm.set_instance_custom_data(i, Color(color.r, color.g, color.b, dissolve))

# swap-remove: move the last wall into slot i
func _remove(i: int) -> void:
	var last := _walls.size() - 1
	if i != last:
		_walls[i] = _walls[last]
	_walls.pop_back()

# called by BeepSaber_Game._clear_track()
func clear_from_track() -> void:
	_walls.clear()
	_mm.visible_instance_count = 0
