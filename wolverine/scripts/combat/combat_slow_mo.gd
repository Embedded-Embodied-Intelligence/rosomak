class_name CombatSlowMo
extends Node

## Brief kill/highlight slow-mo using Engine.time_scale, restored on real-time clock
## so mission timers are not permanently broken. Prefer PROCESS_MODE_ALWAYS owners
## for mission clocks (MissionController uses unscaled delta while active).

var _until_msec: int = 0
var _active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("combat_slow_mo")


func pulse(duration_sec: float = 0.15, scale: float = 0.22) -> void:
	if duration_sec <= 0.0:
		return
	_active = true
	_until_msec = Time.get_ticks_msec() + int(duration_sec * 1000.0)
	Engine.time_scale = clampf(scale, 0.08, 1.0)


func _process(_delta: float) -> void:
	if not _active:
		return
	if Time.get_ticks_msec() >= _until_msec:
		Engine.time_scale = 1.0
		_active = false


func _exit_tree() -> void:
	if _active:
		Engine.time_scale = 1.0
		_active = false


static func request(tree: SceneTree, duration_sec: float, scale: float = 0.22) -> void:
	if tree == null:
		return
	var existing := tree.get_first_node_in_group("combat_slow_mo") as CombatSlowMo
	if existing == null:
		existing = CombatSlowMo.new()
		existing.name = "CombatSlowMo"
		tree.root.add_child(existing)
	existing.pulse(duration_sec, scale)
