extends Panel
class_name BeatSaverFilterPanel
# Filter settings overlay for BeatSaverPanel. Builds its own controls in code,
# so no scene editing is needed. Emits filters_applied with a dictionary that
# matches BeatSaverPanel.filters.

signal filters_applied(filters: Dictionary)
signal closed

# [filter key, label]. true = only maps with that property
# (automapper: true = include AI maps)
const BOOL_FILTERS := [
	["noodle", "Noodle Ext only"],
	["me", "Mapping Ext only"],
	["chroma", "Chroma only"],
	["cinema", "Cinema only"],
	["ranked", "Ranked only"],
	["curated", "Curated only"],
	["verified", "Verified mappers"],
	["automapper", "Include AI maps"],
]

var _checks := {}
var _rating_slider: HSlider
var _rating_label: Label

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "BeatSaver filters"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# two columns keeps the window short enough for small panels
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for entry: Array in BOOL_FILTERS:
		var check := CheckButton.new()
		check.text = entry[1]
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(check)
		_checks[entry[0]] = check

	_rating_label = Label.new()
	box.add_child(_rating_label)
	_rating_slider = HSlider.new()
	_rating_slider.min_value = 0.0
	_rating_slider.max_value = 1.0
	_rating_slider.step = 0.05
	_rating_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rating_slider.value_changed.connect(_update_rating_label)
	box.add_child(_rating_slider)
	_update_rating_label(0.0)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	buttons.add_child(_make_button("Apply", _on_apply_pressed))
	buttons.add_child(_make_button("Reset", _on_reset_pressed))
	buttons.add_child(_make_button("Close", close_panel))

	# hook up the same click/hover sounds as the rest of the UI
	UI_AudioEngine.attach_children(self)

func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# button_up like the rest of the panel (works with the OQ UI pointer)
	button.button_up.connect(callback)
	return button

func _update_rating_label(value: float) -> void:
	if value <= 0.0:
		_rating_label.text = "Minimum rating: any"
	else:
		_rating_label.text = "Minimum rating: %d%%" % roundi(value * 100.0)

# fill the controls from a BeatSaverPanel.filters dictionary
func load_from(filters: Dictionary) -> void:
	for key: String in _checks:
		(_checks[key] as CheckButton).button_pressed = filters.get(key, false)
	_rating_slider.value = filters.get("min_rating", 0.0)
	_update_rating_label(_rating_slider.value)

func get_filters() -> Dictionary:
	var result := {}
	for key: String in _checks:
		result[key] = (_checks[key] as CheckButton).button_pressed
	result["min_rating"] = _rating_slider.value
	return result

func close_panel() -> void:
	visible = false
	closed.emit()

func _on_apply_pressed() -> void:
	filters_applied.emit(get_filters())
	close_panel()

# clears the controls only; press Apply to reload the list
func _on_reset_pressed() -> void:
	load_from({})
