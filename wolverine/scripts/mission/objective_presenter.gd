class_name ObjectivePresenter
extends CanvasLayer

## Brief fade-in objective text. No quest log, compass, or persistent tracker.

signal shown(text: String)
signal hidden

@export var display_seconds: float = 3.2
@export var fade_in: float = 0.35
@export var fade_out: float = 0.55

var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = 12
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -420
	_label.offset_right = 420
	_label.offset_top = 56
	_label.offset_bottom = 120
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	_label.modulate.a = 0.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_label)


func show_objective(text: String, duration: float = -1.0) -> void:
	_label.text = text
	shown.emit(text)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, fade_in)
	var hold := display_seconds if duration < 0.0 else duration
	if hold > 0.0:
		_tween.tween_interval(hold)
		_tween.tween_property(_label, "modulate:a", 0.0, fade_out)
		_tween.tween_callback(func() -> void: hidden.emit())


func clear_objective() -> void:
	if _tween:
		_tween.kill()
	_label.modulate.a = 0.0
	hidden.emit()
