class_name Hurtbox
extends Area3D

signal hit_received(event: HitEvent)
## Legacy mirror for callers that still unpack positional args.
signal hit_received_legacy(damage: int, source_position: Vector3, hit_stop: float, knockback: float)

const DEFAULT_KNOCKBACK := 2.4

var enabled: bool = true


func receive_hit(event: HitEvent) -> bool:
	if not enabled or event == null or event.damage <= 0:
		return false
	hit_received.emit(event)
	return true


## Back-compat wrapper used by older tests / training setups.
func receive_hit_legacy(
	damage: int,
	source_position: Vector3,
	hit_stop: float,
	knockback: float = DEFAULT_KNOCKBACK
) -> bool:
	return receive_hit(HitEvent.legacy(damage, source_position, hit_stop, knockback))


func disable() -> void:
	# The immediate flag also rejects hits before the deferred physics change.
	enabled = false
	set_deferred("collision_layer", 0)
	$CollisionShape3D.set_deferred("disabled", true)
