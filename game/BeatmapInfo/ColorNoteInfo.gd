extends RefCounted
class_name ColorNoteInfo

var beat: float
var line_index: float
var line_layer: float
var color: int # 0=left, 1=right
var cut_angle: float
var rotation: float
var interactable := true
var fake := false
var arrow_hidden := false

@warning_ignore("shadowed_variable")
func _init(beat: float, line_index: float, line_layer: float, color: int, cut_angle: float, rotation_degrees: float) -> void:
	self.beat = beat
	self.line_index = Utils.adjust_horizontal(line_index)
	self.line_layer = Utils.adjust_vertical(line_layer)
	self.color = Utils.adjust_color(color)
	self.cut_angle = cut_angle
	self.rotation = Utils.adjust_lane_rotation(rotation_degrees * (PI/180.))
	if abs(Settings.gradual_rotation) > Constants.ROTATION_EPS:
		self.rotation += Settings.gradual_rotation * beat

static func new_v2(note_dict: Dictionary) -> ColorNoteInfo:
	var info := ColorNoteInfo.new(
		Utils.get_float(note_dict, "_time", 0.0),
		Utils.precise_measurement(Utils.get_float(note_dict, "_lineIndex", 0)),
		Utils.precise_measurement(Utils.get_float(note_dict, "_lineLayer", 0)),
		int(Utils.get_float(note_dict, "_type", -1.0)),
		Utils.precise_angle_rad(Utils.get_float(note_dict, "_cutDirection", 0), 0),
		Utils.get_float(note_dict, "r", 0)
	)
	var cd := Utils.get_dict(note_dict, "_customData", {})
	info.interactable = cd.get("_interactable", true) != false
	info.fake = cd.get("_fake", false) == true
	info.arrow_hidden = ColorNoteInfo.is_arrow_hidden(cd.get("_animation", null))
	info._read_noodle(cd)
	return info

static func new_v3(note_dict: Dictionary) -> ColorNoteInfo:
	var info := ColorNoteInfo.new(
		Utils.get_float(note_dict, "b", 0.0),
		Utils.precise_measurement(Utils.get_float(note_dict, "x", 0)),
		Utils.precise_measurement(Utils.get_float(note_dict, "y", 0)),
		int(Utils.get_float(note_dict, "c", 0)),
		Utils.precise_angle_rad(Utils.get_float(note_dict, "d", 0), Utils.get_float(note_dict, "a", 0)),
		Utils.get_float(note_dict, "r", 0)
	)
	var cd := Utils.get_dict(note_dict, "customData", {})
	info.interactable = cd.get("uninteractable", false) != true
	info.fake = cd.get("fake", false) == true
	info.arrow_hidden = ColorNoteInfo.is_arrow_hidden(cd.get("animation", null))
	info._read_noodle(cd)
	return info

# True when the note's arrow is dissolved for its whole lifetime (every _dissolveArrow keyframe is 0)
static func is_arrow_hidden(anim: Variant) -> bool:
	if not anim is Dictionary:
		return false
	var d := anim as Dictionary
	var da: Variant = d.get("_dissolveArrow", d.get("dissolveArrow", null))
	if not da is Array or (da as Array).is_empty():
		return false
	var kfs: Array = da if (da as Array)[0] is Array else [da]
	for kf: Variant in kfs:
		if not kf is Array or (kf as Array).is_empty() or float((kf as Array)[0]) > 0.0:
			return false
	return true
	
var noodle: ObstacleInfo = null   # Noodle data (parsed like walls); null when the note has none
var tracks := PackedStringArray()

func _read_noodle(cd: Dictionary) -> void:
	var bag := ObstacleInfo.new(beat, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	ObstacleInfo._read_noodle(bag, cd)
	if bag.noodle:
		noodle = bag
		tracks = bag.tracks
