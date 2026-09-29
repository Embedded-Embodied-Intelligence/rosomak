class_name CheckpointSystem
extends Node

## Session-only checkpoints. Restores player HP, mission phase, doors, triggers, and enemies.

signal restored(checkpoint_id: StringName)

const ID_START := &"mission_start"
const ID_AFTER_E1 := &"after_encounter_01"
const ID_BEFORE_FINAL := &"before_final"

var active_id: StringName = ID_START
var _snapshots: Dictionary = {} ## id -> snapshot dict
var _mission: MissionController
var _player: Player
var _doors: Dictionary = {} ## door_id -> MissionDoor
var _triggers: Dictionary = {} ## trigger_id -> MissionTrigger
var _enemies_root: Node3D
var _spawn_callback: Callable ## (snapshot) -> void clears + respawns encounter state


func setup(
	mission: MissionController,
	player: Player,
	doors: Array,
	triggers: Array,
	enemies_root: Node3D,
	spawn_callback: Callable
) -> void:
	_mission = mission
	_player = player
	_enemies_root = enemies_root
	_spawn_callback = spawn_callback
	_doors.clear()
	for door in doors:
		if door is MissionDoor:
			_doors[door.door_id] = door
	_triggers.clear()
	for trigger in triggers:
		if trigger.has_method("snapshot"):
			_triggers[trigger.trigger_id] = trigger
	capture(ID_START)


func capture(checkpoint_id: StringName) -> void:
	var door_data := {}
	for id in _doors:
		door_data[id] = _doors[id].snapshot()
	var trigger_data := {}
	for id in _triggers:
		trigger_data[id] = _triggers[id].snapshot()
	_snapshots[checkpoint_id] = {
		"phase": _mission.phase,
		"player_health": _player.max_health,
		"player_rage": 0.0,
		"player_position": _player.global_position,
		"player_yaw": _player.visuals.rotation.y,
		"camera_yaw": _player.camera_pivot.rotation.y,
		"doors": door_data,
		"triggers": trigger_data,
		"encounter_alive": _mission.encounter_alive.duplicate(),
		"kills": _mission.kills,
	}
	active_id = checkpoint_id
	_mission.notify_checkpoint(checkpoint_id)


func restore(checkpoint_id: StringName = &"") -> void:
	var id := checkpoint_id if checkpoint_id != &"" else active_id
	if not _snapshots.has(id):
		id = ID_START
	var data: Dictionary = _snapshots[id]
	active_id = id

	# Clear live enemies.
	for child in _enemies_root.get_children():
		child.queue_free()
	Enemy.attackers = 0
	Enemy.max_attackers = 2

	_player.health = float(data.get("player_health", _player.max_health))
	_player.rage = float(data.get("player_rage", 0.0))
	_player.rage_left = 0.0
	_player.grace_left = 0.8
	_player.since_damage = 0.0
	_player.hit_chain = 0
	_player.controls_enabled = true
	if _player.state == Player.State.DEAD:
		_player.state = Player.State.IDLE
		_player.state_time = 0.0
		_player.hurtbox.enabled = true
		_player.hurtbox.collision_layer = 32
		_player.set_deferred("collision_layer", 2)
		_player.set_deferred("collision_mask", 1)
		_player.animator.play(&"idle")
	_player._emit_health()
	_player.rage_changed.emit(_player.rage, false)
	_player.global_position = data.get("player_position", _player.global_position)
	_player.visuals.rotation.y = float(data.get("player_yaw", 0.0))
	_player.camera_pivot.rotation.y = float(data.get("camera_yaw", 0.0))
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()

	for door_id in data.get("doors", {}):
		if _doors.has(door_id):
			_doors[door_id].restore(data["doors"][door_id])
	for trigger_id in data.get("triggers", {}):
		if _triggers.has(trigger_id):
			_triggers[trigger_id].restore(data["triggers"][trigger_id])

	_mission.encounter_alive = data.get("encounter_alive", {}).duplicate()
	_mission.kills = int(data.get("kills", 0))
	_mission.restore_phase(int(data.get("phase", MissionController.Phase.MISSION_START)) as MissionController.Phase)

	if _spawn_callback.is_valid():
		_spawn_callback.call(data)

	restored.emit(id)
