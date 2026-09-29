class_name MissionTrigger
extends Area3D

## One-shot or repeatable volume trigger for phase advances, checkpoints, and scripted events.

signal triggered(trigger_id: StringName, body: Node3D)

@export var trigger_id: StringName = &"trigger"
@export var once: bool = true
@export var enabled: bool = true

var fired: bool = false
var _collision: CollisionShape3D


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_collision(Vector3(6, 4, 3))


func configure(size: Vector3 = Vector3(6, 4, 3)) -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_collision(size)


func _ensure_collision(size: Vector3) -> void:
	if _collision == null:
		_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "CollisionShape3D"
		add_child(_collision)
	var box := (_collision.shape as BoxShape3D)
	if box == null:
		box = BoxShape3D.new()
		_collision.shape = box
	box.size = size
	_collision.position = Vector3(0, size.y * 0.5, 0)


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
