class_name Player
extends CharacterBody3D

signal health_changed(health: int, max_health: int)
signal rage_changed(rage: float, raging: bool)
signal hit_chain_changed(count: int)
signal hurt(damage: int)
signal died

enum State { IDLE, RUN, DODGE, ATTACK, HURT, DEAD }

const ANIMATIONS: Array[StringName] = [
	&"idle", &"sprint", &"actions/dodge", &"attack-melee-right", &"reactions/hit", &"die"
]
const HIT_IMPACT := preload("res://scenes/hit_impact.tscn")
## Three light claw swings (RT). Buffering chains into the next step.
const LIGHT_COMBO: Array[Dictionary] = [
	{animation = &"attack-melee-right", limb = 0, time = 1.0, damage = 25, knockback = 2.4, hit_stop = 0.05},
	{animation = &"attack-melee-left", limb = 1, time = 0.9, damage = 25, knockback = 2.6, hit_stop = 0.055},
	{animation = &"attack-melee-right", limb = 0, time = 1.05, damage = 25, knockback = 3.2, hit_stop = 0.06},
]
## Dedicated heavy (RB): slower, bigger knockback and hit-stop.
const HEAVY_ATTACK := {
	animation = &"attack-kick-right", limb = 2, time = 1.35, damage = 45, knockback = 7.5, hit_stop = 0.07
}
const RAGE_MAX := 100.0

@export var move_speed: float = 5.0
@export var acceleration: float = 24.0
@export var deceleration: float = 30.0
@export var turn_speed: float = 12.0
@export var camera_speed: float = 2.4
@export var mouse_sensitivity: float = 0.0025
@export_range(1.0, 20.0) var dodge_speed: float = 11.0
@export_range(0.1, 1.0) var dodge_duration: float = 0.32
@export_range(0.0, 2.0) var dodge_cooldown: float = 0.28
@export_range(0.1, 2.0) var attack_duration: float = 0.5
@export_range(0.0, 1.0) var dodge_iframe_start: float = 0.05
@export_range(0.0, 1.0) var dodge_iframe_end: float = 0.22
@export_range(0.0, 1.0) var attack_active_start: float = 0.5
@export_range(0.0, 1.0) var attack_active_end: float = 0.7
@export_range(0.0, 0.1) var camera_impulse_strength: float = 0.035
@export_range(0.05, 0.3) var camera_impulse_duration: float = 0.16

@export_group("Combo")
## A press after this fraction of a swing queues the next light step.
@export_range(0.0, 1.0) var combo_buffer_start: float = 0.3
## A queued step starts at this fraction, cancelling the current swing's recovery.
@export_range(0.0, 1.0) var combo_chain_point: float = 0.8
@export var aim_assist_range: float = 4.0
@export_range(0.0, 180.0) var aim_assist_angle: float = 70.0
@export_range(0.0, 0.5) var lunge_time: float = 0.12
@export var max_lunge_speed: float = 12.0

@export_group("Vitals")
@export var max_health: int = 100
## Healing factor: regeneration starts after this long without taking damage.
@export var regen_delay: float = 3.0
@export var regen_rate: float = 10.0
@export_range(0.1, 1.0) var hurt_duration: float = 0.3
## Extra invulnerability after a hurt reaction, so a crowd cannot juggle the player.
@export_range(0.0, 2.0) var hurt_grace: float = 0.6
@export var rage_per_hit: float = 6.0
@export var rage_duration: float = 8.0
@export var rage_damage_multiplier: float = 1.5
@export var rage_speed_multiplier: float = 1.3
@export var rage_regen_rate: float = 18.0

var state: State = State.IDLE
var state_time: float = 0.0
var dodge_cooldown_left: float = 0.0
var dodge_direction := Vector3.ZERO
var hit_stop_left: float = 0.0
var camera_impulse_left: float = 0.0
var combo_step: int = 0
var combo_queued: bool = false
var heavy_attack: bool = false
var lunge_velocity := Vector3.ZERO
var knockback_velocity := Vector2.ZERO
var health: float
var rage: float = 0.0
var rage_left: float = 0.0
var since_damage: float = 0.0
var grace_left: float = 0.0
var hit_chain: int = 0
var hit_chain_left: float = 0.0
## The game disables controls on the title and game-over screens.
var controls_enabled: bool = true
var _attack_device: int = -1
var _rumble_device: int = -1
var _impulse_scale: float = 1.0
var _mouse_look := Vector2.ZERO
var _shown_health: int = 0
var _overlay := StandardMaterial3D.new()
var _claw_material := StandardMaterial3D.new()

var is_invulnerable: bool:
	get:
		return state == State.DODGE and state_time >= dodge_iframe_start and state_time < dodge_iframe_end

var raging: bool:
	get:
		return rage_left > 0.0

var is_alive: bool:
	get:
		return state != State.DEAD

@onready var visuals: Node3D = $Visuals
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var animator: AnimationPlayer = $Visuals/Humanoid/AnimationPlayer
@onready var attack_hand: Node3D = $"Visuals/Humanoid/figurine-cube-detailed/root/torso/arm-right"
@onready var limbs: Array[Node3D] = [
	attack_hand,
	$"Visuals/Humanoid/figurine-cube-detailed/root/torso/arm-left",
	$"Visuals/Humanoid/figurine-cube-detailed/root/leg-right",
]
@onready var attack_hitbox: MeleeHitbox = $Visuals/AttackHitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_shown_health = max_health
	# The camera should collide with the arena, but not the player's capsule.
	spring_arm.add_excluded_object(get_rid())
	animator.add_animation_library(&"actions", preload("res://animations/dodge.tres"))
	animator.add_animation_library(&"reactions", preload("res://animations/enemy_reactions.tres"))
	# Advance alongside action timing so hand placement, active frames, and hit-stop agree.
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	attack_hitbox.hit_landed.connect(_on_hit_landed)
	hurtbox.hit_received.connect(_on_hurt)
	_apply_claw_fighter_look()
	animator.play(ANIMATIONS[state])
	print(State.keys()[state])


func _apply_claw_fighter_look() -> void:
	# Original identity: dark tactical body + steel claw blades (not a costume copy).
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.12, 0.13, 0.15)
	body.roughness = 0.85
	body.metallic = 0.05
	_claw_material.albedo_color = Color(0.78, 0.82, 0.88)
	_claw_material.metallic = 0.95
	_claw_material.roughness = 0.28
	_claw_material.emission_enabled = true
	_claw_material.emission = Color(0.35, 0.45, 0.55)
	_claw_material.emission_energy_multiplier = 0.35
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for mesh in $Visuals/Humanoid.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = body
		mesh.material_overlay = _overlay
	_attach_claws(limbs[0])
	_attach_claws(limbs[1])


func _attach_claws(hand: Node3D) -> void:
	var claws := Node3D.new()
	claws.name = "Claws"
	hand.add_child(claws)
	claws.position = Vector3(0.0, -0.28, 0.02)
	for i in 3:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.035, 0.42, 0.02)
		blade.mesh = box
		blade.material_override = _claw_material
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blade.position = Vector3((i - 1) * 0.045, -0.12, 0.0)
		blade.rotation_degrees = Vector3(8.0, 0.0, (i - 1) * 6.0)
		claws.add_child(blade)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_look += event.relative * mouse_sensitivity


func _physics_process(delta: float) -> void:
	var stopped := hit_stop_left > 0.0
	hit_stop_left = maxf(0.0, hit_stop_left - delta)
	if not stopped:
		state_time += delta
	dodge_cooldown_left = maxf(0.0, dodge_cooldown_left - delta)
	_update_vitals(delta)
	# Camera input stays live during every action.
	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	camera_pivot.rotation.y = wrapf(
		camera_pivot.rotation.y - look_input.x * camera_speed * delta - _mouse_look.x, -PI, PI
	)
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x - look_input.y * camera_speed * delta - _mouse_look.y,
		deg_to_rad(-60.0), deg_to_rad(25.0)
	)
	_mouse_look = Vector2.ZERO
	hurtbox.enabled = state != State.DEAD and not is_invulnerable and grace_left <= 0.0
	if stopped:
		# Only this actor's action/pose pauses; physics, gravity, and camera input stay live.
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return

	var can_act := controls_enabled and state != State.DEAD
	var move_input := Vector2.ZERO
	if can_act:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# The pivot only rotates around Y, so camera pitch never tilts movement.
	# Preserve the stick magnitude for slow walking and capped diagonal speed.
	var move_direction := camera_pivot.global_basis * Vector3(move_input.x, 0.0, move_input.y)
	var resume_state := State.RUN if not move_input.is_zero_approx() else State.IDLE

	if state == State.DODGE and state_time >= dodge_duration:
		# End the burst immediately instead of coasting at dodge speed.
		velocity.x = move_direction.x * move_speed
		velocity.z = move_direction.z * move_speed
		_set_state(resume_state)
	elif state == State.ATTACK:
		var swing_time := _attack_time()
		if (
			can_act and not heavy_attack and Input.is_action_just_pressed("attack")
			and combo_step < LIGHT_COMBO.size() - 1 and state_time >= swing_time * combo_buffer_start
		):
			combo_queued = true
		if combo_queued and state_time >= swing_time * combo_chain_point:
			_start_light(combo_step + 1, move_direction)
		elif state_time >= swing_time:
			_set_state(resume_state)
	elif state == State.HURT and state_time >= hurt_duration:
		_set_state(resume_state)

	# Actions are grounded and never queued from free movement. A wins simultaneous presses.
	if can_act and (state == State.IDLE or state == State.RUN) and is_on_floor():
		if Input.is_action_just_pressed("dodge") and dodge_cooldown_left <= 0.0:
			dodge_direction = move_direction.normalized() if not move_input.is_zero_approx() else -visuals.global_basis.z
			dodge_cooldown_left = dodge_duration + dodge_cooldown
			_set_state(State.DODGE)
		elif Input.is_action_just_pressed("attack_heavy"):
			_start_heavy(move_direction)
		elif Input.is_action_just_pressed("attack"):
			_start_light(0, move_direction)
	if can_act and Input.is_action_just_pressed("rage") and rage >= RAGE_MAX and not raging:
		_start_rage()

	var target_velocity := move_direction * move_speed
	var rate := deceleration if move_input.is_zero_approx() else acceleration
	if state == State.ATTACK or state == State.HURT or state == State.DEAD:
		target_velocity = Vector3.ZERO
		rate = deceleration
	var horizontal_velocity := Vector2(velocity.x, velocity.z).move_toward(
		Vector2(target_velocity.x, target_velocity.z), rate * delta
	)
	if state == State.DODGE:
		horizontal_velocity = Vector2(dodge_direction.x, dodge_direction.z) * dodge_speed
	elif state == State.ATTACK and not lunge_velocity.is_zero_approx():
		# The lunge closes the gap to an assisted target, then stops dead to avoid overshoot.
		horizontal_velocity = Vector2(lunge_velocity.x, lunge_velocity.z)
		if state_time >= lunge_time:
			lunge_velocity = Vector3.ZERO
			horizontal_velocity = Vector2.ZERO
	elif state == State.HURT:
		horizontal_velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 14.0 * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	var facing_direction := dodge_direction if state == State.DODGE else move_direction
	var holds_facing := state == State.ATTACK or state == State.HURT or state == State.DEAD
	if not holds_facing and not facing_direction.is_zero_approx():
		var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
		# Rotate only the mesh, leaving the camera free to orbit independently.
		visuals.rotation.y = lerp_angle(
			visuals.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta)
		)

	if state == State.IDLE or state == State.RUN:
		# Actual motion drives locomotion, so pushing a wall does not run in place.
		var ground_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
		var run_threshold := 0.08 if state == State.RUN else 0.15
		_set_state(State.RUN if ground_speed > run_threshold else State.IDLE)
		animator.speed_scale = clampf(ground_speed / move_speed, 0.25, 1.0) if state == State.RUN else 1.0

	animator.advance(delta)
	# Follow the animated limb without inheriting the imported model's 3x scale.
	var move := _current_move()
	attack_hitbox.global_position = limbs[int(move.limb)].to_global(Vector3(0, -0.2, 0))
	var swing := _attack_time()
	attack_hitbox.set_active(
		state == State.ATTACK
		and state_time >= swing * attack_active_start
		and state_time < swing * attack_active_end
	)
	attack_hitbox.check_hits()


## Adds rage outside of a rampage; the game calls this for kills.
func add_rage(amount: float) -> void:
	if raging or state == State.DEAD:
		return
	rage = minf(RAGE_MAX, rage + amount)
	rage_changed.emit(rage, false)


## Session checkpoint revive — restores combat readiness without reloading the scene.
func revive(full_health: bool = true) -> void:
	if full_health:
		health = max_health
	rage_left = 0.0
	grace_left = 0.9
	since_damage = 0.0
	hit_chain = 0
	hit_stop_left = 0.0
	knockback_velocity = Vector2.ZERO
	lunge_velocity = Vector3.ZERO
	combo_queued = false
	heavy_attack = false
	controls_enabled = true
	hurtbox.enabled = true
	hurtbox.collision_layer = 32
	collision_layer = 2
	collision_mask = 1
	velocity = Vector3.ZERO
	_set_state(State.IDLE, true)
	_emit_health()
	rage_changed.emit(rage, false)
	hit_chain_changed.emit(0)


func _current_move() -> Dictionary:
	return HEAVY_ATTACK if heavy_attack else LIGHT_COMBO[combo_step]


func _attack_time() -> float:
	var speed := rage_speed_multiplier if raging else 1.0
	return attack_duration * float(_current_move().time) / speed


func _start_light(step: int, move_direction: Vector3) -> void:
	heavy_attack = false
	combo_step = step
	combo_queued = false
	_configure_hitbox(_current_move())
	_aim_attack(move_direction)
	_set_state(State.ATTACK, true)


func _start_heavy(move_direction: Vector3) -> void:
	heavy_attack = true
	combo_step = 0
	combo_queued = false
	_configure_hitbox(HEAVY_ATTACK)
	_aim_attack(move_direction)
	_set_state(State.ATTACK, true)


func _configure_hitbox(move: Dictionary) -> void:
	var damage_scale := rage_damage_multiplier if raging else 1.0
	attack_hitbox.damage = roundi(float(move.damage) * damage_scale)
	attack_hitbox.knockback = float(move.knockback)
	attack_hitbox.hit_stop_duration = float(move.hit_stop)


## Soft lock: snap the swing toward the best enemy in front and lunge into range.
func _aim_attack(move_direction: Vector3) -> void:
	lunge_velocity = Vector3.ZERO
	var forward := move_direction.normalized() if not move_direction.is_zero_approx() else -visuals.global_basis.z
	forward.y = 0.0
	var best_offset := Vector3.ZERO
	var best_score := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > aim_assist_range or distance < 0.01:
			continue
		var angle := forward.angle_to(offset)
		if angle > deg_to_rad(aim_assist_angle):
			continue
		# Prefer enemies near the stick direction, then the closest.
		var score := distance + angle * 2.0
		if score < best_score:
			best_score = score
			best_offset = offset
	if best_score == INF:
		return
	visuals.rotation.y = atan2(-best_offset.x, -best_offset.z)
	var gap := best_offset.length() - 1.1
	if gap > 0.0 and lunge_time > 0.0:
		lunge_velocity = best_offset.normalized() * minf(gap / lunge_time, max_lunge_speed)


func _start_rage() -> void:
	rage_left = rage_duration
	_kick_camera(1.6)
	_sfx(&"rage", 2.0, 0.0)
	rage_changed.emit(rage, true)


func _update_vitals(delta: float) -> void:
	since_damage += delta
	grace_left = maxf(0.0, grace_left - delta)
	if hit_chain > 0:
		hit_chain_left -= delta
		if hit_chain_left <= 0.0:
			hit_chain = 0
			hit_chain_changed.emit(0)
	if state == State.DEAD:
		return
	if raging:
		rage_left = maxf(0.0, rage_left - delta)
		rage = RAGE_MAX * rage_left / rage_duration
		health += rage_regen_rate * delta
		rage_changed.emit(rage, raging)
	elif since_damage >= regen_delay:
		health += regen_rate * delta
	health = minf(health, max_health)
	_emit_health()


func _emit_health() -> void:
	var shown := ceili(health)
	if shown != _shown_health:
		_shown_health = shown
		health_changed.emit(shown, max_health)


func _set_state(next_state: State, force: bool = false) -> void:
	if state == next_state and not force:
		return
	state = next_state
	state_time = 0.0
	attack_hitbox.set_active(false)
	if state == State.ATTACK:
		attack_hitbox.begin_swing(self)
		_sfx(&"swing", -4.0)
	elif state == State.DODGE:
		_sfx(&"dodge", -3.0)
	elif state != State.ATTACK:
		heavy_attack = false
		combo_queued = false
	animator.speed_scale = 1.0
	var animation: StringName = (
		StringName(_current_move().animation) if state == State.ATTACK else ANIMATIONS[state]
	)
	var length := animator.get_animation(animation).length
	var playback_speed := 1.0
	match state:
		State.DODGE:
			playback_speed = length / dodge_duration
		State.ATTACK:
			playback_speed = length / _attack_time()
		State.HURT:
			playback_speed = length / hurt_duration
		State.DEAD:
			playback_speed = length / 0.6
	var blend := 0.1
	if state == State.DODGE or state == State.ATTACK or state == State.HURT:
		blend = 0.05
	animator.play(animation, blend, playback_speed)
	if force and animator.current_animation == animation:
		# Replaying the same clip (a second hurt) must restart it.
		animator.seek(0.0, true)
	print(State.keys()[state])


func _on_hurt(damage: int, source_position: Vector3, hit_stop: float, knockback: float) -> void:
	if state == State.DEAD:
		return
	health = maxf(0.0, health - damage)
	since_damage = 0.0
	grace_left = hurt_duration + hurt_grace
	combo_queued = false
	heavy_attack = false
	lunge_velocity = Vector3.ZERO
	hit_stop_left = maxf(hit_stop_left, hit_stop)
	_kick_camera(2.4)
	_rumble(0.5, 0.7, 0.2)
	_sfx(&"hurt")
	hurt.emit(damage)
	_emit_health()
	var away := global_position - source_position
	away.y = 0.0
	away = away.normalized()
	if health <= 0.0:
		rage_left = 0.0
		rage_changed.emit(rage, false)
		_set_state(State.DEAD)
		died.emit()
		return
	knockback_velocity = Vector2(away.x, away.z) * knockback
	if not away.is_zero_approx():
		visuals.rotation.y = atan2(away.x, away.z)
	_set_state(State.HURT, true)


func _input(event: InputEvent) -> void:
	# Rumble goes to whichever controller last attacked or dodged.
	if (
		event.is_action_pressed("attack")
		or event.is_action_pressed("attack_heavy")
		or event.is_action_pressed("dodge")
	):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			_attack_device = event.device


func _on_hit_landed(contact_position: Vector3) -> void:
	var finisher := heavy_attack or (not heavy_attack and combo_step == LIGHT_COMBO.size() - 1)
	hit_stop_left = attack_hitbox.hit_stop_duration
	_kick_camera(1.8 if finisher else 1.0)
	var impact := HIT_IMPACT.instantiate()
	impact.size = 1.8 if finisher else 1.0
	get_tree().current_scene.add_child(impact)
	impact.global_position = contact_position
	_sfx(&"heavy_hit" if finisher else &"hit")
	hit_chain += 1
	hit_chain_left = 2.0
	hit_chain_changed.emit(hit_chain)
	add_rage(rage_per_hit)
	if _attack_device >= 0:
		_rumble(0.2 if finisher else 0.16, 0.35 if finisher else 0.24, 0.1 if finisher else 0.09)


func _rumble(weak: float, strong: float, duration: float) -> void:
	# Unsupported/disconnected controllers simply receive no vibration request.
	if _attack_device in Input.get_connected_joypads() and Input.has_joy_vibration(_attack_device):
		_rumble_device = _attack_device
		Input.start_joy_vibration(_rumble_device, weak, strong, duration)


func _kick_camera(scale: float) -> void:
	camera_impulse_left = camera_impulse_duration
	_impulse_scale = scale


func _sfx(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	# Resolve by path so scripts compile even when preloaded before autoloads (tests).
	var tree := get_tree()
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, volume_db, pitch_jitter)


func _process(delta: float) -> void:
	camera_impulse_left = maxf(0.0, camera_impulse_left - delta)
	var elapsed := camera_impulse_duration - camera_impulse_left
	var strength := camera_impulse_strength * _impulse_scale * pow(camera_impulse_left / camera_impulse_duration, 2.0)
	# Small lens offsets leave orbit angles and the spring arm's position untouched.
	camera.h_offset = sin(elapsed * 90.0) * strength
	camera.v_offset = cos(elapsed * 70.0) * strength * 0.65
	if raging:
		_overlay.albedo_color = Color(1.0, 0.12, 0.05, 0.28 + 0.1 * sin(Time.get_ticks_msec() * 0.02))
	elif grace_left > 0.0 and state != State.DEAD:
		_overlay.albedo_color = Color(1, 1, 1, 0.45 if fmod(grace_left, 0.12) > 0.06 else 0.0)
	else:
		_overlay.albedo_color = Color(1, 1, 1, 0)


func _exit_tree() -> void:
	if _rumble_device in Input.get_connected_joypads():
		Input.stop_joy_vibration(_rumble_device)
