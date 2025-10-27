extends PanelContainer

signal notification_finished

const FADE_IN_DURATION = 0.3
const FADE_OUT_DURATION = 0.4
const SLIDE_DISTANCE = 50

var notification_type: String = "info"
var duration: float = 3.0
var timer: Timer

@onready var label: Label = $MarginContainer/HBoxContainer/Label
@onready var icon: TextureRect = $MarginContainer/HBoxContainer/Icon


func _ready():
	modulate.a = 0.0
	position.x += SLIDE_DISTANCE

	_setup_style()
	_animate_in()


func setup(message: String, type: String, display_duration: float):
	notification_type = type
	duration = display_duration

	if label:
		label.text = message

	_set_icon_and_color()

	timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(_start_fade_out)
	add_child(timer)
	timer.start()


func _setup_style():
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2

	add_theme_stylebox_override("panel", style)


func _set_icon_and_color():
	var style = get_theme_stylebox("panel")
	var border_color: Color
	var text_color: Color

	match notification_type:
		"item":
			border_color = Color(0.4, 0.8, 0.4, 1.0)
			text_color = Color(0.9, 1.0, 0.9, 1.0)
		"crafted":
			border_color = Color(0.8, 0.3, 0.9, 1.0)
			text_color = Color(0.9, 1.0, 0.9, 1.0)
		"success":
			border_color = Color(0.3, 0.8, 0.3, 1.0)
			text_color = Color(0.8, 1.0, 0.8, 1.0)
		"warning":
			border_color = Color(0.9, 0.7, 0.2, 1.0)
			text_color = Color(1.0, 0.95, 0.8, 1.0)
		"error":
			border_color = Color(0.9, 0.3, 0.3, 1.0)
			text_color = Color(1.0, 0.85, 0.85, 1.0)
		_:
			border_color = Color(0.4, 0.6, 0.9, 1.0)
			text_color = Color(0.9, 0.95, 1.0, 1.0)

	style.border_color = border_color

	if label:
		label.add_theme_color_override("font_color", text_color)


func _animate_in():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)
	tween.tween_property(self, "position:x", position.x - SLIDE_DISTANCE, FADE_IN_DURATION)


func _start_fade_out():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)

	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.tween_property(self, "position:x", position.x - SLIDE_DISTANCE, FADE_OUT_DURATION)

	await tween.finished
	notification_finished.emit()


func force_close():
	if timer and not timer.is_stopped():
		timer.stop()
	_start_fade_out()
