extends RefCounted
class_name BombInfo

var beat: float
var line_index: float
var line_layer: float
var rotation: float
var interactable := true
var fake := false

@warning_ignore("shadowed_variable")
func _init(beat: float, line_index: float, line_layer: float, rotation_degrees: float) -> void:
	self.beat = beat
	self.line_index = Utils.adjust_horizontal(line_index)
	self.line_layer = Utils.adjust_vertical(line_layer)
	self.rotation = Utils.adjust_lane_rotation(rotation_degrees * (PI/180.))
	if abs(Settings.gradual_rotation) > 1e-5:
		self.rotation += Settings.gradual_rotation * beat
		self.rotation += Settings.gradual_rotation * beat

static func new_v2(bomb_dict: Dictionary) -> BombInfo:
	var info := BombInfo.new(
		Utils.get_float(bomb_dict, "_time", 0.0),
		Utils.precise_measurement(Utils.get_float(bomb_dict, "_lineIndex", 0)),
		Utils.precise_measurement(Utils.get_float(bomb_dict, "_lineLayer", 0)),
		Utils.get_float(bomb_dict, "r", 0)
	)
	var cd := Utils.get_dict(bomb_dict, "_customData", {})
	info.interactable = cd.get("_interactable", true) != false
	info.fake = cd.get("_fake", false) == true
	return info

static func new_v3(bomb_dict: Dictionary) -> BombInfo:
	var info := BombInfo.new(
		Utils.get_float(bomb_dict, "b", 0.0),
		Utils.precise_measurement(Utils.get_float(bomb_dict, "x", 0)),
		Utils.precise_measurement(Utils.get_float(bomb_dict, "y", 0)),
		Utils.get_float(bomb_dict, "r", 0)
	)
	var cd := Utils.get_dict(bomb_dict, "customData", {})
	info.interactable = cd.get("uninteractable", false) != true
	info.fake = cd.get("fake", false) == true
	return info
