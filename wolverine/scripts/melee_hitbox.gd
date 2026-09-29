class_name MeleeHitbox
extends Area3D

signal hit_landed(contact_position: Vector3)

@export var damage: int = 25
@export var knockback: float = Hurtbox.DEFAULT_KNOCKBACK
@export_range(0.0, 0.1) var hit_stop_duration: float = 0.05
@export_flags_3d_physics var world_mask: int = 1

var active: bool = false
var attacker: Node3D
var _hit_targets: Dictionary = {}

@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func begin_swing(source: Node3D) -> void:
	attacker = source
	_hit_targets.clear()
	set_active(false)


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
		if hurtbox.receive_hit(damage, attacker.global_position, hit_stop_duration, knockback):
			_hit_targets[target_id] = true
			hit_landed.emit(contact)
