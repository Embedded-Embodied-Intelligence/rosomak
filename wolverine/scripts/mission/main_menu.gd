extends Control

## Tiny title screen for PROJECT CLAW.

@onready var _title: Label = $Center/Box/Title
@onready var _hint: Label = $Center/Box/Hint


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = "PROJECT CLAW"
	_hint.text = "A / Enter — PLAY\nB / Esc — QUIT"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("attack") or event.is_action_pressed("dodge"):
		get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		get_viewport().set_input_as_handled()
