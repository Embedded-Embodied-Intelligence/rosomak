extends Node3D

## Heavier hits spawn a larger flash; the lifetime stays the same.
var size: float = 1.0
var age: float = 0.0


func _process(delta: float) -> void:
	age += delta
	if age >= 0.12:
		queue_free()
		return
	scale = Vector3.ONE * size * (1.0 - age / 0.12)
