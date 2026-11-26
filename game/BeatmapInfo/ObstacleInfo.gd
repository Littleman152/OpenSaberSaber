extends RefCounted
class_name ObstacleInfo

var beat: float
var duration: float
var line_index: float
var line_layer: float
var width: float
var height: float
var rotation: = 0.
var interactable := true
var fake := false

# ---- Noodle data (read from customData, see NoodleAnim.gd) ----
var noodle := false            # true if the wall has any Noodle transform / color / animation
var has_scale := false
var has_position := false      # true if the wall has a "_position"
var nd_scale := Vector3.ONE    # in lane units
var nd_position := Vector2.ZERO
var nd_rotation := Vector3.ZERO        # world rotation (degrees)
var nd_local_rotation := Vector3.ZERO  # degrees
var nd_color := Color.WHITE
var nd_has_color := false
var nd_alpha := 1.0
var has_njs := false
var nd_njs := 0.0
var nd_offset := 0.0
var anim := {}                 # "def_pos" "scale" "rotation" "local_rotation" "dissolve" "color" -> NoodleAnim.Track
var tracks := PackedStringArray()

@warning_ignore("shadowed_variable")
func _init(beat: float, duration: float, line_index: float, line_layer: float, 
		width: float, height: float, rotation_degrees: float) -> void:
	self.beat = beat
	self.duration = duration
	self.width = width
	if Settings.flip & Constants.FLIP_HORIZONTAL:
		self.line_index = (3+1)-line_index-width
	else:
		self.line_index = line_index
	self.height = height
	if Settings.flip & Constants.FLIP_VERTICAL:
		self.line_layer = (2+1)-line_layer-height
	else:
		self.line_layer = line_layer
	self.rotation = Utils.adjust_lane_rotation(rotation_degrees * (PI/180.))
	if abs(Settings.gradual_rotation) > 1e-5:
		self.rotation += Settings.gradual_rotation * beat

static func new_v2(obstacle_dict: Dictionary) -> ObstacleInfo:
	var y: float = 0
	var h: float = 0
	match int(Utils.get_float(obstacle_dict, "_type", 0)):
		0: # full height
			y = 0
			h = 5
		1: # crouch
			y = 2
			h = 3
		2: # free
			y = Utils.precise_measurement(Utils.get_float(obstacle_dict, "_lineLayer", 0))
			h = Utils.precise_measurement(Utils.get_float(obstacle_dict, "_height", 0))
	var info := ObstacleInfo.new(
		Utils.get_float(obstacle_dict, "_time", 0.0),
		Utils.get_float(obstacle_dict, "_duration", 0.0),
		Utils.precise_measurement(Utils.get_float(obstacle_dict, "_lineIndex", 0)),
		y,
		Utils.precise_measurement(Utils.get_float(obstacle_dict, "_width", 0)),
		h,
		Utils.get_float(obstacle_dict, "r", 0)
	)
	var cd := Utils.get_dict(obstacle_dict, "_customData", {})
	info.interactable = cd.get("_interactable", true) != false
	info.fake = cd.get("_fake", false) == true
	_read_noodle(info, cd)
	return info

static func new_v3(obstacle_dict: Dictionary) -> ObstacleInfo:
	var info := ObstacleInfo.new(
		Utils.get_float(obstacle_dict, "b", 0.0),
		Utils.get_float(obstacle_dict, "d", 0.0),
		Utils.precise_measurement(Utils.get_float(obstacle_dict, "x", 0)),
		Utils.precise_measurement(Utils.get_float(obstacle_dict, "y", 0)),
		Utils.precise_measurement(Utils.get_float(obstacle_dict, "w", 0)),
		Utils.precise_measurement(Utils.get_float(obstacle_dict, "h", 0)),
		Utils.get_float(obstacle_dict, "r", 0)
	)
	var cd := Utils.get_dict(obstacle_dict, "customData", {})
	info.interactable = cd.get("uninteractable", false) != true
	info.fake = cd.get("fake", false) == true
	_read_noodle(info, cd)
	return info

static func _vec3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO

# Reads the Noodle fields. v2 key names first, v3 names as fallback.
static func _read_noodle(info: ObstacleInfo, cd: Dictionary) -> void:
	var sc: Variant = cd.get("_scale", cd.get("size", null))
	if sc is Array and (sc as Array).size() >= 3:
		info.has_scale = true
		info.nd_scale = _vec3(sc)
	var pos: Variant = cd.get("_position", cd.get("coordinates", null))
	if pos is Array and (pos as Array).size() >= 2:
		info.has_position = true
		info.nd_position = Vector2(float(pos[0]), float(pos[1]))
	info.nd_rotation = _vec3(cd.get("_rotation", cd.get("worldRotation", null)))
	info.nd_local_rotation = _vec3(cd.get("_localRotation", cd.get("localRotation", null)))
	var col: Variant = cd.get("_color", cd.get("color", null))
	var has_color := false
	if col is Array and (col as Array).size() >= 3:
		has_color = true
		info.nd_has_color = true
		info.nd_color = Color(float(col[0]), float(col[1]), float(col[2]), 1.0)
		if (col as Array).size() >= 4:
			info.nd_alpha = float(col[3])
	var njs: Variant = cd.get("_noteJumpMovementSpeed", cd.get("noteJumpMovementSpeed", null))
	if njs is float or njs is int:
		info.has_njs = true
		info.nd_njs = float(njs)
	var jump_offset: Variant = cd.get("_noteJumpStartBeatOffset", cd.get("noteJumpStartBeatOffset", null))
	if jump_offset is float or jump_offset is int:
		info.nd_offset = float(jump_offset)
	var raw_anim: Variant = cd.get("_animation", cd.get("animation", null))
	if raw_anim is Dictionary:
		var ad := raw_anim as Dictionary
		var specs := {
			"def_pos": ["_definitePosition", "definitePosition", 3],
			"scale": ["_scale", "scale", 3],
			"rotation": ["_rotation", "rotation", 3],
			"local_rotation": ["_localRotation", "localRotation", 3],
			"dissolve": ["_dissolve", "dissolve", 1],
			"color": ["_color", "color", 4],
			"position": ["_position", "position", 3],
			"dissolve_arrow": ["_dissolveArrow", "dissolveArrow", 1],
		}
		for key: String in specs:
			var spec: Array = specs[key]
			var tr := NoodleAnim.parse(ad.get(spec[0], ad.get(spec[1], null)), int(spec[2]))
			if tr != null:
				info.anim[key] = tr
	# track names (v2 "_track", v3 "track"): a string or a list of strings
	var trk: Variant = cd.get("_track", cd.get("track", null))
	if trk is String:
		info.tracks.append(trk)
	elif trk is Array:
		for tn: Variant in trk:
			if tn is String:
				info.tracks.append(tn)
	info.noodle = has_color or info.has_scale or info.has_position or not info.anim.is_empty() \
		or info.nd_position != Vector2.ZERO or info.nd_rotation != Vector3.ZERO \
		or info.nd_local_rotation != Vector3.ZERO or not info.tracks.is_empty() \
		or info.has_njs or info.nd_offset != 0.0
