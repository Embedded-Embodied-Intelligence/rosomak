class_name SpawnEntry
extends Marker3D

## Off-screen / door-adjacent spawn marker. Optionally linked to a MissionDoor that opens on spawn.

@export var entry_id: StringName = &"entry"
@export var linked_door_path: NodePath
@export var open_door_on_spawn: bool = true
@export var spawn_jitter: float = 0.8

var linked_door: MissionDoor


func _ready() -> void:
	if linked_door_path != NodePath():
		linked_door = get_node_or_null(linked_door_path) as MissionDoor


func spawn_position() -> Vector3:
	return global_position + Vector3(
		randf_range(-spawn_jitter, spawn_jitter),
		0.05,
		randf_range(-spawn_jitter, spawn_jitter)
	)


func prepare_entry() -> void:
	if open_door_on_spawn and linked_door:
		linked_door.request_open()
