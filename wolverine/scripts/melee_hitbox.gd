class_name MeleeHitbox
extends Area3D

signal hit_landed(contact_position: Vector3)

@export var damage: int = 25
@export var knockback: float = Hurtbox.DEFAULT_KNOCKBACK
@export_range(0.0, 0.2) var hit_stop_duration: float = 0.05
@export_flags_3d_physics var world_mask: int = 1

var active: bool = false
var attacker: Node3D
var move_id: StringName = &""
var attack_strength: int = CombatAttackData.Strength.LIGHT
var blood_tier: int = CombatAttackData.BloodTier.LIGHT_FLESH
var stagger_bonus: float = 0.0
var last_hit_event: HitEvent
var _hit_targets: Dictionary = {}
var _move: CombatAttackData

@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func begin_swing(source: Node3D, move: CombatAttackData = null) -> void:
	attacker = source
	_move = move
	_hit_targets.clear()
	if move:
		damage = move.damage
		knockback = move.knockback
		hit_stop_duration = move.hit_stop
		move_id = move.id
		attack_strength = move.strength
		blood_tier = move.blood_tier
	set_active(false)


func configure_from_move(move: CombatAttackData, damage_scale: float = 1.0) -> void:
	_move = move
	damage = maxi(1, roundi(float(move.damage) * damage_scale))
	knockback = move.knockback
	hit_stop_duration = move.hit_stop
	move_id = move.id
	attack_strength = move.strength
	blood_tier = move.blood_tier


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	collision_shape.set_deferred("disabled", not value)


func check_hits() -> void:
	if not active or not is_instance_valid(attacker):
		return
	# Query the current hand transform, avoiding Area3D's previous-step overlap list.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := get_world_3d().direct_space_state
	for result in space.intersect_shape(query, 8):
		var hurtbox := result.collider as Hurtbox
		if hurtbox == null or not hurtbox.enabled or hurtbox.get_parent() == attacker:
			continue
		# Hurtboxes are direct children of their receiver: multiple boxes still count once.
		var target_id := hurtbox.get_parent().get_instance_id()
		if _hit_targets.has(target_id):
			continue
		var obstruction := PhysicsRayQueryParameters3D.create(
			attacker.global_position + Vector3.UP, hurtbox.global_position, world_mask
		)
		obstruction.hit_from_inside = true
		if not space.intersect_ray(obstruction).is_empty():
			continue
		var contact := global_position.lerp(hurtbox.global_position, 0.5)
		var event: HitEvent
		if _move:
			event = HitEvent.from_move(_move, attacker, attacker.global_position)
			event.damage = damage
			event.knockback = knockback
			event.hit_stop = hit_stop_duration
		else:
			event = HitEvent.legacy(damage, attacker.global_position, hit_stop_duration, knockback)
			event.attacker = attacker
			event.source_move_id = move_id
			event.attack_strength = attack_strength
			event.blood_tier = blood_tier
			event.stagger_bonus = stagger_bonus
			var dir := hurtbox.global_position - attacker.global_position
			dir.y = 0.0
			event.direction = dir.normalized() if not dir.is_zero_approx() else Vector3.FORWARD
		if hurtbox.receive_hit(event):
			_hit_targets[target_id] = true
			last_hit_event = event
			hit_landed.emit(contact)
