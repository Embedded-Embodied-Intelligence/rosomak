class_name Hurtbox
extends Area3D

signal hit_received(damage: int, source_position: Vector3, hit_stop: float, knockback: float)

const DEFAULT_KNOCKBACK := 2.4

var enabled: bool = true


func receive_hit(damage: int, source_position: Vector3, hit_stop: float, knockback: float = DEFAULT_KNOCKBACK) -> bool:
	if not enabled or damage <= 0:
		return false
	hit_received.emit(damage, source_position, hit_stop, knockback)
	return true


func disable() -> void:
	# The immediate flag also rejects hits before the deferred physics change.
	enabled = false
	set_deferred("collision_layer", 0)
	$CollisionShape3D.set_deferred("disabled", true)
