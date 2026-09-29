extends CharacterBody3D

enum State { IDLE, STAGGER, DEAD }

@export var max_health: int = 100
@export var knockback_deceleration: float = 14.0
@export var stagger_duration: float = 0.24
@export var disappear_delay: float = 1.1

var health: int
var state: State = State.IDLE
var state_time: float = 0.0
var hit_stop_left: float = 0.0
var knockback_velocity := Vector2.ZERO

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var visuals: Node3D = $Visuals
@onready var animator: AnimationPlayer = $Visuals/Humanoid/AnimationPlayer


func _ready() -> void:
	health = max_health
	hurtbox.hit_received.connect(_receive_hit)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.add_animation_library(&"reactions", preload("res://animations/enemy_reactions.tres"))
	animator.play("idle")
	# Share one simple material across the existing six low-poly mesh parts.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.34, 0.12)
	material.roughness = 1.0
	for mesh in $Visuals/Humanoid.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material


func _physics_process(delta: float) -> void:
	var stopped := hit_stop_left > 0.0
	hit_stop_left = maxf(0.0, hit_stop_left - delta)
	if not stopped:
		state_time += delta
		if state == State.STAGGER and state_time >= stagger_duration:
			state = State.IDLE
			animator.play("idle", 0.08)
		elif state == State.DEAD and state_time >= disappear_delay:
			queue_free()
			return
		animator.advance(delta)
	# Local hit-stop holds the reaction and horizontal burst. Physics/gravity continue.
	var horizontal := Vector2.ZERO if stopped else knockback_velocity
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if not stopped:
		# Keep collision's slide result, so a wall cannot accumulate knockback velocity.
		knockback_velocity = Vector2(velocity.x, velocity.z).move_toward(
			Vector2.ZERO, knockback_deceleration * delta
		)


func _receive_hit(damage: int, source_position: Vector3, hit_stop: float, knockback: float) -> void:
	if state == State.DEAD:
		return
	health = maxi(0, health - damage)
	print("HIT: %d damage" % damage)
	print("ENEMY HP: %d/%d" % [health, max_health])
	hit_stop_left = maxf(hit_stop_left, hit_stop)
	if health == 0:
		state = State.DEAD
		state_time = 0.0
		hurtbox.disable()
		# The corpse no longer blocks the player; its own floor collision remains.
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 1)
		animator.play("die", 0.04, animator.get_animation("die").length / 0.55)
		print("ENEMY DEAD")
		return
	if state == State.STAGGER:
		return # Damage is accepted, but never stack impulses or restart this reaction.
	state = State.STAGGER
	state_time = 0.0
	var away := global_position - source_position
	away.y = 0.0
	away = away.normalized()
	knockback_velocity = Vector2(away.x, away.z) * knockback
	if not away.is_zero_approx():
		visuals.rotation.y = atan2(away.x, away.z)
	animator.play("reactions/hit", 0.03, 0.24 / stagger_duration)
