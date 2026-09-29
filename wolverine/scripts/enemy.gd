class_name Enemy
extends CharacterBody3D

## A melee brawler: chase, telegraphed windup, strike, recover. Variants (grunt, runner,
## brute) are inherited scenes that only override the exported numbers below.

signal died(enemy: Enemy)

enum State { SPAWN, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD, CHEER }

const HEALTH_BAR_SHADER := preload("res://shaders/health_bar.gdshader")
const SPAWN_TIME := 0.7
const CORPSE_TIME := 1.4

## Enemies share a few attack slots, so a crowd takes turns instead of stacking hits.
## Static, so the game resets it when a run starts.
static var max_attackers: int = 2
static var attackers: int = 0

@export_group("Body")
@export var max_health: int = 60
@export var body_scale: float = 1.0
@export var body_color := Color(0.85, 0.34, 0.12)
@export var move_speed: float = 3.0
@export var move_animation: StringName = &"walk"
## Speed at which the move animation looks natural at playback speed 1.
@export var move_animation_speed: float = 2.5
@export var turn_speed: float = 10.0
## Hits dealing less damage than this only flinch the enemy instead of staggering it.
@export var poise: int = 0
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0
@export var stagger_duration: float = 0.35

@export_group("Attack")
@export var attack_range: float = 1.5
@export var attack_damage: int = 12
@export var attack_knockback: float = 4.0
@export var attack_animation: StringName = &"attack-melee-right"
@export var attack_limb: StringName = &"arm-right"
@export var windup_time: float = 0.55
@export var strike_time: float = 0.3
@export var recover_time: float = 0.55
@export var lunge_speed: float = 3.5
@export var cooldown_range := Vector2(0.5, 1.4)

var state: State = State.SPAWN
var state_time: float = 0.0
var health: int
var hit_stop_left: float = 0.0
var knockback_velocity := Vector2.ZERO
var attack_cooldown: float = 0.0
var target: Node3D
var _has_slot: bool = false
var _strafe_sign: float = 1.0
var _flash: float = 0.0
var _overlay := StandardMaterial3D.new()
var _bar_material := ShaderMaterial.new()
var _bar: MeshInstance3D

@onready var visuals: Node3D = $Visuals
@onready var animator: AnimationPlayer = $Visuals/Humanoid/AnimationPlayer
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: MeleeHitbox = $AttackHitbox
@onready var limb: Node3D = $Visuals/Humanoid.find_child(attack_limb, true, false)


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	target = get_tree().get_first_node_in_group("player")
	hurtbox.enabled = false
	hurtbox.hit_received.connect(_receive_hit)
	attack_hitbox.damage = attack_damage
	attack_hitbox.knockback = attack_knockback
	attack_hitbox.hit_stop_duration = 0.06
	_apply_body_scale()
	_setup_materials()
	_setup_health_bar()

	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.add_animation_library(&"reactions", preload("res://animations/enemy_reactions.tres"))
	# Only enemies use these clips, so looping the shared imported resources is safe.
	animator.get_animation(&"walk").loop_mode = Animation.LOOP_LINEAR
	animator.get_animation(&"emote-yes").loop_mode = Animation.LOOP_LINEAR
	animator.play(&"idle")
	visuals.scale = Vector3.ONE * body_scale * 0.2
	_face(_to_target(), 1.0)


func _apply_body_scale() -> void:
	# Scene sub-resources are shared by every instance, so resize private copies.
	var body := ($CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	body.radius *= body_scale
	body.height *= body_scale
	$CollisionShape3D.shape = body
	$CollisionShape3D.position.y *= body_scale
	var hurt := ($Hurtbox/CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	hurt.radius *= body_scale
	hurt.height *= body_scale
	$Hurtbox/CollisionShape3D.shape = hurt
	hurtbox.position.y *= body_scale
	var reach := ($AttackHitbox/CollisionShape3D.shape as SphereShape3D).duplicate() as SphereShape3D
	reach.radius *= body_scale
	$AttackHitbox/CollisionShape3D.shape = reach


func _setup_materials() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 1.0
	# The overlay carries spawn, hit-flash, and windup telegraph colors.
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for mesh in $Visuals/Humanoid.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.material_overlay = _overlay


func _setup_health_bar() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.1) * maxf(1.0, body_scale)
	_bar_material.shader = HEALTH_BAR_SHADER
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = _bar_material
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.position.y = 2.15 * body_scale
	_bar.visible = false
	add_child(_bar)


func _physics_process(delta: float) -> void:
	var stopped := hit_stop_left > 0.0
	hit_stop_left = maxf(0.0, hit_stop_left - delta)
	var desired := Vector3.ZERO
	if not stopped:
		state_time += delta
		attack_cooldown = maxf(0.0, attack_cooldown - delta)
		desired = _think(delta)
	# Local hit-stop holds the reaction and horizontal motion. Physics/gravity continue.
	var horizontal := Vector2.ZERO if stopped else Vector2(desired.x, desired.z) + knockback_velocity
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if not stopped:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 12.0 * delta)
		if state == State.CHASE:
			var ground_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
			animator.speed_scale = clampf(ground_speed / move_animation_speed, 0.4, 2.0)
		animator.advance(delta)

	attack_hitbox.global_position = limb.to_global(Vector3(0, -0.2, 0))
	attack_hitbox.set_active(
		state == State.STRIKE and state_time >= strike_time * 0.1 and state_time < strike_time * 0.65
	)
	attack_hitbox.check_hits()
	_update_overlay(delta)


func _think(delta: float) -> Vector3:
	var to_target := _to_target()
	var distance := to_target.length()
	match state:
		State.SPAWN:
			var progress := clampf(state_time / SPAWN_TIME, 0.0, 1.0)
			visuals.scale = Vector3.ONE * body_scale * lerpf(0.2, 1.0, ease(progress, 0.4))
			_face(to_target, delta)
			if progress >= 1.0:
				hurtbox.enabled = true
				_enter(State.CHASE)
		State.CHASE:
			if not _target_alive():
				_enter(State.CHEER)
				return Vector3.ZERO
			if distance <= attack_range and attack_cooldown <= 0.0 and _claim_slot():
				_enter(State.WINDUP)
				return Vector3.ZERO
			var direction := to_target / distance if distance > 0.01 else Vector3.ZERO
			var speed := move_speed
			if distance < attack_range + 1.4:
				# Waiting for a slot or cooldown: circle at a readable distance instead of crowding.
				var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_sign
				var spacing := clampf(distance - (attack_range + 0.7), -1.0, 1.0)
				direction = tangent * 0.8 + direction * spacing
				speed *= 0.5
			direction += _separation()
			_face(to_target, delta)
			return direction.limit_length(1.0) * speed
		State.WINDUP:
			_face(to_target, delta)
			if state_time >= windup_time:
				_enter(State.STRIKE)
		State.STRIKE:
			if state_time >= strike_time:
				_enter(State.RECOVER)
			elif state_time < 0.12 and distance > 1.0:
				return _forward() * lunge_speed
		State.RECOVER:
			if state_time >= recover_time:
				_enter(State.CHASE)
		State.STAGGER:
			if state_time >= stagger_duration:
				_enter(State.CHASE)
		State.DEAD:
			if state_time >= CORPSE_TIME:
				queue_free()
			elif state_time > CORPSE_TIME - 0.45:
				var shrink := (CORPSE_TIME - state_time) / 0.45
				visuals.scale = Vector3.ONE * body_scale * shrink
		State.CHEER:
			if _target_alive():
				_enter(State.CHASE)
	return Vector3.ZERO


func _enter(next_state: State) -> void:
	if next_state != State.WINDUP and next_state != State.STRIKE:
		_release_slot()
	state = next_state
	state_time = 0.0
	animator.speed_scale = 1.0
	attack_hitbox.set_active(false)
	match state:
		State.CHASE:
			animator.play(move_animation, 0.15)
		State.WINDUP:
			# The first 40% of the swing stretches over the windup as a slow, readable draw.
			animator.play(attack_animation, 0.1)
			animator.speed_scale = animator.get_animation(attack_animation).length * 0.4 / windup_time
			_sfx(&"telegraph", -8.0)
		State.STRIKE:
			attack_hitbox.begin_swing(self)
			animator.speed_scale = animator.get_animation(attack_animation).length * 0.6 / strike_time
			_sfx(&"swing", -9.0)
		State.RECOVER:
			attack_cooldown = randf_range(cooldown_range.x, cooldown_range.y)
			animator.play(&"idle", 0.2)
		State.STAGGER:
			animator.play(&"reactions/hit", 0.03, 0.24 / stagger_duration)
			animator.seek(0.0, true)
		State.CHEER:
			animator.play(&"emote-yes", 0.3)


func _receive_hit(damage: int, source_position: Vector3, hit_stop: float, knockback: float) -> void:
	if state == State.DEAD or state == State.SPAWN:
		return
	health = maxi(0, health - damage)
	_flash = 1.0
	_bar.visible = true
	_bar_material.set_shader_parameter(&"fill", float(health) / max_health)
	hit_stop_left = maxf(hit_stop_left, hit_stop)
	var away := global_position - source_position
	away.y = 0.0
	away = away.normalized()
	var push := Vector2(away.x, away.z) * knockback * (1.0 - knockback_resistance)
	if health == 0:
		_die(push)
		return
	if damage < poise:
		# Armored: the hit registers, but the current action carries on.
		knockback_velocity += push * 0.3
		return
	knockback_velocity = push
	if not away.is_zero_approx():
		visuals.rotation.y = atan2(away.x, away.z)
	# Every hit restarts the stagger, so a full combo keeps the enemy locked.
	_enter(State.STAGGER)


func _die(push: Vector2) -> void:
	_release_slot()
	state = State.DEAD
	state_time = 0.0
	remove_from_group("enemies")
	hurtbox.disable()
	attack_hitbox.set_active(false)
	# The corpse no longer blocks anyone; its own floor collision remains.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	knockback_velocity = push * 1.6
	_bar.visible = false
	animator.speed_scale = 1.0
	animator.play(&"die", 0.04, animator.get_animation(&"die").length / 0.55)
	_sfx(&"enemy_die", -2.0)
	died.emit(self)


func _sfx(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, volume_db, pitch_jitter)


func _update_overlay(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 8.0)
	var color := Color(1, 1, 1, 0)
	if state == State.SPAWN:
		color = Color(1.0, 0.5, 0.2, 1.0 - state_time / SPAWN_TIME)
	elif state == State.WINDUP:
		# Pulses faster as the strike approaches: this is the cue to dodge.
		var progress := state_time / windup_time
		var pulse := 0.5 + 0.5 * sin(state_time * lerpf(18.0, 40.0, progress))
		color = Color(1.0, 0.85, 0.2, lerpf(0.15, 0.65, progress) * pulse + 0.1)
	if _flash > 0.0:
		color = Color(1, 1, 1, _flash * 0.8)
	_overlay.albedo_color = color


func _to_target() -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset


func _target_alive() -> bool:
	return is_instance_valid(target) and target.get(&"is_alive") == true


func _forward() -> Vector3:
	var forward := -visuals.global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _face(direction: Vector3, delta: float) -> void:
	if direction.is_zero_approx():
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.001 and distance < 1.6:
			push += offset / distance * (1.6 - distance) / 1.6
	return push


func _claim_slot() -> bool:
	if _has_slot:
		return true
	if attackers >= max_attackers:
		return false
	attackers += 1
	_has_slot = true
	return true


func _release_slot() -> void:
	if _has_slot:
		attackers -= 1
		_has_slot = false


func _exit_tree() -> void:
	_release_slot()
