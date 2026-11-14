extends Panel
class_name PracticePanel

# emitted when the player presses Start
signal start_pressed(speed_percent: int, start_seconds: float)
signal back_pressed()

const FALLBACK_LENGTH := 600.0
# the start point can't be closer than this to the end of the song
const END_MARGIN := 5.0

@onready var _song_label := $song as Label
@onready var _speed_label := $speed_label as Label
@onready var _speed_slider := $speed_slider as HSlider
@onready var _start_label := $start_label as Label
@onready var _start_slider := $start_slider as HSlider

var _current_info: MapInfo

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	_speed_slider.value_changed.connect(_on_slider_changed)
	_start_slider.value_changed.connect(_on_slider_changed)
	_update_labels()

# called by the game every time the menu is opened
func setup(info: MapInfo, difficulty: DifficultyInfo) -> void:
	_song_label.text = "%s By %s\n%s" % [info.song_name, info.song_author_name, difficulty.get_display_name()]
	# the speed is remembered, the start point goes back to 0 when the song changes
	if info != _current_info:
		_current_info = info
		_start_slider.max_value = maxf(1.0, _get_song_length(info) - END_MARGIN)
		_start_slider.value = 0.0
	_update_labels()

func _get_song_length(info: MapInfo) -> float:
	# same loading code as BeepSaber_Game.start_map(), only to read the length
	var filename := info.filepath + info.song_filename
	var stream: AudioStream = null
	if FileAccess.file_exists(filename):
		stream = AudioStreamOggVorbis.load_from_file(filename)
	else:
		var audio_data := Utils.read_binary_file(info.filepath, info.song_filename)
		if len(audio_data) > 0:
			stream = AudioStreamOggVorbis.load_from_buffer(audio_data)
	if stream != null and stream.get_length() > 0.0:
		return stream.get_length()
	var from_info := info.get_length_seconds()
	return from_info if from_info > 0.0 else FALLBACK_LENGTH

func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]

func _update_labels() -> void:
	_speed_label.text = "Speed %d%%" % int(_speed_slider.value)
	_start_label.text = "Start at %s" % _format_time(_start_slider.value)

func _on_slider_changed(_value: float) -> void:
	_update_labels()

func _on_minus_button_up() -> void:
	_start_slider.value -= 10.0

func _on_plus_button_up() -> void:
	_start_slider.value += 10.0

func _on_start_button_up() -> void:
	start_pressed.emit(int(_speed_slider.value), _start_slider.value)

func _on_back_button_up() -> void:
	back_pressed.emit()
