extends CharacterBody3D

@export var move_speed: float = 5.0
@export var acceleration: float = 24.0
@export var deceleration: float = 30.0
@export var turn_speed: float = 12.0
@export var camera_speed: float = 2.4

@onready var visuals: Node3D = $Visuals
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D


func _ready() -> void:
	# The camera should collide with the arena, but not the player's capsule.
	spring_arm.add_excluded_object(get_rid())


func _physics_process(delta: float) -> void:
	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	camera_pivot.rotation.y = wrapf(
		camera_pivot.rotation.y - look_input.x * camera_speed * delta, -PI, PI
	)
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x - look_input.y * camera_speed * delta,
		deg_to_rad(-60.0), deg_to_rad(25.0)
	)

	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# The pivot only rotates around Y, so camera pitch never tilts movement.
	# Preserve the stick magnitude for slow walking and capped diagonal speed.
	var move_direction := camera_pivot.global_basis * Vector3(move_input.x, 0.0, move_input.y)
	var target_velocity := move_direction * move_speed
	var rate := deceleration if move_input.is_zero_approx() else acceleration
	var horizontal_velocity := Vector2(velocity.x, velocity.z).move_toward(
		Vector2(target_velocity.x, target_velocity.z), rate * delta
	)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	if not move_input.is_zero_approx():
		var target_yaw := atan2(-move_direction.x, -move_direction.z)
		# Rotate only the mesh, leaving the camera free to orbit independently.
		visuals.rotation.y = lerp_angle(
			visuals.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta)
		)

	if Input.is_action_just_pressed("attack"):
		print("ATTACK")
