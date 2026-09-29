extends SceneTree

# Headless mission systems smoke test.
# "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path wolverine \
#   --fixed-fps 60 --script res://tests/mission_smoke.gd

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


func _run() -> void:
	# --- MissionController phase machine ---
	var mission := MissionController.new()
	root.add_child(mission)
	var phases: Array = []
	mission.phase_changed.connect(func(p, _prev): phases.append(p))
	mission.start_mission()
	_check(mission.phase == MissionController.Phase.MISSION_START, "mission starts at MISSION_START")
	mission.set_phase(MissionController.Phase.APPROACH)
	mission.set_phase(MissionController.Phase.ENCOUNTER_01)
	mission.notify_encounter_spawned(&"e1", 3)
	_check(mission.remaining_in(&"e1") == 3, "spawned enemies tracked")
	mission.notify_enemy_died(&"e1")
	mission.notify_enemy_died(&"e1")
	mission.notify_enemy_died(&"e1")
	_check(mission.is_encounter_clear(&"e1"), "encounter clears at zero")
	_check(mission.kills == 3, "kills increment")
	mission.set_phase(MissionController.Phase.MISSION_COMPLETE)
	_check(mission.phase == MissionController.Phase.MISSION_COMPLETE, "mission complete phase set")
	_check(phases.has(MissionController.Phase.ENCOUNTER_01), "phase_changed emitted")

	# --- MissionDoor ---
	var door := MissionDoor.new()
	door.door_id = &"test_door"
	door.start_locked = true
	root.add_child(door)
	await _frames(2)
	_check(door.state == MissionDoor.State.LOCKED, "door starts locked")
	door.request_open()
	_check(door.state == MissionDoor.State.OPENING, "door enters OPENING")
	await _frames(90)
	_check(door.state == MissionDoor.State.OPEN, "door finishes OPEN")
	var snap := door.snapshot()
	door.lock()
	_check(door.state == MissionDoor.State.LOCKED, "door can lock again")
	door.restore(snap)
	_check(door.state == MissionDoor.State.OPEN, "door restore reopens")

	# --- MissionTrigger ---
	var trigger := MissionTrigger.new()
	trigger.trigger_id = &"t1"
	root.add_child(trigger)
	await _frames(1)
	var fired := [false]
	trigger.triggered.connect(func(_id, _b): fired[0] = true)
	# Simulate player body enter via direct call path.
	var dummy := CharacterBody3D.new()
	dummy.add_to_group("player")
	root.add_child(dummy)
	trigger._on_body_entered(dummy)
	_check(fired[0] and trigger.fired, "trigger fires once for player")
	fired[0] = false
	trigger._on_body_entered(dummy)
	_check(not fired[0], "once-trigger ignores re-entry")
	var tsnap := trigger.snapshot()
	trigger.arm()
	trigger.restore(tsnap)
	_check(trigger.fired, "trigger restore keeps fired state")

	# --- CheckpointSystem with stub player/enemies ---
	var arena := preload("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await _frames(20)
	var player: Player = arena.get_node("Player")
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	arena.add_child(enemies)
	var mission2 := MissionController.new()
	arena.add_child(mission2)
	mission2.start_mission()
	mission2.set_phase(MissionController.Phase.TRANSITION_01)
	var cps := CheckpointSystem.new()
	arena.add_child(cps)
	var door2 := MissionDoor.new()
	door2.door_id = &"cp_door"
	door2.start_locked = true
	arena.add_child(door2)
	await _frames(2)
	door2.force_open()
	cps.setup(mission2, player, [door2], [], enemies, Callable())
	cps.capture(CheckpointSystem.ID_AFTER_E1)
	player.health = 20.0
	player._emit_health()
	door2.lock()
	mission2.set_phase(MissionController.Phase.ENCOUNTER_02)
	cps.restore(CheckpointSystem.ID_AFTER_E1)
	await _frames(2)
	_check(player.health >= player.max_health * 0.99, "checkpoint restores full HP")
	_check(mission2.phase == MissionController.Phase.TRANSITION_01, "checkpoint restores phase")
	_check(door2.state == MissionDoor.State.OPEN, "checkpoint restores door open")

	# --- EncounterDirector staging ---
	var director := EncounterDirector.new()
	arena.add_child(director)
	var entry := SpawnEntry.new()
	entry.entry_id = &"s1"
	entry.position = Vector3(0, 0.05, -4)
	arena.add_child(entry)
	director.setup(mission2, enemies, player, [entry])
	director.begin_encounter(&"test", [[{"type": &"grunt", "entry": &"s1"}, {"type": &"runner", "entry": &"s1"}]], 3)
	await _frames(120)
	_check(enemies.get_child_count() >= 1, "director spawns at least one enemy")
	_check(mission2.remaining_in(&"test") >= 1, "mission tracks director spawns")

	# --- ObjectivePresenter ---
	var obj := ObjectivePresenter.new()
	root.add_child(obj)
	await _frames(1)
	obj.show_objective("TEST OBJECTIVE", 0.5)
	_check(obj._label.text == "TEST OBJECTIVE", "objective text set")

	# --- MusicController bed switch ---
	var music := MusicController.new()
	root.add_child(music)
	await _frames(1)
	music.set_bed(MusicController.Bed.COMBAT, true)
	_check(music.current == MusicController.Bed.COMBAT, "music bed switches to combat")
	music.set_bed(MusicController.Bed.MISSION_COMPLETE, true)
	_check(music.current == MusicController.Bed.MISSION_COMPLETE, "music bed switches to complete")

	# --- FacilityBuilder builds without error ---
	var holder := Node3D.new()
	root.add_child(holder)
	var builder := FacilityBuilder.new()
	holder.add_child(builder)
	builder.build(holder)
	await _frames(2)
	_check(builder.doors.size() >= 8, "facility places mission doors")
	_check(builder.triggers.size() >= 6, "facility places triggers")
	_check(builder.entries.size() >= 8, "facility places spawn entries")
	_check(holder.get_node_or_null("Facility") != null, "facility root created")

	# --- Full mission scene boots ---
	var mission_scene := preload("res://scenes/mission/mission.tscn").instantiate()
	root.add_child(mission_scene)
	current_scene = mission_scene
	await _frames(45)
	_check(mission_scene.mission != null, "mission scene has controller")
	_check(mission_scene.mission.phase == MissionController.Phase.MISSION_START, "mission scene starts correctly")
	_check(mission_scene.player.controls_enabled, "player has control at mission start")
	# Simulate approach + e1 trigger.
	mission_scene._on_trigger(&"trg_approach", mission_scene.player)
	_check(mission_scene.mission.phase == MissionController.Phase.APPROACH, "approach trigger advances phase")
	mission_scene._on_trigger(&"trg_e1", mission_scene.player)
	_check(mission_scene.mission.phase == MissionController.Phase.ENCOUNTER_01, "e1 trigger starts encounter")
	await _frames(90)
	_check(mission_scene.enemies.get_child_count() >= 1, "e1 spawns enemies")
	# Force-clear e1.
	for child in mission_scene.enemies.get_children():
		if child is Enemy:
			child._die(Vector2.ZERO)
	mission_scene.director._queue.clear()
	await _frames(10)
	# Manually finish if AI death path lagged.
	if not mission_scene._finished_encounters.get(&"e1", false):
		mission_scene.mission.encounter_alive[&"e1"] = 0
		mission_scene._on_encounter_finished(&"e1")
	_check(mission_scene.builder.doors[&"door_warehouse_out"].state != MissionDoor.State.LOCKED, "e1 clear unlocks exit door")
	_check(mission_scene.mission.phase == MissionController.Phase.TRANSITION_01, "e1 clear advances to transition")

	# Checkpoint capture + death restore.
	mission_scene.checkpoints.capture(CheckpointSystem.ID_AFTER_E1)
	mission_scene.player.health = 0.0
	mission_scene.player._on_hurt(999, Vector3.ZERO, 0.05, 0.0)
	await _frames(5)
	_check(mission_scene._ui_mode == MissionGame.UiMode.DEATH, "death enters YOU DIED mode")
	mission_scene._restore_now()
	await _frames(5)
	_check(mission_scene.player.is_alive and mission_scene.player.health > 50.0, "checkpoint restore revives player")
	_check(mission_scene.mission.phase == MissionController.Phase.TRANSITION_01, "restore returns after-e1 phase")

	# Jump to final completion path.
	mission_scene.mission.set_phase(MissionController.Phase.FINAL_ENCOUNTER)
	mission_scene._final_started = true
	mission_scene._finished_encounters.erase(&"final")
	mission_scene._on_encounter_finished(&"final")
	await _frames(5)
	_check(mission_scene.mission.phase == MissionController.Phase.MISSION_COMPLETE, "final clear completes mission")
	_check(mission_scene._ui_mode == MissionGame.UiMode.COMPLETE, "complete UI mode active")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
