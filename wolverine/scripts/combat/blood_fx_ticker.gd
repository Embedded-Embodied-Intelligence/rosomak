extends Node

## Advances BloodFx decal ages; spawned lazily by BloodFx.ensure_host.


func _process(delta: float) -> void:
	BloodFx.tick(delta)
