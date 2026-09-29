extends SceneTree

# Run with --headless --path wolverine --fixed-fps 60 --script res://tests/combat_smoke.gd.
# Omit --headless and append -- --capture to save native screenshots in /tmp.
const PLAYER = preload("res://scripts/player.gd")
const ENEMY = preload("res://scripts/training_enemy.gd")
const ARENA = preload("res://scenes/test_arena.tscn")

var player: PLAYER
var enemy: ENEMY
var landed: int = 0
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


func _dodge(pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_A
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
	_dodge(false)
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
	landed = 0
	player.attack_hitbox.hit_landed.connect(func(_point: Vector3) -> void: landed += 1)
	await _frames(30)


func _swing() -> void:
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(2)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(42)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(2)


func _wait_for_hit() -> void:
	for i in 30:
		if landed > 0:
			return
		await _frames(1)


func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var path := "/tmp/rosomak-m3-" + label + ".png"
		root.get_texture().get_image().save_png(path)
		print("SCREENSHOT: ", path)


func _run() -> void:
	await _fresh(Vector3(0, 0.03, 3))
	_check(enemy.health == 100 and enemy.is_on_floor(), "training enemy starts stationary with 100 HP on floor")
	_check(player.collision_layer == 2 and enemy.collision_layer == 4 and enemy.hurtbox.collision_layer == 8 and player.attack_hitbox.collision_mask == 8, "physical bodies and hurtboxes use separate layers")
	await _capture("arena")
	await _swing()
	_check(enemy.health == 100 and landed == 0, "out-of-range attack misses")
	_check(player.hit_stop_left == 0.0 and player.camera_impulse_left == 0.0 and current_scene.find_children("HitImpact*", "Node3D", false, false).is_empty(), "miss produces no stop, impulse, or impact")
	_check(player._rumble_device == -1, "miss never requests rumble")

	await _fresh()
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(10)
	_check(enemy.health == 100 and not player.attack_hitbox.active, "windup cannot damage an overlapping enemy")
	await _wait_for_hit()
	_check(landed == 1 and enemy.health == 75, "first connection deals exactly 25 HP once")
	_check(player.state_time >= 0.25 and player.state_time < 0.35, "damage occurs only in the active window")
	_check(enemy.state == ENEMY.State.STAGGER and enemy.animator.current_animation == "reactions/hit", "hit starts stagger animation")
	_check(enemy.knockback_velocity.y < 0.0 and absf(enemy.knockback_velocity.x) < 0.01, "knockback points away from player")
	_check(player.hit_stop_left > 0.0 and enemy.hit_stop_left > 0.0 and player.camera_impulse_left > 0.0, "confirmed hit triggers local stop and camera impulse")
	_check(not current_scene.find_children("HitImpact*", "Node3D", false, false).is_empty(), "confirmed hit spawns cheap contact flash")
	var stopped_time := player.state_time
	var stopped_pose := player.animator.current_animation_position
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(1)
	_check(is_equal_approx(player.state_time, stopped_time) and is_equal_approx(player.animator.current_animation_position, stopped_pose), "local hit-stop holds action timing and pose")
	_check(player.camera_pivot.rotation.y < 0.0 and not paused and Engine.time_scale == 1.0, "camera and engine continue during hit-stop")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _capture("hit")
	await _frames(8)
	await _capture("recoil")
	await _frames(24)
	_check(enemy.health == 75 and landed == 1, "persistent overlap never repeats damage within one swing")
	_check(enemy.position.z < -0.05 and enemy.position.z > -0.5 and enemy.is_on_floor(), "knockback is small and floor collision stays stable")
	_check(player.state == PLAYER.State.IDLE and not player.attack_hitbox.active, "attack recovers and disables hitbox")
	_check(is_zero_approx(player.camera.h_offset) and is_zero_approx(player.camera.v_offset), "camera impulse decays with no residual offset")
	_check(current_scene.find_children("HitImpact*", "Node3D", false, false).is_empty(), "impact cleans itself up")
	for hit_number in range(2, 5):
		player.position = enemy.position + Vector3(0, 0.02, 1.1)
		player.reset_physics_interpolation()
		await _swing()
		_check(enemy.health == 100 - hit_number * 25 and landed == hit_number, "successful hit %d loses exactly 25 HP" % hit_number)
	_check(enemy.state == ENEMY.State.DEAD and not enemy.hurtbox.enabled and enemy.hurtbox.collision_layer == 0, "four hits enter DEAD and disable hurtbox")
	_check(not enemy.hurtbox.receive_hit(25, player.position, 0.05), "dead hurtbox immediately refuses damage")
	await _capture("death")
	await _swing()
	_check(landed == 4 and player.camera_impulse_left == 0.0, "swinging at corpse produces no new hit or camera feedback")
	await _frames(45)
	_check(not is_instance_valid(enemy), "death removes enemy after a short delay")

	await _fresh(Vector3(0, 0.03, -1.1))
	await _swing()
	_check(enemy.health == 100 and landed == 0, "enemy behind the player is not hit")
	await _fresh(Vector3(-1.1, 0.03, 0))
	player.visuals.rotation.y = -PI / 2.0
	await _swing()
	_check(enemy.health == 75 and enemy.position.x > 0.0, "hand hitbox and knockback follow rotated facing")

	await _fresh(Vector3(0, 0.03, 3))
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(23)
	player.position = Vector3(0, 0.01, 1.1)
	player.reset_physics_interpolation()
	await _frames(15)
	_check(enemy.health == 100 and landed == 0, "entering melee range during recovery cannot deal damage")

	await _fresh(Vector3(-1.1, 0.03, 0))
	player.visuals.rotation.y = -PI / 2.0
	var wall := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.08, 2, 2)
	shape_node.shape = shape
	wall.add_child(shape_node)
	current_scene.add_child(wall)
	wall.position = Vector3(-0.55, 1, 0)
	await _frames(3)
	await _swing()
	_check(enemy.health == 100 and landed == 0, "world geometry prevents hits through a thin wall")

	await _fresh(Vector3(0, 0.03, -10.45), Vector3(0, 0.03, -11.55))
	for i in 3:
		await _swing()
	_check(enemy.health == 25 and enemy.position.z >= -11.61 and enemy.is_on_floor(), "repeated knockback against wall remains stable")
	_check(enemy.knockback_velocity.length() < 0.01, "wall does not accumulate knockback velocity")

	await _fresh()
	enemy.hurtbox.receive_hit(25, Vector3(0, 0, 1), 0.05)
	await _frames(5)
	var prior_velocity := enemy.knockback_velocity
	var prior_time := enemy.state_time
	enemy.hurtbox.receive_hit(25, Vector3(1, 0, 0), 0.05)
	_check(enemy.health == 50 and enemy.knockback_velocity == prior_velocity and enemy.state_time == prior_time, "damage during stagger cannot stack or restart the reaction")

	await _fresh(Vector3(0, 0.03, 4))
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames(20)
	_check(player.state == PLAYER.State.RUN and player.velocity.x > 4.9, "Milestone 2 movement still reaches full speed")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(15)
	_dodge(true)
	await _frames(1)
	_check(player.state == PLAYER.State.DODGE and player.velocity.x > 10.0, "neutral-stick A dodges toward character facing")
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _frames(5)
	_check(player.camera_pivot.rotation.y < -0.1 and player.is_invulnerable, "dodge retains camera control and iframe hook")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(40)
	_check(player.state == PLAYER.State.IDLE and not player.attack_hitbox.active, "holding A does not repeat dodge or enable attacks")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
