class_name MissionGame
extends Node3D

## PROJECT CLAW — linear facility mission. Extends existing combat systems; does not replace them.

enum UiMode { PLAYING, DEATH, COMPLETE }

const KILL_RAGE := 10.0
const DEATH_HOLD := 1.4
const COMPLETE_HOLD := 3.5

@onready var player: Player = $Player
@onready var hud: Hud = $Hud
@onready var enemies: Node3D = $Enemies

var mission: MissionController
var checkpoints: CheckpointSystem
var director: EncounterDirector
var objectives: ObjectivePresenter
var music: MusicController
var builder: FacilityBuilder

var _ui_mode: UiMode = UiMode.PLAYING
var _ui_timer: float = 0.0
var _e1_started: bool = false
var _e2_started: bool = false
var _final_started: bool = false
var _ambush_done: bool = false
var _scripted_running: bool = false
var _final_brute: Enemy
var _flicker_time: float = 0.0
var _emergency_active: bool = false
var _finished_encounters: Dictionary = {}


func _ready() -> void:
	Enemy.attackers = 0
	Enemy.max_attackers = 2
	mission = MissionController.new()
	mission.name = "MissionController"
	add_child(mission)
	director = EncounterDirector.new()
	director.name = "EncounterDirector"
	add_child(director)
	checkpoints = CheckpointSystem.new()
	checkpoints.name = "CheckpointSystem"
	add_child(checkpoints)
	objectives = ObjectivePresenter.new()
	objectives.name = "ObjectivePresenter"
	add_child(objectives)
	music = MusicController.new()
	music.name = "MusicController"
	add_child(music)

	builder = FacilityBuilder.new()
	builder.name = "FacilityBuilder"
	add_child(builder)
	builder.build(self)

	player.global_position = builder.player_spawn
	player.controls_enabled = true
	player.spring_arm.spring_length = 3.4
	player.spring_arm.margin = 0.25
	player.health_changed.connect(hud.set_health)
	player.rage_changed.connect(hud.set_rage)
	player.hit_chain_changed.connect(hud.set_hit_chain)
	player.hurt.connect(hud.flash_hurt)
	player.died.connect(_on_player_died)
	player.attack_hitbox.hit_landed.connect(_on_player_hit_landed)
	player.context_prompt_changed.connect(hud.set_context_prompt)
	player.tutorial_requested.connect(hud.show_tutorial)
	hud.set_health(player.max_health, player.max_health)
	hud.set_rage(0.0, false)
	hud.pause_allowed = true
	hud.set_mission_labels(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	director.setup(mission, enemies, player, builder.entries.values())
	director.encounter_finished.connect(_on_encounter_finished)
	director.enemy_spawned.connect(func(enemy: Enemy, _id: StringName) -> void:
		enemy.died.connect(func(_e: Enemy) -> void: player.add_rage(KILL_RAGE))
	)
	director.max_active = 5

	checkpoints.setup(
		mission,
		player,
		builder.doors.values(),
		builder.triggers.values(),
		enemies,
		_on_checkpoint_respawn
	)

	for t in builder.triggers.values():
		t.triggered.connect(_on_trigger)

	mission.phase_changed.connect(_on_phase_changed)
	mission.objective_requested.connect(objectives.show_objective)
	mission.encounter_cleared.connect(_on_encounter_cleared)
	mission.mission_complete.connect(_on_mission_complete)

	mission.start_mission()
	music.set_bed(MusicController.Bed.EXPLORATION)
	# Soft open door path ahead.
	builder.doors[&"door_entrance"].force_open()


func _unhandled_input(event: InputEvent) -> void:
	if _ui_mode == UiMode.DEATH:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("attack") or event.is_action_pressed("dodge"):
			_restore_now()
			get_viewport().set_input_as_handled()
		return
	if _ui_mode == UiMode.COMPLETE:
		if _ui_timer < COMPLETE_HOLD:
			return
		if event.is_action_pressed("ui_accept"):
			get_tree().change_scene_to_file("res://scenes/mission/main_menu.tscn")
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			get_tree().quit()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _ui_mode == UiMode.DEATH:
		_ui_timer += delta
		if _ui_timer >= DEATH_HOLD:
			_restore_now()
		return
	if _ui_mode == UiMode.COMPLETE:
		_ui_timer += delta
		return

	_update_hud_counts()
	if _emergency_active:
		_flicker_time += delta
		_update_emergency_flicker()

	# Soft-lock safety: if encounter clear but door still locked, unlock.
	_safety_door_unlock()


func _on_phase_changed(phase: MissionController.Phase, _previous: MissionController.Phase) -> void:
	match phase:
		MissionController.Phase.MISSION_START:
			objectives.show_objective("INFILTRATE THE FACILITY")
			music.set_bed(MusicController.Bed.EXPLORATION)
		MissionController.Phase.APPROACH:
			objectives.show_objective("ADVANCE THROUGH MAINTENANCE")
		MissionController.Phase.ENCOUNTER_01:
			objectives.show_objective("CLEAR THE WAREHOUSE")
			music.set_bed(MusicController.Bed.COMBAT)
			music.set_intensity(MusicController.Intensity.COMBAT_LOW)
		MissionController.Phase.TRANSITION_01:
			objectives.show_objective("PROCEED INTO RESEARCH")
			music.set_bed(MusicController.Bed.EXPLORATION)
			music.set_intensity(MusicController.Intensity.NONE)
		MissionController.Phase.AMBUSH:
			objectives.show_objective("SURVIVE THE BREACH")
			music.set_bed(MusicController.Bed.COMBAT)
			music.set_intensity(MusicController.Intensity.COMBAT_HIGH)
		MissionController.Phase.ENCOUNTER_02:
			objectives.show_objective("SECURE THE LAB")
			music.set_intensity(MusicController.Intensity.COMBAT_HIGH)
		MissionController.Phase.TRANSITION_02:
			objectives.show_objective("GO DEEPER")
			music.set_bed(MusicController.Bed.EXPLORATION)
			music.set_intensity(MusicController.Intensity.NONE)
			_activate_emergency()
			# Approach door must open here — trg_final sits past door_final_in.
			_unlock_final_approach()
		MissionController.Phase.FINAL_ENCOUNTER:
			objectives.show_objective("DESTROY ALL HOSTILES")
			music.set_bed(MusicController.Bed.FINAL_COMBAT)
			music.set_intensity(MusicController.Intensity.FINAL)
		MissionController.Phase.MISSION_COMPLETE:
			music.set_bed(MusicController.Bed.MISSION_COMPLETE)


func _on_trigger(trigger_id: StringName, _body: Node3D) -> void:
	match trigger_id:
		&"trg_approach":
			if mission.phase == MissionController.Phase.MISSION_START:
				mission.set_phase(MissionController.Phase.APPROACH)
		&"trg_e1":
			_start_encounter_01()
		&"trg_breather":
			if mission.phase == MissionController.Phase.ENCOUNTER_01:
				# Should only fire after clear, but allow if somehow past.
				pass
			if mission.phase <= MissionController.Phase.TRANSITION_01:
				if mission.phase == MissionController.Phase.ENCOUNTER_01 and not mission.is_encounter_clear(&"e1"):
					return
				if mission.phase < MissionController.Phase.TRANSITION_01:
					mission.set_phase(MissionController.Phase.TRANSITION_01)
				objectives.show_objective("INVESTIGATE THE LAB WING")
		&"trg_cp_after_e1":
			if mission.phase >= MissionController.Phase.TRANSITION_01:
				checkpoints.capture(CheckpointSystem.ID_AFTER_E1)
		&"trg_ambush":
			_start_ambush_event()
		&"trg_transition2":
			if mission.phase == MissionController.Phase.ENCOUNTER_02 and mission.is_encounter_clear(&"e2"):
				mission.set_phase(MissionController.Phase.TRANSITION_02)
			elif mission.phase == MissionController.Phase.ENCOUNTER_02:
				pass
			elif mission.phase < MissionController.Phase.TRANSITION_02 and mission.phase >= MissionController.Phase.ENCOUNTER_02:
				mission.set_phase(MissionController.Phase.TRANSITION_02)
		&"trg_cp_before_final":
			if mission.phase >= MissionController.Phase.TRANSITION_02:
				checkpoints.capture(CheckpointSystem.ID_BEFORE_FINAL)
		&"trg_final":
			_start_final_encounter()


func _start_encounter_01() -> void:
	if _e1_started:
		return
	_e1_started = true
	mission.set_phase(MissionController.Phase.ENCOUNTER_01)
	# Seal entrance behind player for arena feel (still escapable via soft-lock safety only after clear).
	if builder.doors.has(&"door_warehouse_in"):
		builder.doors[&"door_warehouse_in"].close_visual()
	hud.banner("HOSTILES", "Warehouse contact", 1.8, "", 56)
	director.begin_encounter(&"e1", [
		[
			{"type": &"grunt", "entry": &"e1_a"},
			{"type": &"grunt", "entry": &"e1_b"},
			{"type": &"runner", "entry": &"e1_c"},
		]
	], 4)
	# Nudge a crate for cheap env feedback.
	var crate = builder.env_fx.get("nudge_crate")
	if crate is Node3D:
		var tw := create_tween()
		tw.tween_property(crate, "rotation_degrees:z", 8.0, 0.25)
		tw.tween_property(crate, "rotation_degrees:z", 3.0, 0.4)


func _start_ambush_event() -> void:
	if _ambush_done:
		return
	_ambush_done = true
	mission.set_phase(MissionController.Phase.AMBUSH)
	_scripted_running = true
	_sfx(&"power_fail", -2.0, 0.0)
	# Flicker lights briefly; keep player control.
	var lab_lights: Array = builder.lights.get("Lab", [])
	for light in lab_lights:
		if light is Light3D:
			var base_energy: float = light.light_energy
			var tw := create_tween()
			tw.tween_property(light, "light_energy", 0.05, 0.12)
			tw.tween_property(light, "light_energy", base_energy * 0.4, 0.1)
			tw.tween_property(light, "light_energy", 0.08, 0.08)
			tw.tween_property(light, "light_energy", base_energy, 0.35)
	# Optional brief camera nudge.
	player._kick_camera(2.2)
	# Shutter / glass breach.
	var glass = builder.env_fx.get("break_glass")
	if glass is Node3D:
		_sfx(&"glass", -1.0, 0.05)
		glass.visible = false
		if glass is StaticBody3D:
			for c in glass.get_children():
				if c is CollisionShape3D:
					c.disabled = true
	var shutter = builder.env_fx.get("shutter")
	if shutter is Node3D:
		var st := create_tween()
		st.tween_property(shutter, "position:y", shutter.position.y + 3.2, 0.7)
	await get_tree().create_timer(0.55).timeout
	_scripted_running = false
	mission.set_phase(MissionController.Phase.ENCOUNTER_02)
	_start_encounter_02()


func _start_encounter_02() -> void:
	if _e2_started:
		return
	_e2_started = true
	if builder.doors.has(&"door_lab_in"):
		builder.doors[&"door_lab_in"].close_visual()
	hud.banner("AMBUSH", "Lab security inbound", 1.6, "", 52)
	director.begin_encounter(&"e2", [
		[
			{"type": &"grunt", "entry": &"e2_a"},
			{"type": &"grunt", "entry": &"e2_b"},
			{"type": &"runner", "entry": &"e2_side"},
		],
		[
			{"type": &"grunt", "entry": &"e2_side"},
			{"type": &"brute", "entry": &"e2_heavy", "intro": true, "intro_hold": 1.35},
		],
	], 5)
	# Side door opens with second wave via spawn entry link.


func _start_final_encounter() -> void:
	if _final_started:
		return
	if mission.phase < MissionController.Phase.TRANSITION_02:
		# Coming from lab clear path.
		if mission.phase == MissionController.Phase.ENCOUNTER_02 and not mission.is_encounter_clear(&"e2"):
			return
	_final_started = true
	mission.set_phase(MissionController.Phase.FINAL_ENCOUNTER)
	builder.doors[&"door_final_in"].request_open()
	hud.banner("FINAL SECTOR", "Experiment chamber", 2.0, "", 52)
	director.begin_encounter(&"final", [
		[
			{"type": &"grunt", "entry": &"fin_a"},
			{"type": &"grunt", "entry": &"fin_b"},
			{"type": &"runner", "entry": &"fin_c"},
		],
		[
			{"type": &"grunt", "entry": &"fin_d"},
			{"type": &"runner", "entry": &"fin_e"},
		],
		[
			{"type": &"brute", "entry": &"fin_c", "intro": true, "intro_hold": 1.45},
			{"type": &"grunt", "entry": &"fin_a"},
		],
	], 5)
	if not director.enemy_spawned.is_connected(_track_final_brute):
		director.enemy_spawned.connect(_track_final_brute)


func _track_final_brute(enemy: Enemy, encounter_id: StringName) -> void:
	if encounter_id != &"final" or _final_brute != null:
		return
	# Brute archetype has elevated poise / health vs grunt.
	if enemy.poise > 0 or enemy.max_health >= 120:
		_final_brute = enemy
		enemy.died.connect(_on_final_brute_died)


func _on_final_brute_died(_enemy: Enemy) -> void:
	# Finisher juice: stronger hit-stop + brief slow-mo + impulse. No execution system.
	player.hit_stop_left = maxf(player.hit_stop_left, 0.12)
	player._kick_camera(3.2)
	Engine.time_scale = 0.35
	await get_tree().create_timer(0.2 * Engine.time_scale).timeout
	Engine.time_scale = 1.0


func _on_encounter_finished(encounter_id: StringName) -> void:
	if _finished_encounters.get(encounter_id, false):
		return
	_finished_encounters[encounter_id] = true
	match encounter_id:
		&"e1":
			builder.doors[&"door_warehouse_out"].request_open()
			builder.doors[&"door_warehouse_in"].request_open()
			mission.set_phase(MissionController.Phase.TRANSITION_01)
			objectives.show_objective("CONTINUE THROUGH RESEARCH")
			hud.banner("CLEAR", "Path open", 1.4, "", 48)
			_sfx(&"clear", -2.0, 0.0)
		&"e2":
			builder.doors[&"door_lab_out"].request_open()
			builder.doors[&"door_lab_in"].request_open()
			# Unlock final approach now; trg_final is past this door (z 132 > door z 126).
			_unlock_final_approach()
			mission.set_phase(MissionController.Phase.TRANSITION_02)
			objectives.show_objective("FOLLOW EMERGENCY CORRIDOR")
			hud.banner("LAB SECURE", "Alarms ahead", 1.5, "", 48)
			_sfx(&"clear", -2.0, 0.0)
			_activate_emergency()
		&"final":
			_open_final_doors()
			mission.set_phase(MissionController.Phase.MISSION_COMPLETE)


func _on_encounter_cleared(encounter_id: StringName) -> void:
	# Mirror finished when the director still has an empty queue race.
	if _finished_encounters.get(encounter_id, false):
		return
	if encounter_id == &"e1" and mission.phase == MissionController.Phase.ENCOUNTER_01:
		if not director.has_pending() and director.alive_in(&"e1") == 0:
			_on_encounter_finished(&"e1")
	elif encounter_id == &"e2" and mission.phase == MissionController.Phase.ENCOUNTER_02:
		if not director.has_pending() and director.alive_in(&"e2") == 0:
			_on_encounter_finished(&"e2")
	elif encounter_id == &"final" and mission.phase == MissionController.Phase.FINAL_ENCOUNTER:
		if not director.has_pending() and director.alive_in(&"final") == 0:
			_on_encounter_finished(&"final")


func _activate_emergency() -> void:
	if _emergency_active:
		return
	_emergency_active = true
	_sfx(&"alarm", -6.0, 0.0)
	var emergency = builder.env_fx.get("emergency_lights")
	if emergency is Node3D:
		for light in emergency.get_children():
			if light is Light3D:
				light.light_energy = 1.6
	# Darken fog slightly via world env if present.
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		we.environment.fog_light_color = Color(0.25, 0.05, 0.04)
		we.environment.fog_density = 0.014
		we.environment.ambient_light_energy = 0.28


func _update_emergency_flicker() -> void:
	var emergency = builder.env_fx.get("emergency_lights")
	if emergency is Node3D:
		var pulse := 1.2 + 0.5 * sin(_flicker_time * 7.0)
		for light in emergency.get_children():
			if light is Light3D:
				light.light_energy = pulse
	# Occasional spark SFX.
	if fmod(_flicker_time, 3.7) < 0.05:
		_sfx(&"spark", -8.0, 0.1)


func _unlock_final_approach() -> void:
	## Opens the emergency→final gate. Must run on E2 clear / TRANSITION_02 —
	## trg_final lives inside the chamber, past this door.
	if not builder.doors.has(&"door_final_in"):
		return
	var door: MissionDoor = builder.doors[&"door_final_in"]
	if door.state == MissionDoor.State.LOCKED or door.state == MissionDoor.State.CLOSED:
		door.request_open()
		if OS.is_debug_build():
			print("[Mission] door_final_in unlocked (approach to final chamber)")


func _open_final_doors() -> void:
	for door_id in [&"door_final_in", &"door_final_a", &"door_final_b", &"door_final_c"]:
		if builder.doors.has(door_id):
			builder.doors[door_id].request_open()
	if OS.is_debug_build():
		print("[Mission] final doors unlocked remaining=%d" % director.alive_in(&"final"))


func _safety_door_unlock() -> void:
	if mission.phase >= MissionController.Phase.TRANSITION_01 and builder.doors[&"door_warehouse_out"].state == MissionDoor.State.LOCKED:
		if mission.is_encounter_clear(&"e1") or not _e1_started:
			builder.doors[&"door_warehouse_out"].request_open()
	if mission.phase >= MissionController.Phase.TRANSITION_02 and builder.doors[&"door_lab_out"].state == MissionDoor.State.LOCKED:
		if mission.is_encounter_clear(&"e2") or not _e2_started:
			builder.doors[&"door_lab_out"].request_open()
	# Approach door: after E2/TRANSITION_02 the path into final must be open.
	# (Previously only unlocked on FINAL_ENCOUNTER, but trg_final is past the door.)
	if mission.phase >= MissionController.Phase.TRANSITION_02:
		if builder.doors[&"door_final_in"].state == MissionDoor.State.LOCKED:
			if mission.is_encounter_clear(&"e2") or not _e2_started or mission.phase >= MissionController.Phase.FINAL_ENCOUNTER:
				_unlock_final_approach()
	# Softlock: every living final enemy gone + empty spawn queue must unlock and complete.
	if (
		mission.phase == MissionController.Phase.FINAL_ENCOUNTER
		and not _finished_encounters.get(&"final", false)
		and not director.has_pending()
		and director.alive_in(&"final") == 0
		and _final_started
	):
		_on_encounter_finished(&"final")
	elif mission.phase == MissionController.Phase.MISSION_COMPLETE:
		_open_final_doors()


func _update_hud_counts() -> void:
	var remaining := 0
	match mission.phase:
		MissionController.Phase.ENCOUNTER_01:
			remaining = _living_enemies()
			hud.set_section("WAREHOUSE")
		MissionController.Phase.AMBUSH, MissionController.Phase.ENCOUNTER_02:
			remaining = _living_enemies()
			hud.set_section("LAB")
		MissionController.Phase.FINAL_ENCOUNTER:
			remaining = _living_enemies()
			hud.set_section("FINAL")
		_:
			hud.set_section("PROJECT CLAW")
			remaining = 0
	hud.set_counts(remaining, mission.kills)


func _living_enemies() -> int:
	var n := 0
	for child in enemies.get_children():
		if child is Enemy and child.state != Enemy.State.DEAD:
			n += 1
	if director.has_pending():
		n += 1 # at least show activity
	return n


func _on_player_died() -> void:
	mission.notify_player_died()
	_ui_mode = UiMode.DEATH
	_ui_timer = 0.0
	hud.pause_allowed = false
	_sfx(&"game_over", 0.0, 0.0)
	hud.show_mission_death()


func _restore_now() -> void:
	if _ui_mode != UiMode.DEATH:
		return
	_ui_mode = UiMode.PLAYING
	_ui_timer = 0.0
	Engine.time_scale = 1.0
	hud.clear_banner()
	hud.pause_allowed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	checkpoints.restore()
	# Re-arm encounter flags based on restored phase.
	_sync_flags_to_phase()


func _sync_flags_to_phase() -> void:
	var p := mission.phase
	_e1_started = p > MissionController.Phase.APPROACH
	_ambush_done = p > MissionController.Phase.TRANSITION_01
	_e2_started = p > MissionController.Phase.AMBUSH
	_final_started = p >= MissionController.Phase.FINAL_ENCOUNTER
	_emergency_active = p >= MissionController.Phase.TRANSITION_02
	if _emergency_active:
		_activate_emergency()


func _on_checkpoint_respawn(_data: Dictionary) -> void:
	# After restore, if mid-encounter with no living enemies and empty queue, restart that encounter.
	director.clear_all()
	match mission.phase:
		MissionController.Phase.ENCOUNTER_01:
			_e1_started = false
			_finished_encounters.erase(&"e1")
			_start_encounter_01()
		MissionController.Phase.AMBUSH:
			_ambush_done = false
			_e2_started = false
			_finished_encounters.erase(&"e2")
			_start_ambush_event()
		MissionController.Phase.ENCOUNTER_02:
			_e2_started = false
			_finished_encounters.erase(&"e2")
			_start_encounter_02()
		MissionController.Phase.FINAL_ENCOUNTER:
			_final_started = false
			_finished_encounters.erase(&"final")
			_start_final_encounter()


func _on_mission_complete() -> void:
	_ui_mode = UiMode.COMPLETE
	_ui_timer = 0.0
	hud.pause_allowed = false
	player.controls_enabled = true # brief free look/walk
	_sfx(&"mission_complete", 0.0, 0.0)
	var minutes := int(mission.mission_elapsed) / 60
	var seconds := int(mission.mission_elapsed) % 60
	hud.show_mission_complete(mission.kills, "%d:%02d" % [minutes, seconds])
	await get_tree().create_timer(COMPLETE_HOLD).timeout
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_hit_landed(_pos: Vector3) -> void:
	pass


func _sfx(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var bus := get_node_or_null("/root/Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, volume_db, pitch_jitter)
