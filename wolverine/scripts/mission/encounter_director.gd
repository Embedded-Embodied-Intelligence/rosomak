class_name EncounterDirector
extends Node

## Staged wave spawner. Uses SpawnEntry markers, attack-token pacing via Enemy.max_attackers,
## and reports living counts to MissionController.

signal wave_started(encounter_id: StringName, wave_index: int)
signal encounter_finished(encounter_id: StringName)
signal enemy_spawned(enemy: Enemy, encounter_id: StringName)

const GRUNT := preload("res://scenes/enemies/grunt.tscn")
const RUNNER := preload("res://scenes/enemies/runner.tscn")
const BRUTE := preload("res://scenes/enemies/brute.tscn")

@export var max_active: int = 5
@export var default_max_attackers: int = 2
@export var spawn_interval: float = 0.55
@export var intro_hold: float = 0.0 ## Delay before first spawn of a wave (heavy readable intro).

var mission: MissionController
var enemies_root: Node3D
var player: Player
var entries: Dictionary = {} ## entry_id -> SpawnEntry

var _queue: Array[Dictionary] = [] ## {scene, entry_id, encounter_id, intro}
var _spawn_timer: float = 0.0
var _intro_left: float = 0.0
var _active_encounter: StringName = &""
var _alive_by_encounter: Dictionary = {}
var _pending_intro: Callable = Callable()
var _finished_encounters: Dictionary = {} ## encounter_id -> bool


func setup(mission_controller: MissionController, root: Node3D, player_ref: Player, spawn_entries: Array) -> void:
	mission = mission_controller
	enemies_root = root
	player = player_ref
	entries.clear()
	for entry in spawn_entries:
		if entry is SpawnEntry:
			entries[entry.entry_id] = entry
	Enemy.max_attackers = default_max_attackers
	Enemy.attackers = 0


func _process(delta: float) -> void:
	# Softlock safeguard: reconcile bookkeeping against real living enemies.
	if not _active_encounter.is_empty():
		_reconcile_and_maybe_finish()
	if _queue.is_empty():
		return
	if _intro_left > 0.0:
		_intro_left -= delta
		return
	var alive_total := _count_alive()
	_spawn_timer -= delta
	if alive_total >= max_active or _spawn_timer > 0.0:
		return
	var job: Dictionary = _queue.pop_front()
	_spawn_enemy(job)
	_spawn_timer = spawn_interval


func begin_encounter(encounter_id: StringName, waves: Array, max_active_override: int = -1) -> void:
	## waves: Array of Array[Dictionary] where each dict is {type, entry, intro?}
	## type: &"grunt" | &"runner" | &"brute"
	_active_encounter = encounter_id
	_alive_by_encounter[encounter_id] = 0
	_finished_encounters.erase(encounter_id)
	if mission:
		mission.encounter_alive[encounter_id] = 0
	if max_active_override > 0:
		max_active = max_active_override
	Enemy.max_attackers = default_max_attackers
	Enemy.attackers = mini(Enemy.attackers, Enemy.max_attackers)
	_queue.clear()
	var wave_index := 0
	for wave in waves:
		wave_started.emit(encounter_id, wave_index)
		for unit in wave:
			var scene := _scene_for(StringName(unit.get("type", &"grunt")))
			_queue.append({
				"scene": scene,
				"entry_id": StringName(unit.get("entry", &"")),
				"encounter_id": encounter_id,
				"intro": bool(unit.get("intro", false)),
				"intro_hold": float(unit.get("intro_hold", 1.25)),
			})
		wave_index += 1
	_spawn_timer = 0.0
	_intro_left = 0.0


func clear_all() -> void:
	_queue.clear()
	_intro_left = 0.0
	for child in enemies_root.get_children():
		# Mark dead before free so _exit_tree does not re-emit died into a cleared book.
		if child is Enemy and child.state != Enemy.State.DEAD:
			child.state = Enemy.State.DEAD
			child.remove_from_group("enemies")
		child.queue_free()
	_alive_by_encounter.clear()
	_finished_encounters.clear()
	_active_encounter = &""
	Enemy.attackers = 0
	if mission:
		mission.encounter_alive.clear()


func _spawn_enemy(job: Dictionary) -> void:
	var entry_id: StringName = job.get("entry_id", &"")
	var entry: SpawnEntry = entries.get(entry_id)
	var spawn_pos := player.global_position + Vector3(0, 0.05, -6.0)
	if entry:
		if job.get("intro", false):
			entry.prepare_entry()
			_intro_left = float(job.get("intro_hold", 1.25))
			_pending_intro = func() -> void: pass
		else:
			entry.prepare_entry()
		spawn_pos = entry.spawn_position()
	elif entries.size() > 0:
		# Fallback: farthest entry from player.
		var best: SpawnEntry = null
		var best_d := -1.0
		for e in entries.values():
			var d: float = e.global_position.distance_to(player.global_position)
			if d > best_d:
				best_d = d
				best = e
		if best:
			best.prepare_entry()
			spawn_pos = best.spawn_position()

	if job.get("intro", false) and _intro_left > 0.0:
		# Re-queue after intro hold so silhouette/door open is readable first.
		_queue.push_front(job)
		job["intro"] = false
		return

	var enemy := (job.scene as PackedScene).instantiate() as Enemy
	enemy.position = spawn_pos
	var encounter_id: StringName = job.get("encounter_id", _active_encounter)
	enemy.set_meta("encounter_id", encounter_id)
	enemy.died.connect(_on_enemy_died)
	enemies_root.add_child(enemy)
	_alive_by_encounter[encounter_id] = int(_alive_by_encounter.get(encounter_id, 0)) + 1
	mission.notify_encounter_spawned(encounter_id, 1)
	enemy_spawned.emit(enemy, encounter_id)


func _on_enemy_died(enemy: Enemy) -> void:
	var encounter_id: StringName = enemy.get_meta("encounter_id", _active_encounter)
	_alive_by_encounter[encounter_id] = maxi(0, int(_alive_by_encounter.get(encounter_id, 0)) - 1)
	mission.notify_enemy_died(encounter_id)
	_debug_encounter(encounter_id, "enemy_died")
	_try_finish(encounter_id)


func _count_alive() -> int:
	var total := 0
	for child in enemies_root.get_children():
		if child is Enemy and is_instance_valid(child) and child.state != Enemy.State.DEAD:
			total += 1
	return total


func _count_alive_in(encounter_id: StringName) -> int:
	var total := 0
	if enemies_root == null:
		return 0
	for child in enemies_root.get_children():
		if not (child is Enemy) or not is_instance_valid(child):
			continue
		if child.state == Enemy.State.DEAD:
			continue
		if child.get_meta("encounter_id", _active_encounter) != encounter_id:
			continue
		total += 1
	return total


func alive_in(encounter_id: StringName) -> int:
	# Prefer scene truth so removed/unreachable orphans cannot softlock.
	return _count_alive_in(encounter_id)


func has_pending() -> bool:
	return not _queue.is_empty() or _intro_left > 0.0


func _try_finish(encounter_id: StringName) -> void:
	if encounter_id.is_empty():
		return
	if _finished_encounters.get(encounter_id, false):
		return
	if has_pending():
		return
	var living := _count_alive_in(encounter_id)
	_alive_by_encounter[encounter_id] = living
	if mission:
		mission.encounter_alive[encounter_id] = living
	if living > 0:
		return
	_finished_encounters[encounter_id] = true
	_debug_encounter(encounter_id, "encounter_finished")
	encounter_finished.emit(encounter_id)
	if _active_encounter == encounter_id:
		_active_encounter = &""


func _reconcile_and_maybe_finish() -> void:
	var encounter_id := _active_encounter
	if encounter_id.is_empty():
		return
	# Drop invalid / freed children that never emitted died.
	var tracked := int(_alive_by_encounter.get(encounter_id, 0))
	var living := _count_alive_in(encounter_id)
	if living != tracked:
		_alive_by_encounter[encounter_id] = living
		if mission:
			mission.encounter_alive[encounter_id] = living
		_debug_encounter(encounter_id, "reconcile living=%d tracked_was=%d" % [living, tracked])
	if living == 0 and not has_pending():
		_try_finish(encounter_id)


func _debug_encounter(encounter_id: StringName, reason: String) -> void:
	if not OS.is_debug_build():
		return
	print(
		"[Encounter] %s id=%s remaining=%d pending=%s queue=%d"
		% [
			reason,
			String(encounter_id),
			_count_alive_in(encounter_id),
			str(has_pending()),
			_queue.size(),
		]
	)


func _scene_for(type_name: StringName) -> PackedScene:
	match type_name:
		&"runner":
			return RUNNER
		&"brute":
			return BRUTE
		_:
			return GRUNT
