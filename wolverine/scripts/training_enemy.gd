extends CharacterBody3D

enum State { IDLE, STAGGER, DEAD, GRABBED, THROWN }

@export var max_health: int = 100
@export var knockback_deceleration: float = 14.0
@export var stagger_duration: float = 0.24
@export var disappear_delay: float = 1.1
@export var stagger_threshold: float = 40.0
@export var is_heavy: bool = false
@export var grab_resist_unless_staggered: bool = false

var health: int
var state: State = State.IDLE
var state_time: float = 0.0
var hit_stop_left: float = 0.0
var knockback_velocity := Vector2.ZERO
var stagger_build: float = 0.0
var _throw_velocity := Vector3.ZERO
var _wall_bonus_used: bool = false

var is_alive: bool:
	get:
		return state != State.DEAD

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var visuals: Node3D = $Visuals
@onready var animator: AnimationPlayer = $Visuals/Humanoid/AnimationPlayer


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	hurtbox.hit_received.connect(_receive_hit)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.add_animation_library(&"reactions", preload("res://animations/enemy_reactions.tres"))
	animator.play("idle")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.34, 0.12)
	material.roughness = 1.0
	for mesh in $Visuals/Humanoid.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material


func can_be_grabbed() -> bool:
	if state == State.DEAD or state == State.GRABBED:
		return false
	if grab_resist_unless_staggered or is_heavy:
		return state == State.STAGGER or stagger_build >= stagger_threshold * 0.85
	return true


func is_staggered() -> bool:
	return state == State.STAGGER


func is_finisher_ready() -> bool:
	return state != State.DEAD and float(health) / float(max_health) <= 0.22


func enter_grabbed(_grabber: Node3D) -> void:
	state = State.GRABBED
	state_time = 0.0
	knockback_velocity = Vector2.ZERO
	animator.play(&"reactions/hit", 0.05, 0.1)


func exit_grabbed(_killed: bool) -> void:
	if state == State.DEAD:
		return
	if health <= 0:
		_die(Vector2.ZERO)
	else:
		state = State.STAGGER
		state_time = 0.0


func receive_throw(velocity_xz: Vector3, _thrower: Node3D) -> void:
	_wall_bonus_used = false
	_throw_velocity = velocity_xz
	_throw_velocity.y = 2.5
	state = State.THROWN
	state_time = 0.0


func _physics_process(delta: float) -> void:
	var stopped := hit_stop_left > 0.0 and state != State.THROWN
	hit_stop_left = maxf(0.0, hit_stop_left - delta)
	if not stopped:
		state_time += delta
		if state == State.STAGGER and state_time >= stagger_duration:
			state = State.IDLE
			animator.play("idle", 0.08)
		elif state == State.DEAD and state_time >= disappear_delay:
			queue_free()
			return
		elif state == State.THROWN:
			if state_time >= 0.85 or (is_on_floor() and state_time > 0.25 and _throw_velocity.length() < 2.0):
				if health <= 0:
					_die(Vector2(_throw_velocity.x, _throw_velocity.z))
				else:
					state = State.STAGGER
					state_time = 0.0
			_check_wall()
		animator.advance(delta)
	var horizontal := Vector2.ZERO if stopped else knockback_velocity
	if state == State.THROWN:
		horizontal = Vector2(_throw_velocity.x, _throw_velocity.z)
		velocity.y = _throw_velocity.y
		_throw_velocity.y += get_gravity().y * delta
		_throw_velocity.x = move_toward(_throw_velocity.x, 0.0, 8.0 * delta)
		_throw_velocity.z = move_toward(_throw_velocity.z, 0.0, 8.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if state != State.THROWN and not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if not stopped and state != State.THROWN:
		knockback_velocity = Vector2(velocity.x, velocity.z).move_toward(
			Vector2.ZERO, knockback_deceleration * delta
		)


func _check_wall() -> void:
	if _wall_bonus_used or state != State.THROWN:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is StaticBody3D:
			_wall_bonus_used = true
			health = maxi(0, health - 22)
			_throw_velocity = Vector3.ZERO
			if health <= 0:
				_die(Vector2.ZERO)
			else:
				state = State.STAGGER
				state_time = 0.0
			return


func _receive_hit(event: HitEvent) -> void:
	if state == State.DEAD:
		return
	health = maxi(0, health - event.damage)
	stagger_build += event.stagger_bonus + float(event.damage) * 0.35
	print("HIT: %d damage" % event.damage)
	print("ENEMY HP: %d/%d" % [health, max_health])
	hit_stop_left = maxf(hit_stop_left, event.hit_stop)
	if health == 0:
		_die(Vector2(event.direction.x, event.direction.z) * event.knockback)
		return
	if state == State.STAGGER:
		return
	if state == State.GRABBED:
		return
	state = State.STAGGER
	state_time = 0.0
	var away: Vector3 = event.direction
	if away.is_zero_approx():
		away = global_position - event.source_position
		away.y = 0.0
		away = away.normalized()
	knockback_velocity = Vector2(away.x, away.z) * event.knockback
	if not away.is_zero_approx():
		visuals.rotation.y = atan2(away.x, away.z)
	animator.play("reactions/hit", 0.03, 0.24 / stagger_duration)


func _die(push: Vector2) -> void:
	state = State.DEAD
	state_time = 0.0
	remove_from_group("enemies")
	hurtbox.disable()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	knockback_velocity = push
	animator.play("die", 0.04, animator.get_animation("die").length / 0.55)
	print("ENEMY DEAD")
