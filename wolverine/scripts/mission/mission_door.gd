class_name MissionDoor
extends Node3D

## Sliding / gating door. LOCKED blocks passage; OPENING animates; OPEN clears collision.
## Optional CLOSED is a non-blocking visual-only state used for sealed side panels.

enum State { LOCKED, OPENING, OPEN, CLOSED }

signal state_changed(state: State)
signal opened

@export var door_id: StringName = &"door"
@export var open_duration: float = 1.1
@export var open_offset := Vector3(0.0, 3.2, 0.0)
@export var start_locked: bool = true

var state: State = State.LOCKED
var _progress: float = 0.0
var _rest_position: Vector3
var _body: StaticBody3D
var _mesh: MeshInstance3D
var _collision: CollisionShape3D


func _ready() -> void:
	_rest_position = position
	_ensure_visuals()
	state = State.LOCKED if start_locked else State.OPEN
	_apply_pose(1.0 if state == State.OPEN else 0.0)
	_set_blocking(state != State.OPEN)


func _ensure_visuals() -> void:
	_body = get_node_or_null("Body") as StaticBody3D
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "Body"
		add_child(_body)
		_mesh = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.2, 3.0, 0.25)
		_mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.2, 0.24)
		mat.metallic = 0.55
		mat.roughness = 0.45
		mat.emission_enabled = true
		mat.emission = Color(0.15, 0.55, 0.7)
		mat.emission_energy_multiplier = 0.35
		_mesh.material_override = mat
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(_mesh)
		_collision = CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(3.2, 3.0, 0.35)
		_collision.shape = shape
		_body.add_child(_collision)
	else:
		_mesh = _body.get_node_or_null("Mesh") as MeshInstance3D
		_collision = _body.get_node_or_null("Collision") as CollisionShape3D


func _process(delta: float) -> void:
	if state != State.OPENING:
		return
	_progress = minf(1.0, _progress + delta / maxf(0.05, open_duration))
	_apply_pose(_progress)
	if _progress >= 1.0:
		_finish_open()


func lock() -> void:
	state = State.LOCKED
	_progress = 0.0
	_apply_pose(0.0)
	_set_blocking(true)
	state_changed.emit(state)


func close_visual() -> void:
	## Non-blocking seal (e.g. after player enters an encounter room).
	state = State.CLOSED
	_progress = 0.0
	_apply_pose(0.0)
	_set_blocking(true)
	state_changed.emit(state)


func request_open() -> void:
	if state == State.OPEN or state == State.OPENING:
		return
	state = State.OPENING
	_progress = 0.0
	state_changed.emit(state)
	_sfx(&"door_open")


func force_open() -> void:
	state = State.OPEN
	_progress = 1.0
	_apply_pose(1.0)
	_set_blocking(false)
	state_changed.emit(state)
	opened.emit()


func _finish_open() -> void:
	state = State.OPEN
	_set_blocking(false)
	state_changed.emit(state)
	opened.emit()


func _apply_pose(t: float) -> void:
	position = _rest_position.lerp(_rest_position + open_offset, ease(t, -1.5))


func _set_blocking(blocked: bool) -> void:
	if _collision:
		_collision.disabled = not blocked
	if _body:
		_body.collision_layer = 1 if blocked else 0


func _sfx(sound: StringName) -> void:
	var bus := get_node_or_null("/root/Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, -4.0, 0.04)


## Snapshot helpers for checkpoints.
func snapshot() -> Dictionary:
	return {"state": state, "progress": _progress}


func restore(data: Dictionary) -> void:
	state = int(data.get("state", State.LOCKED)) as State
	_progress = float(data.get("progress", 0.0))
	if state == State.OPEN:
		_apply_pose(1.0)
		_set_blocking(false)
	elif state == State.OPENING:
		_apply_pose(_progress)
		_set_blocking(true)
	else:
		_apply_pose(0.0)
		_set_blocking(true)
	state_changed.emit(state)
