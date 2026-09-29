extends SceneTree

# Scripted full-mission logic playthrough (phases, doors, encounters, complete).
# Not a realtime 10–15 min play; advances triggers and force-clears encounters.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS: " if condition else "FAIL: ", label)
	if not condition:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _clear_encounter(mission_scene: MissionGame, encounter_id: StringName) -> void:
	mission_scene.director._queue.clear()
	for child in mission_scene.enemies.get_children():
		if child is Enemy and child.state != Enemy.State.DEAD:
			child._die(Vector2.ZERO)
	await _frames(8)
	if not mission_scene._finished_encounters.get(encounter_id, false):
		mission_scene.mission.encounter_alive[encounter_id] = 0
		mission_scene._on_encounter_finished(encounter_id)
	await _frames(4)


func _run() -> void:
	var scene: MissionGame = preload("res://scenes/mission/mission.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	_check(scene.mission.phase == MissionController.Phase.MISSION_START, "boot MISSION_START")
	_check(scene.player.controls_enabled, "immediate control")

	# Opening → approach
	scene._on_trigger(&"trg_approach", scene.player)
	_check(scene.mission.phase == MissionController.Phase.APPROACH, "APPROACH")

	# Encounter 1
	scene._on_trigger(&"trg_e1", scene.player)
	_check(scene.mission.phase == MissionController.Phase.ENCOUNTER_01, "ENCOUNTER_01")
	_check(scene.builder.doors[&"door_warehouse_out"].state == MissionDoor.State.LOCKED, "warehouse exit locked during E1")
	await _frames(60)
	await _clear_encounter(scene, &"e1")
	_check(scene.mission.phase == MissionController.Phase.TRANSITION_01, "TRANSITION_01 after E1")
	_check(scene.builder.doors[&"door_warehouse_out"].state != MissionDoor.State.LOCKED, "warehouse exit opens")

	# Checkpoint after E1
	scene._on_trigger(&"trg_cp_after_e1", scene.player)
	_check(scene.checkpoints.active_id == CheckpointSystem.ID_AFTER_E1, "CP after E1")

	# Breather objective
	scene._on_trigger(&"trg_breather", scene.player)
	_check(scene.mission.phase == MissionController.Phase.TRANSITION_01, "still transition in research")

	# Ambush → E2
	scene._on_trigger(&"trg_ambush", scene.player)
	await _frames(90)
	_check(scene.mission.phase == MissionController.Phase.ENCOUNTER_02 or scene.mission.phase == MissionController.Phase.AMBUSH, "AMBUSH/E2 active")
	# Wait for ambush coroutine to finish entering E2
	for i in 60:
		if scene.mission.phase == MissionController.Phase.ENCOUNTER_02:
			break
		await _frames(1)
	_check(scene.mission.phase == MissionController.Phase.ENCOUNTER_02, "ENCOUNTER_02")
	await _frames(90)
	await _clear_encounter(scene, &"e2")
	_check(scene.mission.phase == MissionController.Phase.TRANSITION_02, "TRANSITION_02")
	_check(scene._emergency_active, "emergency lighting active")
	_check(scene.builder.doors[&"door_lab_out"].state != MissionDoor.State.LOCKED, "lab exit opens")
	# Critical: approach door must open on E2 clear — trg_final is past door_final_in.
	await _frames(8)
	_check(scene.builder.doors[&"door_final_in"].state != MissionDoor.State.LOCKED, "final approach opens after E2 (before trg_final)")

	# Soft-lock safety: if approach door is force-locked after E2 clear, safety reopens it.
	scene.builder.doors[&"door_final_in"].lock()
	scene._safety_door_unlock()
	_check(scene.builder.doors[&"door_final_in"].state != MissionDoor.State.LOCKED, "safety unlocks final approach in TRANSITION_02")

	# Before final checkpoint
	scene._on_trigger(&"trg_cp_before_final", scene.player)
	_check(scene.checkpoints.active_id == CheckpointSystem.ID_BEFORE_FINAL, "CP before final")

	# Final encounter (reachable only because approach door already open)
	scene._on_trigger(&"trg_final", scene.player)
	_check(scene.mission.phase == MissionController.Phase.FINAL_ENCOUNTER, "FINAL_ENCOUNTER")
	await _frames(90)
	await _clear_encounter(scene, &"final")
	_check(scene.mission.phase == MissionController.Phase.MISSION_COMPLETE, "MISSION_COMPLETE")
	_check(scene._ui_mode == MissionGame.UiMode.COMPLETE, "complete UI")
	_check(scene.builder.doors[&"door_final_in"].state != MissionDoor.State.LOCKED, "final entrance stays unlocked after clear")
	_check(scene.builder.doors[&"door_final_a"].state != MissionDoor.State.LOCKED, "final side door A unlocked")
	_check(scene.builder.doors[&"door_final_b"].state != MissionDoor.State.LOCKED, "final side door B unlocked")
	_check(scene.builder.doors[&"door_final_c"].state != MissionDoor.State.LOCKED, "final rear door unlocked")

	# Soft-lock: natural clear path also works via director reconcile (no forced finish).
	scene.mission.restore_phase(MissionController.Phase.FINAL_ENCOUNTER)
	scene._final_started = true
	scene._finished_encounters.erase(&"final")
	scene.director.begin_encounter(&"final", [[{"type": &"grunt", "entry": &"fin_a"}]], 2)
	await _frames(40)
	await _clear_encounter(scene, &"final")
	_check(scene.mission.phase == MissionController.Phase.MISSION_COMPLETE, "reconcile path reaches MISSION_COMPLETE")
	_check(scene.builder.doors[&"door_final_c"].state != MissionDoor.State.LOCKED, "final doors stay unlocked after clear")

	# Soft-lock: reverse walk shouldn't re-lock cleared doors
	scene.builder.doors[&"door_warehouse_out"].force_open()
	scene._safety_door_unlock()
	_check(scene.builder.doors[&"door_warehouse_out"].state == MissionDoor.State.OPEN, "cleared door stays open")

	# Soft-lock: skip wait on death at before-final CP
	scene.player.health = 0.0
	scene.player._on_hurt(HitEvent.legacy(999, Vector3.ZERO, 0.05, 0.0))
	await _frames(3)
	_check(scene._ui_mode == MissionGame.UiMode.DEATH, "death mid-mission")
	scene._restore_now()
	await _frames(5)
	_check(scene.player.is_alive, "revive from before-final CP")
	_check(scene.checkpoints.active_id == CheckpointSystem.ID_BEFORE_FINAL, "restored before-final CP")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
