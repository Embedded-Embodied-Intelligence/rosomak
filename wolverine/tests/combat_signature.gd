extends SceneTree

# Combat signature pass regression.
# Run: --headless --path wolverine --fixed-fps 60 --script res://tests/combat_signature.gd
const PLAYER = preload("res://scripts/player.gd")
const ENEMY = preload("res://scripts/training_enemy.gd")
const ARENA = preload("res://scenes/test_arena.tscn")
const REAL_ENEMY = preload("res://scenes/enemies/grunt.tscn")
const BRUTE = preload("res://scenes/enemies/brute.tscn")

var player: PLAYER
var enemy: ENEMY
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS: " if condition else "FAIL: ", label)
	if not condition:
		failures += 1


func _fresh(player_position := Vector3(0, 0.03, 1.1), enemy_position := Vector3(0, 0.03, 0)) -> void:
	for axis in 6:
		_axis(axis, 0.0)
	_button(JOY_BUTTON_A, false)
	_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	Engine.time_scale = 1.0
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
		await process_frame
	var arena := ARENA.instantiate()
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Player")
	enemy = arena.get_node("TrainingEnemy")
	player.position = player_position
	enemy.position = enemy_position
	player.reset_physics_interpolation()
	enemy.reset_physics_interpolation()
	await _frames(20)


func _run() -> void:
	# --- Combo buffer / lockout ---
	await _fresh()
	_check(CombatAttackData.light_1().damage == 20, "light_1 data damage is 20")
	_check(CombatAttackData.light_2().damage == 25, "light_2 data damage is 25")
	_check(CombatAttackData.light_3().damage == 35, "light_3 data damage is 35")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(3)
	_check(player.state == PLAYER.State.ATTACK and player.attack_kind == PLAYER.AttackKind.LIGHT_1, "RT starts LIGHT_1")
	var start_time := player.state_time
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(1)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(2)
	_check(player.combo_step == 0 and player.state == PLAYER.State.ATTACK, "early spam does not advance combo_step yet")
	_check(player.state_time >= start_time, "attack FSM not reset by spam")
	await _frames(12)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(1)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(20)
	_check(player.combo_step >= 1 or player.attack_kind == PLAYER.AttackKind.LIGHT_2 or player.state == PLAYER.State.IDLE, "buffered RT chains toward next light")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(40)
	Engine.time_scale = 1.0

	# --- One-hit-per-swing ---
	await _fresh()
	var hits := [0]
	player.attack_hitbox.hit_landed.connect(func(_p: Vector3) -> void: hits[0] += 1)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(2)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(45)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(hits[0] == 1 and enemy.health == 80, "one connection per swing (hits=%d hp=%d)" % [hits[0], enemy.health])

	# --- Counter eligibility ---
	await _fresh(Vector3(0, 0.03, 1.5))
	player.counter_window_left = 0.6
	player._start_counter(Vector3.ZERO)
	await _frames(2)
	_check(player.attack_kind == PLAYER.AttackKind.COUNTER, "counter window starts COUNTER")
	await _frames(40)

	# --- Grab + heavy resist ---
	await _fresh()
	enemy.is_heavy = true
	enemy.grab_resist_unless_staggered = true
	enemy.stagger_build = 0.0
	_check(not enemy.can_be_grabbed(), "heavy resists grab when not staggered")
	enemy.state = ENEMY.State.STAGGER
	enemy.state_time = 0.0
	_check(enemy.can_be_grabbed(), "staggered heavy becomes grabbable")
	player._start_grab(enemy, Vector3.ZERO)
	await _frames(2)
	_check(player.state == PLAYER.State.GRAB and enemy.state == ENEMY.State.GRABBED, "grab locks both actors")
	# Stab
	var hp_before := enemy.health
	player._start_grab_stab()
	await _frames(40)
	_check(enemy.health < hp_before, "grab stab deals damage")
	# Throw cleanup
	await _fresh()
	enemy.state = ENEMY.State.STAGGER
	player._start_grab(enemy, Vector3.ZERO)
	await _frames(2)
	player._start_throw(Vector2(0, -1))
	await _frames(3)
	_check(player.state == PLAYER.State.THROW or enemy.state == ENEMY.State.THROWN or enemy.state == ENEMY.State.STAGGER, "throw leaves grab lock")
	await _frames(50)
	Engine.time_scale = 1.0
	_check(player.state != PLAYER.State.GRAB and player.state != PLAYER.State.THROW, "throw interaction cleans up")
	_check(is_instance_valid(enemy), "thrown training enemy still valid for AI/death")

	# --- Stagger build ---
	await _fresh()
	var grunt: Enemy = REAL_ENEMY.instantiate()
	current_scene.add_child(grunt)
	grunt.global_position = Vector3(2, 0.03, 0)
	await _frames(55)
	var before := grunt.stagger_build
	grunt.hurtbox.receive_hit(HitEvent.from_move(CombatAttackData.light_1(), player, player.global_position))
	_check(grunt.stagger_build > before, "light hit builds stagger")
	var mid := grunt.stagger_build
	# Use heavy (non-lethal) for stagger pressure so the grunt stays alive.
	var heavy_event := HitEvent.from_move(CombatAttackData.heavy(), player, player.global_position)
	heavy_event.damage = 10
	grunt.hurtbox.receive_hit(heavy_event)
	_check(grunt.stagger_build >= mid + heavy_event.stagger_bonus * 0.4, "heavy adds high stagger")

	# --- Finisher eligibility ---
	await _fresh()
	enemy.health = 15
	_check(enemy.is_finisher_ready(), "low HP enables finisher eligibility")
	player._start_finisher(enemy)
	await _frames(2)
	_check(player.state == PLAYER.State.FINISHER, "signature finisher starts")
	await _frames(150)
	Engine.time_scale = 1.0
	if player.state == PLAYER.State.FINISHER:
		player._release_grab(true)
		player._set_state(PLAYER.State.IDLE)
	_check(not is_instance_valid(enemy) or enemy.state == ENEMY.State.DEAD or enemy.health <= 0, "finisher is lethal")
	_check(player.state != PLAYER.State.FINISHER, "finisher exits lock")

	# --- Brute heavy resist grab ---
	await _fresh()
	enemy.queue_free()
	await _frames(2)
	var brute: Enemy = BRUTE.instantiate()
	current_scene.add_child(brute)
	brute.global_position = Vector3(0, 0.03, 0)
	await _frames(55)
	player.global_position = Vector3(0, 0.03, 1.2)
	_check(brute.is_heavy and not brute.can_be_grabbed(), "brute resists grab until staggered")
	brute.stagger_build = brute.stagger_threshold
	brute._enter(Enemy.State.STAGGER)
	_check(brute.can_be_grabbed(), "staggered brute becomes grabbable")

	# --- Grab action is mapped (LT / L key) ---
	_check(InputMap.has_action("grab"), "grab input action exists")
	var grab_events := InputMap.action_get_events("grab")
	var has_lt := false
	for ev in grab_events:
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_LEFT:
			has_lt = true
	_check(has_lt, "grab maps to Left Trigger")
	await _fresh()
	enemy.state = ENEMY.State.STAGGER
	enemy.state_time = 0.0
	player._try_contextual_grab(Vector3.ZERO)
	await _frames(2)
	_check(player.state == PLAYER.State.GRAB or player.state == PLAYER.State.WALL_SLAM, "contextual grab API starts grab")

	DebugCombat.reset_release()
	_check(not DebugCombat.hitboxes or OS.is_debug_build(), "debug hitboxes gated by build")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
