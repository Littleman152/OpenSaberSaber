extends RefCounted
class_name NoodleTracks
# Noodle Extensions track events for the batched walls.
# Supported: AnimateTrack (position, rotation, localRotation, scale, dissolve, color) with
# durations, easings and keyframe lists, and AssignTrackParent (children follow a parent track).
# Not supported yet: AssignPlayerToTrack, AssignPathAnimation, AssignFogTrack, _repeat.
#
# Usage: NoodleTracks.load_map(map_data) when a map starts, then every physics frame
# NoodleTracks.current.begin_frame(beat) and ask state(track) / parent_transform(track).

static var current: NoodleTracks = null

const MAX_PARENT_DEPTH := 8
const PROPS := {"position": 3, "rotation": 3, "localRotation": 3, "scale": 3, "dissolve": 1, "color": 4}
const DEFAULTS := {
	"position": Vector4(0, 0, 0, 0), "rotation": Vector4(0, 0, 0, 0), "localRotation": Vector4(0, 0, 0, 0),
	"scale": Vector4(1, 1, 1, 0), "dissolve": Vector4(0, 0, 0, 0), "color": Vector4(1, 1, 1, 1),
}

class PropEvent extends RefCounted:
	var time := 0.0
	var duration := 0.0
	var easing := 0
	var kf: NoodleAnim.Track = null    # keyframes played over the event's duration, or null
	var from := Vector4.ZERO           # static target: value when the event starts
	var to := Vector4.ZERO             # static target: value when the event ends

class TrackState extends RefCounted:
	var position := Vector3.ZERO       # meters, game space
	var rotation := Vector3.ZERO       # degrees (Beat Saber convention)
	var local_rotation := Vector3.ZERO
	var scale := Vector3.ONE
	var dissolve := 0.0
	var color := Color.WHITE
	var has_color := false

var _needed := {}      # tracks used by walls (and their parents); everything else is skipped
var _events := {}      # track -> { prop -> Array[PropEvent] sorted by time }
var _parents := {}     # child track -> Array of [time, parent track] sorted by time
var _frame_beat := 0.0
var _state_cache := {}
var _parent_cache := {}

# ---------------------------------------------------------------- loading

static var _thread: Thread = null

static func load_map(map_data: Dictionary) -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	current = null
	var needed := _collect_needed(map_data)
	if needed.is_empty():
		return   # no wall uses a track, nothing to do
	_thread = Thread.new()
	_thread.start(_load_in_thread.bind(map_data, needed))

static func _load_in_thread(map_data: Dictionary, needed: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var t := NoodleTracks.new()
	t._needed = needed
	t._load(map_data)
	if not t._events.is_empty() or not t._parents.is_empty():
		current = t
	print("[TRACKS] loaded in ", Time.get_ticks_msec() - t0, " ms: animated tracks=", t._events.size(), " tracks with a parent=", t._parents.size())   # DEBUG, remove later

# Tracks used by walls, plus every track that is a parent of one of them (directly or not).
static func _collect_needed(map_data: Dictionary) -> Dictionary:
	var needed := {}
	for o: ObstacleInfo in Map.obstacle_stack:
		if o != null:
			for tn: String in o.tracks:
				needed[tn] = true
	if needed.is_empty():
		return needed
	var custom: Variant = map_data.get("_customData", map_data.get("customData", null))
	if not custom is Dictionary:
		return needed
	var raw: Variant = (custom as Dictionary).get("_customEvents", (custom as Dictionary).get("customEvents", null))
	if not raw is Array:
		return needed
	var links: Array = []   # [children, parent]
	for e: Variant in raw:
		if not e is Dictionary:
			continue
		var type_v: Variant = _ev(e as Dictionary, "_type", "t")
		if not type_v is String or String(type_v) != "AssignTrackParent":
			continue
		var d: Variant = _ev(e as Dictionary, "_data", "d")
		if d is Dictionary:
			var p: Variant = _ev(d as Dictionary, "_parentTrack", "parentTrack")
			if p is String:
				links.append([_names(_ev(d as Dictionary, "_childrenTracks", "childrenTracks")), String(p)])
	var changed := true
	while changed:
		changed = false
		for link: Array in links:
			if needed.has(link[1]):
				continue
			for c: String in link[0]:
				if needed.has(c):
					needed[link[1]] = true
					changed = true
					break
	return needed

static func _ev(e: Dictionary, k2: String, k3: String) -> Variant:
	return e.get(k2, e.get(k3, null))

static func _names(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is String:
		out.append(v)
	elif v is Array:
		for n: Variant in v:
			if n is String:
				out.append(n)
	return out

func _load(map_data: Dictionary) -> void:
	var custom: Variant = map_data.get("_customData", map_data.get("customData", null))
	if not custom is Dictionary:
		return
	var raw: Variant = (custom as Dictionary).get("_customEvents", (custom as Dictionary).get("customEvents", null))
	if not raw is Array:
		return
	var list: Array = []
	for e: Variant in raw:
		if e is Dictionary:
			# skip events without a numeric time, they can't be placed on the timeline
			var tv: Variant = _ev(e as Dictionary, "_time", "b")
			if tv is float or tv is int:
				list.append(e)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(_ev(a, "_time", "b")) < float(_ev(b, "_time", "b")))
	for e: Dictionary in list:
		var type_v: Variant = _ev(e, "_type", "t")
		var data_v: Variant = _ev(e, "_data", "d")
		if not type_v is String or not data_v is Dictionary:
			continue
		var time := float(_ev(e, "_time", "b"))
		match String(type_v):
			"AnimateTrack":
				_add_animate(time, data_v as Dictionary)
			"AssignTrackParent":
				_add_parent(time, data_v as Dictionary)

func _add_animate(time: float, d: Dictionary) -> void:
	var tracks := PackedStringArray()
	for tn: String in _names(_ev(d, "_track", "track")):
		if _needed.has(tn):
			tracks.append(tn)
	if tracks.is_empty():
		return
	var dur_v: Variant = _ev(d, "_duration", "duration")
	var dur := float(dur_v) if (dur_v is float or dur_v is int) else 0.0
	var ease_v: Variant = _ev(d, "_easing", "easing")
	var easing := 0
	if ease_v is String and NoodleAnim.EASE_IDS.has(ease_v):
		easing = NoodleAnim.EASE_IDS[ease_v]
	for prop: String in PROPS:
		var val: Variant = _ev(d, "_" + prop, prop)
		if val == null:
			continue
		for tr: String in tracks:
			_add_prop_event(tr, prop, int(PROPS[prop]), val, time, dur, easing)

func _add_prop_event(track: String, prop: String, comps: int, raw: Variant, time: float, dur: float, easing: int) -> void:
	var v: Variant = NoodleAnim.resolve(raw)
	var ev := PropEvent.new()
	ev.time = time
	ev.duration = dur
	ev.easing = easing
	if v is Array and not (v as Array).is_empty() and (v as Array)[0] is Array:
		ev.kf = NoodleAnim.parse(v, comps)
		if ev.kf == null:
			return
	else:
		var arr: Array = v if v is Array else [v]
		if arr.size() < comps:
			return
		var vec := Vector4.ZERO
		for c in comps:
			vec[c] = float(arr[c])
		ev.to = vec
		ev.from = _value_at(track, prop, time)   # earlier events are already stored
	if not _events.has(track):
		_events[track] = {}
	var props: Dictionary = _events[track]
	if not props.has(prop):
		props[prop] = []
	(props[prop] as Array).append(ev)

func _add_parent(time: float, d: Dictionary) -> void:
	var parent_v: Variant = _ev(d, "_parentTrack", "parentTrack")
	if not parent_v is String:
		return
	for child: String in _names(_ev(d, "_childrenTracks", "childrenTracks")):
		if not _needed.has(child):
			continue
		if not _parents.has(child):
			_parents[child] = []
		(_parents[child] as Array).append([time, String(parent_v)])

# ---------------------------------------------------------------- evaluation

@warning_ignore("integer_division")
func _last_index(list: Array, b: float) -> int:
	var lo := 0
	var hi := list.size() - 1
	var res := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if (list[mid] as PropEvent).time <= b:
			res = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return res

func _value_at(track: String, prop: String, b: float) -> Vector4:
	var default_v: Vector4 = DEFAULTS[prop]
	if not _events.has(track):
		return default_v
	var props: Dictionary = _events[track]
	if not props.has(prop):
		return default_v
	var list: Array = props[prop]
	var idx := _last_index(list, b)
	if idx < 0:
		return default_v
	var ev := list[idx] as PropEvent
	var t := 1.0 if ev.duration <= 0.0 else clampf((b - ev.time) / ev.duration, 0.0, 1.0)
	var eased := NoodleAnim._ease(ev.easing, t)
	if ev.kf != null:
		return NoodleAnim.sample(ev.kf, eased)
	return ev.from.lerp(ev.to, eased)

func begin_frame(beat: float) -> void:
	_frame_beat = beat
	_state_cache.clear()
	_parent_cache.clear()

func has_track(track: String) -> bool:
	return _events.has(track) or _parents.has(track)

# Unity euler degrees (ZXY order) -> game basis (z axis is mirrored, so x/y rotations flip sign)
static func euler_basis(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-deg.x), deg_to_rad(-deg.y), deg_to_rad(deg.z)), EULER_ORDER_YXZ)

# The animated values of one track at the current frame (cached per frame).
func state(track: String) -> TrackState:
	if _state_cache.has(track):
		return _state_cache[track]
	var s := TrackState.new()
	if _events.has(track):
		var props: Dictionary = _events[track]
		var unit := Vector3(Settings.LANE_DISTANCE_X, Constants.LANE_DISTANCE_Y, Settings.LANE_DISTANCE_X)
		if props.has("position"):
			var p := _value_at(track, "position", _frame_beat)
			s.position = Vector3(p.x * unit.x, p.y * unit.y, -p.z * unit.z)
		if props.has("rotation"):
			var r := _value_at(track, "rotation", _frame_beat)
			s.rotation = Vector3(r.x, r.y, r.z)
		if props.has("localRotation"):
			var lr := _value_at(track, "localRotation", _frame_beat)
			s.local_rotation = Vector3(lr.x, lr.y, lr.z)
		if props.has("scale"):
			var sc := _value_at(track, "scale", _frame_beat)
			s.scale = Vector3(sc.x, sc.y, sc.z)
		if props.has("dissolve"):
			s.dissolve = clampf(_value_at(track, "dissolve", _frame_beat).x, 0.0, 1.0)
		if props.has("color"):
			var c := _value_at(track, "color", _frame_beat)
			s.color = Color(c.x, c.y, c.z, c.w)
			s.has_color = true
	_state_cache[track] = s
	return s

# This track's own transform, used when it acts as a parent for other tracks.
func track_transform(track: String) -> Transform3D:
	var s := state(track)
	var b := euler_basis(s.rotation) * euler_basis(s.local_rotation)
	var sc := Vector3(maxf(s.scale.x, 0.0001), maxf(s.scale.y, 0.0001), maxf(s.scale.z, 0.0001))
	return Transform3D(b.scaled_local(sc), s.position)

func _parent_at(track: String, b: float) -> String:
	var list: Array = _parents[track]
	var result := ""
	for entry: Array in list:
		if float(entry[0]) <= b:
			result = entry[1]
		else:
			break
	return result

# Transform contributed by the parent chain of a track (identity if it has no parent).
func parent_transform(track: String, depth := 0) -> Transform3D:
	if _parent_cache.has(track):
		return _parent_cache[track]
	var result := Transform3D.IDENTITY
	if depth < MAX_PARENT_DEPTH and _parents.has(track):
		var p := _parent_at(track, _frame_beat)
		if p != "":
			result = parent_transform(p, depth + 1) * track_transform(p)
	_parent_cache[track] = result
	return result

# DEBUG, remove later: one line describing a track and its parent chain at the current frame
func describe(track: String) -> String:
	var out := ""
	var nm := track
	for i in MAX_PARENT_DEPTH:
		var s := state(nm)
		out += "%s(pos=%s scale=%s) <- " % [nm, s.position, s.scale]
		var p := ""
		if _parents.has(nm):
			p = _parent_at(nm, _frame_beat)
		if p == "":
			break
		nm = p
	return out
