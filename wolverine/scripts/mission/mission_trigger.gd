class_name MissionTrigger
extends Area3D

## One-shot or repeatable volume trigger for phase advances, checkpoints, and scripted events.

signal triggered(trigger_id: StringName, body: Node3D)

@export var trigger_id: StringName = &"trigger"
@export var once: bool = true
@export var enabled: bool = true

var fired: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	if not has_node("CollisionShape3D"):
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(6, 4, 3)
		col.shape = box
		col.position = Vector3(0, 2, 0)
		add_child(col)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or not body.is_in_group("player"):
		return
	if once and fired:
		return
	fired = true
	triggered.emit(trigger_id, body)


func arm() -> void:
	enabled = true
	fired = false


func disarm() -> void:
	enabled = false


func snapshot() -> Dictionary:
	return {"fired": fired, "enabled": enabled}


func restore(data: Dictionary) -> void:
	fired = bool(data.get("fired", false))
	enabled = bool(data.get("enabled", true))
