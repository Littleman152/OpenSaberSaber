extends RefCounted
class_name NoodleAnim
# Noodle Extensions keyframe animation: parsing and sampling.
# Keyframe formats (time is 0..1 over the object's lifetime):
#   vectors  [x, y, z, time, (easing)]       e.g. _definitePosition, _scale, _rotation
#   colors   [r, g, b, a, time, (easing)]
#   floats   [value, time, (easing)]         e.g. _dissolve
# A flat array such as [x, y, z] is treated as one static keyframe.
# The easing on a keyframe controls the segment that ENDS at that keyframe.
# Supported easings: linear, Quad/Cubic/Quart/Quint (in/out/inOut), Sine, Expo,
# easeOutElastic, easeOutBack and splineCatmullRom. Others fall back to linear.

class Track extends RefCounted:
	var count := 0
	var times := PackedFloat32Array()
	var values: Array[Vector4] = []
	var easings := PackedInt32Array()
	var quats: Array[Quaternion] = []     # rotation keyframes as quaternions (built when first sampled)

const E_SPLINE := 1

# named point definitions of the current map (_pointDefinitions), so animations can refer to them by name
static var point_definitions := {}

static func set_point_definitions(map_data: Dictionary) -> void:
	point_definitions = {}
	var custom: Variant = map_data.get("_customData", map_data.get("customData", null))
	if not custom is Dictionary:
		return
	var defs: Variant = (custom as Dictionary).get("_pointDefinitions", (custom as Dictionary).get("pointDefinitions", null))
	if not defs is Array:
		return
	for d: Variant in defs:
		if d is Dictionary:
			var nm: Variant = (d as Dictionary).get("_name", (d as Dictionary).get("name", null))
			var pts: Variant = (d as Dictionary).get("_points", (d as Dictionary).get("points", null))
			if nm is String and pts is Array:
				point_definitions[nm] = pts

# a string is looked up in the point definitions, anything else is returned unchanged
static func resolve(raw: Variant) -> Variant:
	if raw is String and point_definitions.has(raw):
		return point_definitions[raw]
	return raw
# id = family * 10 + kind; family 1..4 = Quad..Quint, 5 = Sine, 6 = Expo, 7 = Elastic, 8 = Back
# kind 0 = in, 1 = out, 2 = inOut
const EASE_IDS := {
	"easeLinear": 0, "splineCatmullRom": 1,
	"easeInQuad": 10, "easeOutQuad": 11, "easeInOutQuad": 12,
	"easeInCubic": 20, "easeOutCubic": 21, "easeInOutCubic": 22,
	"easeInQuart": 30, "easeOutQuart": 31, "easeInOutQuart": 32,
	"easeInQuint": 40, "easeOutQuint": 41, "easeInOutQuint": 42,
	"easeInSine": 50, "easeOutSine": 51, "easeInOutSine": 52,
	"easeInExpo": 60, "easeOutExpo": 61, "easeInOutExpo": 62,
	"easeOutElastic": 71, "easeOutBack": 81,
	"easeInCirc": 90, "easeOutCirc": 91, "easeInOutCirc": 92,
	"easeStep": 100,
}

# comps = number of value components (3 for vectors, 4 for colors, 1 for floats).
# Returns null for anything that isn't keyframe data (for example point definition names).
static func parse(raw: Variant, comps: int) -> Track:
	raw = resolve(raw)
	if not raw is Array or (raw as Array).is_empty():
		return null
	var arr := raw as Array
	var keyframes: Array = arr if arr[0] is Array else [arr + [0.0]]
	var tr := Track.new()
	for kf: Variant in keyframes:
		if not kf is Array:
			continue
		var k := kf as Array
		if k.size() < comps + 1:
			continue
		var v := Vector4.ZERO
		for c in comps:
			v[c] = float(k[c])
		tr.values.append(v)
		tr.times.append(float(k[comps]))
		var e := 0
		for j in range(comps + 1, k.size()):
			if k[j] is String and EASE_IDS.has(k[j]):
				e = EASE_IDS[k[j]]
		tr.easings.append(e)
	tr.count = tr.values.size()
	return tr if tr.count > 0 else null

static func sample(tr: Track, t: float) -> Vector4:
	var n := tr.count
	if n == 1 or t <= tr.times[0]:
		return tr.values[0]
	if t >= tr.times[n - 1]:
		return tr.values[n - 1]
	var i := 0
	while i < n - 2 and t >= tr.times[i + 1]:
		i += 1
	var f := (t - tr.times[i]) / maxf(tr.times[i + 1] - tr.times[i], 0.00001)
	var e := tr.easings[i + 1]
	if e == E_SPLINE:
		var p0 := tr.values[maxi(i - 1, 0)]
		var p3 := tr.values[mini(i + 2, n - 1)]
		return _catmull(p0, tr.values[i], tr.values[i + 1], p3, f)
	return tr.values[i].lerp(tr.values[i + 1], _ease(e, f))

# Euler degrees (Beat Saber convention, ZXY order) -> quaternion in game space
static func euler_to_quat(deg: Vector3) -> Quaternion:
	return Quaternion(Basis.from_euler(Vector3(deg_to_rad(-deg.x), deg_to_rad(-deg.y), deg_to_rad(deg.z)), EULER_ORDER_YXZ))

static func _kf_quat(tr: Track, i: int) -> Quaternion:
	if tr.quats.size() != tr.count:
		tr.quats.clear()
		for v: Vector4 in tr.values:
			tr.quats.append(euler_to_quat(Vector3(v.x, v.y, v.z)))
	return tr.quats[i]

# Rotations are blended like Noodle does: as quaternions along the SHORTEST arc, not per Euler angle.
# So a keyframe list like 0, 90, 180, 270, 0 keeps turning in the same direction instead of
# swinging back, and -360 to 0 means no turn at all. splineCatmullRom segments still use the Euler values.
static func sample_rotation(tr: Track, t: float) -> Quaternion:
	var n := tr.count
	if n == 1 or t <= tr.times[0]:
		return _kf_quat(tr, 0)
	if t >= tr.times[n - 1]:
		return _kf_quat(tr, n - 1)
	var i := 0
	while i < n - 2 and t >= tr.times[i + 1]:
		i += 1
	var f := (t - tr.times[i]) / maxf(tr.times[i + 1] - tr.times[i], 0.00001)
	var e := tr.easings[i + 1]
	if e == E_SPLINE:
		var v := _catmull(tr.values[maxi(i - 1, 0)], tr.values[i], tr.values[i + 1], tr.values[mini(i + 2, n - 1)], f)
		return euler_to_quat(Vector3(v.x, v.y, v.z))
	return _kf_quat(tr, i).slerp(_kf_quat(tr, i + 1), _ease(e, f))

static func _catmull(p0: Vector4, p1: Vector4, p2: Vector4, p3: Vector4, t: float) -> Vector4:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t \
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

@warning_ignore("integer_division")
static func _ease(e: int, x: float) -> float:
	var fam := e / 10
	var kind := e % 10
	if fam >= 1 and fam <= 4:
		var p := float(fam + 1)
		match kind:
			0:
				return pow(x, p)
			1:
				return 1.0 - pow(1.0 - x, p)
			_:
				if x < 0.5:
					return pow(2.0, p - 1.0) * pow(x, p)
				return 1.0 - pow(-2.0 * x + 2.0, p) / 2.0
	match fam:
		5:
			match kind:
				0:
					return 1.0 - cos(x * PI / 2.0)
				1:
					return sin(x * PI / 2.0)
				_:
					return -(cos(PI * x) - 1.0) / 2.0
		6:
			if x <= 0.0:
				return 0.0
			if x >= 1.0:
				return 1.0
			match kind:
				0:
					return pow(2.0, 10.0 * x - 10.0)
				1:
					return 1.0 - pow(2.0, -10.0 * x)
				_:
					if x < 0.5:
						return pow(2.0, 20.0 * x - 10.0) / 2.0
					return (2.0 - pow(2.0, -20.0 * x + 10.0)) / 2.0
		7:
			if x <= 0.0:
				return 0.0
			if x >= 1.0:
				return 1.0
			return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (2.0 * PI / 3.0)) + 1.0
		8:
			var c1 := 1.70158
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
		9:
			match kind:
				0:
					return 1.0 - sqrt(maxf(1.0 - x * x, 0.0))
				1:
					return sqrt(maxf(1.0 - (x - 1.0) * (x - 1.0), 0.0))
				_:
					if x < 0.5:
						return (1.0 - sqrt(maxf(1.0 - 4.0 * x * x, 0.0))) / 2.0
					return (sqrt(maxf(1.0 - pow(-2.0 * x + 2.0, 2.0), 0.0)) + 1.0) / 2.0
		10:
			return floorf(x)   # easeStep: holds the old value, jumps at the end of the segment
	return x
	return x
