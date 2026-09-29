extends Node3D

## Lightweight slash flash; heavier hits spawn a larger cross.
var size: float = 1.0
var age: float = 0.0


func _ready() -> void:
	rotation.y = randf_range(0.0, TAU)
	rotation.z = randf_range(-0.4, 0.4)


func _process(delta: float) -> void:
	age += delta
	if age >= 0.12:
		queue_free()
		return
	var t := age / 0.12
	scale = Vector3.ONE * size * (1.0 - t * 0.35)
	rotate_y(delta * 8.0)
