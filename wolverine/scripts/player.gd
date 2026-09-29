class_name Player
extends CharacterBody3D

signal health_changed(health: int, max_health: int)
signal rage_changed(rage: float, raging: bool)
signal hit_chain_changed(count: int)
signal hurt(damage: int)
signal died

## Core locomotion + combat. AttackKind covers light string / heavy / lunge / counter /
## grab interactions while State remains the FSM bucket (ATTACK holds most swings).
enum State { IDLE, RUN, DODGE, ATTACK, HURT, DEAD, GRAB, THROW, WALL_SLAM, FINISHER }
enum AttackKind {
	NONE, LIGHT_1, LIGHT_2, LIGHT_3, HEAVY, LUNGE, COUNTER, STAB
}

const ANIMATIONS: Array[StringName] = [
	&"idle", &"sprint", &"actions/dodge", &"attack-melee-right", &"reactions/hit", &"die"
]
const HIT_IMPACT := preload("res://scenes/hit_impact.tscn")
const CharacterAnimLib := preload("res://scripts/combat/character_anim.gd")
const RAGE_MAX := 100.0
const COUNTER_WINDOW := 0.6
const GRAB_RANGE := 1.85
const FINISHER_RANGE := 2.15
const LUNGE_MIN := 2.0
const LUNGE_MAX := 4.2
const WALL_CHECK := 1.35
const FINISHER_HP_RATIO := 0.35

@export var move_speed: float = 5.0
@export var acceleration: float = 24.0
@export var deceleration: float = 30.0
@export var turn_speed: float = 14.0
@export var turn_speed_idle: float = 9.0
@export var camera_speed: float = 2.4
@export var mouse_sensitivity: float = 0.0025
@export_range(1.0, 20.0) var dodge_speed: float = 11.0
@export_range(0.1, 1.0) var dodge_duration: float = 0.34
@export_range(0.0, 2.0) var dodge_cooldown: float = 0.26
@export_range(0.1, 2.0) var attack_duration: float = 0.5
@export_range(0.0, 1.0) var dodge_iframe_start: float = 0.04
@export_range(0.0, 1.0) var dodge_iframe_end: float = 0.24
@export_range(0.0, 0.1) var camera_impulse_strength: float = 0.035
@export_range(0.05, 0.3) var camera_impulse_duration: float = 0.16
@export_range(0.5, 3.0) var walk_anim_threshold: float = 1.35
@export_range(0.05, 0.5) var footstep_interval: float = 0.28

@export_group("Magnetism")
@export var aim_assist_range: float = 4.2
@export_range(0.0, 180.0) var aim_assist_angle: float = 65.0
@export_range(0.0, 0.35) var lunge_time: float = 0.14
@export var max_lunge_speed: float = 14.0
@export_range(0.0, 1.0) var max_magnet_yaw: float = 0.55

@export_group("Vitals")
@export var max_health: int = 100
@export var regen_delay: float = 3.0
@export var regen_rate: float = 10.0
@export_range(0.1, 1.0) var hurt_duration: float = 0.3
@export_range(0.0, 2.0) var hurt_grace: float = 0.6
@export var rage_per_hit: float = 6.0
@export var rage_duration: float = 8.0
@export var rage_damage_multiplier: float = 1.5
@export var rage_speed_multiplier: float = 1.3
@export var rage_regen_rate: float = 18.0

var state: State = State.IDLE
var state_time: float = 0.0
var dodge_cooldown_left: float = 0.0
var dodge_direction := Vector3.ZERO
var hit_stop_left: float = 0.0
var camera_impulse_left: float = 0.0
var combo_step: int = 0
var combo_queued: bool = false
var heavy_attack: bool = false
var attack_kind: AttackKind = AttackKind.NONE
var current_move: CombatAttackData
var lunge_velocity := Vector3.ZERO
var knockback_velocity := Vector2.ZERO
var health: float
var rage: float = 0.0
var rage_left: float = 0.0
var since_damage: float = 0.0
var grace_left: float = 0.0
var hit_chain: int = 0
var hit_chain_left: float = 0.0
var controls_enabled: bool = true
var counter_window_left: float = 0.0
var grab_target: Node3D
var grab_stabs: int = 0
var _locked_iframes: bool = false
var _trail: SlashTrail
var _fov_base: float = 70.0
var _fov_punch: float = 0.0
var _attack_device: int = -1
var _rumble_device: int = -1
var _impulse_scale: float = 1.0
var _mouse_look := Vector2.ZERO
var _shown_health: int = 0
var _overlay := StandardMaterial3D.new()
var _claw_material := StandardMaterial3D.new()
var _debug_label: Label3D
var _attack_held_prev: bool = false
var _grab_held_prev: bool = false
var _context_prompt: String = ""
var _tutorials_shown: Dictionary = {} ## StringName -> bool
var _pending_throw_dir := Vector3.ZERO
var _throw_released: bool = false
var _footstep_left: float = 0.0
var _loco_anim: StringName = &"idle"
var _finisher_cam_yaw: float = 0.0
var _finisher_cam_blend: float = 0.0
var _last_hurt_dir := Vector3.FORWARD
var _hurt_play_duration: float = 0.3
signal context_prompt_changed(text: String)
signal tutorial_requested(text: String)

var is_invulnerable: bool:
	get:
		if _locked_iframes:
			return true
		return state == State.DODGE and state_time >= dodge_iframe_start and state_time < dodge_iframe_end

var raging: bool:
	get:
		return rage_left > 0.0

var is_alive: bool:
	get:
		return state != State.DEAD

@onready var visuals: Node3D = $Visuals
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var animator: AnimationPlayer = $Visuals/Humanoid/AnimationPlayer
@onready var attack_hand: Node3D = $"Visuals/Humanoid/figurine-cube-detailed/root/torso/arm-right"
@onready var limbs: Array[Node3D] = [
	attack_hand,
	$"Visuals/Humanoid/figurine-cube-detailed/root/torso/arm-left",
	$"Visuals/Humanoid/figurine-cube-detailed/root/leg-right",
]
@onready var attack_hitbox: MeleeHitbox = $Visuals/AttackHitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	add_to_group("player")
	DebugCombat.reset_release()
	health = max_health
	_shown_health = max_health
	_fov_base = camera.fov
	current_move = CombatAttackData.light_1()
	spring_arm.add_excluded_object(get_rid())
	if animator.has_animation_library(&"actions"):
		animator.remove_animation_library(&"actions")
	if animator.has_animation_library(&"reactions"):
		animator.remove_animation_library(&"reactions")
	animator.add_animation_library(&"actions", CharacterAnimLib.build_actions())
	animator.add_animation_library(&"reactions", CharacterAnimLib.build_reactions())
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if animator.has_animation(&"idle"):
		animator.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
	if animator.has_animation(&"walk"):
		animator.get_animation(&"walk").loop_mode = Animation.LOOP_LINEAR
	if animator.has_animation(&"sprint"):
		animator.get_animation(&"sprint").loop_mode = Animation.LOOP_LINEAR
	attack_hitbox.hit_landed.connect(_on_hit_landed)
	hurtbox.hit_received.connect(_on_hurt)
	_apply_claw_fighter_look()
	animator.play(&"idle")
	if DebugCombat.state_label or DebugCombat.combo_label:
		_debug_label = Label3D.new()
		_debug_label.position = Vector3(0, 2.2, 0)
		_debug_label.font_size = 28
		add_child(_debug_label)
	print(State.keys()[state])


func _apply_claw_fighter_look() -> void:
	## Bold comic-book yellow/blue/black claw-fighter silhouette (original, fan-inspired).
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.82, 0.08)
	yellow.roughness = 0.48
	yellow.metallic = 0.05
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.08, 0.22, 0.68)
	blue.roughness = 0.42
	blue.metallic = 0.15
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.04, 0.04, 0.05)
	black.roughness = 0.62
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.1, 0.12, 0.18)
	leather.roughness = 0.78
	leather.metallic = 0.08
	_claw_material.albedo_color = Color(0.88, 0.9, 0.94)
	_claw_material.metallic = 1.0
	_claw_material.roughness = 0.12
	_claw_material.emission_enabled = true
	_claw_material.emission = Color(0.55, 0.65, 0.8)
	_claw_material.emission_energy_multiplier = 0.7
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for mesh in $Visuals/Humanoid.find_children("*", "MeshInstance3D", true, false):
		var n := String(mesh.name).to_lower()
		var mat := yellow
		if "leg" in n or "boot" in n or "foot" in n:
			mat = blue
		elif "arm" in n or "hand" in n:
			mat = yellow
		elif "head" in n or "hair" in n:
			mat = black
		elif "torso" in n or "body" in n or "chest" in n:
			mat = yellow
		mesh.material_override = mat
		mesh.material_overlay = _overlay
	_attach_mask_fins()
	_attach_suit_accents(leather, blue)
	_attach_claws(limbs[0])
	_attach_claws(limbs[1])
	# Uniform visual scale only — never scale Visuals non-uniformly (Jolt hitbox child).
	var torso: Node3D = $Visuals/Humanoid.find_child("torso", true, false)
	if torso:
		torso.scale = Vector3(1.18, 1.08, 1.16)


func _attach_suit_accents(leather: StandardMaterial3D, blue: StandardMaterial3D) -> void:
	var torso: Node3D = $Visuals/Humanoid.find_child("torso", true, false)
	if torso == null or torso.get_node_or_null("SuitAccents"):
		return
	var accents := Node3D.new()
	accents.name = "SuitAccents"
	torso.add_child(accents)
	for angle in [-38.0, 38.0]:
		var strap := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.55, 0.04)
		strap.mesh = box
		strap.material_override = leather
		strap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strap.position = Vector3(0.0, 0.05, 0.12)
		strap.rotation_degrees = Vector3(8.0, 0.0, angle)
		accents.add_child(strap)
	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.42, 0.08, 0.1)
	belt.mesh = belt_mesh
	belt.material_override = leather
	belt.position = Vector3(0.0, -0.28, 0.1)
	accents.add_child(belt)
	var buckle := MeshInstance3D.new()
	var buckle_mesh := BoxMesh.new()
	buckle_mesh.size = Vector3(0.12, 0.1, 0.06)
	buckle.mesh = buckle_mesh
	buckle.material_override = blue
	buckle.position = Vector3(0.0, -0.28, 0.16)
	accents.add_child(buckle)


func _attach_mask_fins() -> void:
	var head: Node3D = $Visuals/Humanoid.find_child("head", true, false)
	if head == null:
		head = $Visuals/Humanoid.find_child("Head", true, false)
	if head == null:
		return
	if head.get_node_or_null("MaskFins"):
		return
	var fins := Node3D.new()
	fins.name = "MaskFins"
	head.add_child(fins)
	fins.position = Vector3(0.0, 0.12, -0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.04)
	mat.roughness = 0.55
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.055, 0.34, 0.09)
		fin.mesh = box
		fin.material_override = mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fin.position = Vector3(side * 0.15, 0.2, -0.05)
		fin.rotation_degrees = Vector3(-22.0, side * 18.0, side * 14.0)
		fins.add_child(fin)
	var brow := MeshInstance3D.new()
	var brow_mesh := BoxMesh.new()
	brow_mesh.size = Vector3(0.34, 0.07, 0.13)
	brow.mesh = brow_mesh
	brow.material_override = mat
	brow.position = Vector3(0.0, 0.1, 0.09)
	fins.add_child(brow)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.95, 0.95, 0.98)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.7, 0.75, 0.85)
	eye_mat.emission_energy_multiplier = 0.4
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.09, 0.04, 0.03)
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(side * 0.07, 0.04, 0.14)
		fins.add_child(eye)


func _attach_claws(hand: Node3D) -> void:
	if hand.get_node_or_null("Claws"):
		return
	var claws := Node3D.new()
	claws.name = "Claws"
	hand.add_child(claws)
	claws.position = Vector3(0.0, -0.3, 0.03)
	var knuckle := StandardMaterial3D.new()
	knuckle.albedo_color = Color(0.25, 0.22, 0.2)
	knuckle.metallic = 0.4
	knuckle.roughness = 0.45
	for i in 3:
		var mount := MeshInstance3D.new()
		var mount_mesh := BoxMesh.new()
		mount_mesh.size = Vector3(0.045, 0.06, 0.04)
		mount.mesh = mount_mesh
		mount.material_override = knuckle
		mount.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.position = Vector3((i - 1) * 0.055, -0.02, 0.01)
		claws.add_child(mount)
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.032, 0.58, 0.018)
		blade.mesh = box
		blade.material_override = _claw_material
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blade.position = Vector3((i - 1) * 0.055, -0.28, 0.02)
		blade.rotation_degrees = Vector3(12.0, 0.0, (i - 1) * 7.0)
		claws.add_child(blade)
		var tip := MeshInstance3D.new()
		var tip_mesh := BoxMesh.new()
		tip_mesh.size = Vector3(0.02, 0.1, 0.012)
		tip.mesh = tip_mesh
		tip.material_override = _claw_material
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tip.position = Vector3((i - 1) * 0.055, -0.58, 0.03)
		tip.rotation_degrees = Vector3(18.0, 0.0, (i - 1) * 7.0)
		claws.add_child(tip)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_look += event.relative * mouse_sensitivity


func _physics_process(delta: float) -> void:
	var stopped := hit_stop_left > 0.0
	hit_stop_left = maxf(0.0, hit_stop_left - delta)
	# Track analog edges even during hit-stop so RT/LT don't "stick" after freeze.
	var attack_edge := _poll_action_edge("attack", true)
	var grab_edge := _poll_action_edge("grab", false)
	if not stopped:
		state_time += delta
	dodge_cooldown_left = maxf(0.0, dodge_cooldown_left - delta)
	counter_window_left = maxf(0.0, counter_window_left - delta)
	_update_vitals(delta)
	_sync_grab_target(delta)

	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	camera_pivot.rotation.y = wrapf(
		camera_pivot.rotation.y - look_input.x * camera_speed * delta - _mouse_look.x, -PI, PI
	)
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x - look_input.y * camera_speed * delta - _mouse_look.y,
		deg_to_rad(-60.0), deg_to_rad(25.0)
	)
	_mouse_look = Vector2.ZERO
	hurtbox.enabled = state != State.DEAD and not is_invulnerable and grace_left <= 0.0
	if stopped:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return

	var can_act := controls_enabled and state != State.DEAD
	var move_input := Vector2.ZERO
	if can_act:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Locomotion stick is ignored during locked interactions, but grab-throw still reads aim.
	var loco_input := Vector2.ZERO if _is_locked_interaction() else move_input
	var move_direction := camera_pivot.global_basis * Vector3(loco_input.x, 0.0, loco_input.y)
	var resume_state := State.RUN if not loco_input.is_zero_approx() else State.IDLE

	_update_action_states(can_act, move_input, move_direction, resume_state, attack_edge)
	_try_start_actions(can_act, loco_input, move_direction, attack_edge, grab_edge)
	_update_context_prompt()

	var target_velocity := move_direction * move_speed
	var rate := deceleration if loco_input.is_zero_approx() else acceleration
	if state == State.ATTACK or state == State.HURT or state == State.DEAD or _is_locked_interaction():
		target_velocity = Vector3.ZERO
		rate = deceleration
	var horizontal_velocity := Vector2(velocity.x, velocity.z).move_toward(
		Vector2(target_velocity.x, target_velocity.z), rate * delta
	)
	if state == State.DODGE:
		horizontal_velocity = Vector2(dodge_direction.x, dodge_direction.z) * dodge_speed
	elif state == State.ATTACK and not lunge_velocity.is_zero_approx():
		var lunge_t := clampf(state_time / maxf(0.01, lunge_time), 0.0, 1.0)
		var ease := 1.0 - lunge_t * lunge_t  # decelerate into impact instead of skate-cut
		horizontal_velocity = Vector2(lunge_velocity.x, lunge_velocity.z) * ease
		if state_time >= lunge_time:
			lunge_velocity = Vector3.ZERO
			horizontal_velocity = Vector2.ZERO
	elif state == State.ATTACK and current_move and current_move.advance_speed > 0.0:
		var fwd := -visuals.global_basis.z
		fwd.y = 0.0
		if state_time < _attack_time() * current_move.active_end:
			horizontal_velocity = Vector2(fwd.x, fwd.z) * current_move.advance_speed
	elif state == State.HURT:
		horizontal_velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 14.0 * delta)
	elif state == State.THROW:
		horizontal_velocity = Vector2.ZERO
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	var facing_direction := dodge_direction if state == State.DODGE else move_direction
	var holds_facing := (
		state == State.ATTACK or state == State.HURT or state == State.DEAD or _is_locked_interaction()
	)
	if not holds_facing and not facing_direction.is_zero_approx():
		var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
		var ground_speed := Vector2(velocity.x, velocity.z).length()
		var yaw_rate := turn_speed if ground_speed > 0.6 else turn_speed_idle
		# Faster catch-up when nearly aligned; soft turn-in-place at low speed.
		var yaw_err := absf(wrapf(target_yaw - visuals.rotation.y, -PI, PI))
		if yaw_err > 0.9 and ground_speed < 0.35:
			yaw_rate *= 1.35
		visuals.rotation.y = lerp_angle(
			visuals.rotation.y, target_yaw, 1.0 - exp(-yaw_rate * delta)
		)

	if state == State.IDLE or state == State.RUN:
		_update_locomotion_anim(delta)

	animator.advance(delta)
	_update_hitbox_active()
	_update_finisher_camera(delta)
	_update_debug_label()


func _poll_action_edge(action: StringName, is_attack: bool) -> bool:
	## Analog triggers (RT/LT) rarely fully release; track strength edges past deadzone.
	var held := Input.is_action_pressed(action)
	var prev := _attack_held_prev if is_attack else _grab_held_prev
	if is_attack:
		_attack_held_prev = held
	else:
		_grab_held_prev = held
	return held and not prev


func _is_locked_interaction() -> bool:
	return state == State.GRAB or state == State.THROW or state == State.WALL_SLAM or state == State.FINISHER


func _update_action_states(
	can_act: bool, move_input: Vector2, move_direction: Vector3, resume_state: State, attack_edge: bool = false
) -> void:
	if state == State.DODGE:
		_poll_dodge_counter()
		if state_time >= dodge_duration:
			# Soft handoff into loco — keep a slice of dodge momentum, not a hard stop/snap.
			var carry := dodge_direction * dodge_speed * 0.35
			if not move_direction.is_zero_approx():
				velocity.x = move_direction.x * move_speed + carry.x * 0.25
				velocity.z = move_direction.z * move_speed + carry.z * 0.25
			else:
				velocity.x = carry.x
				velocity.z = carry.z
			_set_state(resume_state)
	elif state == State.ATTACK:
		_handle_attack_cancel(can_act, move_direction, resume_state, attack_edge)
	elif state == State.HURT and state_time >= _hurt_play_duration:
		_set_state(resume_state)
	elif state == State.GRAB:
		_handle_grab_input(can_act, move_input, attack_edge)
	elif state == State.THROW:
		if not _throw_released and state_time >= 0.18:
			_release_pending_throw()
		if state_time >= 0.45:
			if not _throw_released:
				_release_pending_throw()
			_set_state(resume_state)
	elif state == State.WALL_SLAM and state_time >= 1.0:
		_release_grab(false)
		_set_state(resume_state)
	elif state == State.FINISHER and state_time >= (current_move.time if current_move else 2.0) * attack_duration:
		_release_grab(true)
		_finisher_cam_blend = 0.0
		spring_arm.spring_length = 5.0
		_set_state(resume_state)


func _handle_attack_cancel(
	can_act: bool, move_direction: Vector3, resume_state: State, attack_edge: bool = false
) -> void:
	var swing_time := _attack_time()
	var move := current_move
	var in_active := state_time >= swing_time * move.startup and state_time < swing_time * move.active_end
	var in_combo_window := (
		attack_kind >= AttackKind.LIGHT_1 and attack_kind <= AttackKind.LIGHT_3
		and combo_step < 2 and state_time >= swing_time * move.combo_window
	)
	# Buffer next light during combo window; never cancel mid-active into another attack.
	# Accept both just_pressed and our analog edge so RT mash/hold-release works on pad.
	var light_press := attack_edge or Input.is_action_just_pressed("attack")
	if can_act and in_combo_window and light_press:
		combo_queued = true
	if can_act and move.can_dodge_cancel_late and not in_active and state_time >= swing_time * move.cancel_window:
		if Input.is_action_just_pressed("dodge") and dodge_cooldown_left <= 0.0:
			combo_queued = false
			dodge_direction = move_direction.normalized() if not move_direction.is_zero_approx() else -visuals.global_basis.z
			dodge_cooldown_left = dodge_duration + dodge_cooldown
			_set_state(State.DODGE)
			return
	if combo_queued and state_time >= swing_time * move.cancel_window and attack_kind != AttackKind.STAB:
		_start_light(combo_step + 1, move_direction)
	elif state_time >= swing_time:
		if attack_kind == AttackKind.STAB and is_instance_valid(grab_target) and grab_target.get("is_alive") != false and grab_stabs < 2:
			_set_state(State.GRAB, true)
		else:
			if attack_kind == AttackKind.STAB:
				_release_grab(false)
			_set_state(resume_state)


func _try_start_actions(
	can_act: bool, move_input: Vector2, move_direction: Vector3, attack_edge: bool = false, grab_edge: bool = false
) -> void:
	if not can_act:
		return
	var light_press := attack_edge or Input.is_action_just_pressed("attack")
	var grab_press := grab_edge or Input.is_action_just_pressed("grab")
	# Counter window: RT during post-dodge window.
	if counter_window_left > 0.0 and light_press and (
		state == State.IDLE or state == State.RUN or state == State.DODGE
	):
		_start_counter(move_direction)
		return
	if _is_locked_interaction():
		return
	if state == State.IDLE or state == State.RUN:
		if not is_on_floor():
			return
		if Input.is_action_just_pressed("dodge") and dodge_cooldown_left <= 0.0:
			dodge_direction = move_direction.normalized() if not move_input.is_zero_approx() else -visuals.global_basis.z
			dodge_cooldown_left = dodge_duration + dodge_cooldown
			_set_state(State.DODGE)
		elif grab_press:
			_try_contextual_grab(move_direction)
		elif Input.is_action_just_pressed("attack_heavy"):
			_start_heavy_or_lunge(move_direction, move_input)
		elif light_press:
			_start_light(0, move_direction)
	if can_act and Input.is_action_just_pressed("rage") and rage >= RAGE_MAX and not raging:
		_start_rage()


func _poll_dodge_counter() -> void:
	if not is_invulnerable:
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get("state") != 3: # Enemy.State.STRIKE
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() <= 2.4:
			counter_window_left = COUNTER_WINDOW
			_sfx(&"counter_ready", -6.0, 0.02)
			return


func _try_contextual_grab(move_direction: Vector3) -> void:
	var target := _best_grab_target()
	if target == null:
		return
	# Signature finisher when eligible.
	if _finisher_eligible(target):
		_offer_tutorial(&"finisher", "LT - Finish vulnerable enemy")
		_start_finisher(target)
		return
	# Wall slam when staggered near wall.
	if _wall_slam_eligible(target):
		_start_wall_slam(target)
		return
	if not _grab_eligible(target):
		_sfx(&"grab_resist", -4.0)
		return
	_offer_tutorial(&"grab", "LT - Grab nearby enemy")
	_start_grab(target, move_direction)


func _grab_eligible(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.get("is_alive") == false:
		return false
	var distance := Vector3(
		target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z
	).length()
	if distance > GRAB_RANGE:
		return false
	if target.has_method("can_be_grabbed"):
		return target.can_be_grabbed()
	return true


func _finisher_eligible(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var distance := Vector3(
		target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z
	).length()
	if distance > FINISHER_RANGE:
		return false
	if target.has_method("is_finisher_ready"):
		return target.is_finisher_ready()
	var hp: Variant = target.get("health")
	var max_hp: Variant = target.get("max_health")
	if hp is int and max_hp is int and max_hp > 0:
		return float(hp) / float(max_hp) <= FINISHER_HP_RATIO
	return false


func _wall_slam_eligible(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var staggered := false
	if target.has_method("is_staggered"):
		staggered = target.is_staggered()
	elif int(target.get("state")) == 5:
		staggered = true
	if not staggered:
		return false
	# Only when the enemy is pressed against a wall (short ray from their back).
	return _enemy_pressed_to_wall(target)


func _enemy_pressed_to_wall(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var origin := target.global_position + Vector3.UP * 0.9
	var away := target.global_position - global_position
	away.y = 0.0
	if away.is_zero_approx():
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, origin + away.normalized() * 0.9, 1)
	return not space.intersect_ray(query).is_empty()


func _near_wall(from: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var query := PhysicsRayQueryParameters3D.create(
			from + Vector3.UP * 0.9, from + Vector3.UP * 0.9 + dir * WALL_CHECK, 1
		)
		if not space.intersect_ray(query).is_empty():
			return true
	return false


func _best_grab_target() -> Node3D:
	var forward := -visuals.global_basis.z
	forward.y = 0.0
	var best: Node3D
	var best_score := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > FINISHER_RANGE or distance < 0.05:
			continue
		var angle := forward.angle_to(offset)
		if angle > deg_to_rad(95.0):
			continue
		if not _has_los(enemy):
			continue
		var score := distance + angle * 1.35
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _has_los(enemy: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP, enemy.global_position + Vector3.UP, 1
	)
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()


func _start_grab(target: Node3D, _move_direction: Vector3) -> void:
	grab_target = target
	grab_stabs = 0
	_locked_iframes = true
	if target.has_method("enter_grabbed"):
		target.enter_grabbed(self)
	_face_target(target)
	_set_state(State.GRAB, true)
	_sfx(&"grab", -2.0)
	_offer_tutorial(&"grab_follow", "RT - Stab   RB - Throw")


func _handle_grab_input(can_act: bool, move_input: Vector2, attack_edge: bool = false) -> void:
	if not is_instance_valid(grab_target) or grab_target.get("is_alive") == false:
		_release_grab(false)
		_set_state(State.IDLE)
		return
	if state_time > 3.2:
		_release_grab(false)
		_set_state(State.IDLE)
		return
	if not can_act:
		return
	var stab_press := attack_edge or Input.is_action_just_pressed("attack")
	if stab_press and grab_stabs < 2:
		_start_grab_stab()
	elif Input.is_action_just_pressed("attack_heavy"):
		# Allow throw even with neutral stick — use facing as fallback.
		var throw_stick := move_input
		if throw_stick.is_zero_approx():
			throw_stick = Vector2(0.0, -1.0)
		_start_throw(throw_stick)
	elif Input.is_action_just_pressed("dodge"):
		_release_grab(false)
		_set_state(State.IDLE)


func _start_grab_stab() -> void:
	grab_stabs += 1
	attack_kind = AttackKind.STAB
	current_move = CombatAttackData.grab_stab()
	heavy_attack = false
	_configure_hitbox(current_move)
	_locked_iframes = true
	_set_state(State.ATTACK, true)
	# Direct stab damage on hit frame (deterministic, no free-aim miss while locked).
	var hit_at := _attack_time() * current_move.startup
	get_tree().create_timer(hit_at).timeout.connect(_apply_grab_stab_damage, CONNECT_ONE_SHOT)


func _apply_grab_stab_damage() -> void:
	if attack_kind != AttackKind.STAB or not is_instance_valid(grab_target):
		return
	if state != State.ATTACK:
		return
	var event := HitEvent.from_move(current_move, self, global_position)
	var hb := grab_target.get_node_or_null("Hurtbox") as Hurtbox
	if hb:
		hb.receive_hit(event)
	BloodFx.spawn(get_tree(), grab_target.global_position + Vector3.UP * 0.9, -visuals.global_basis.z, event.blood_tier)
	hit_stop_left = current_move.hit_stop
	_kick_camera(current_move.camera_impulse)
	_rumble(current_move.rumble_weak, current_move.rumble_strong, current_move.rumble_duration)
	_sfx(&"heavy_hit")
	hit_chain += 1
	hit_chain_left = 2.0
	hit_chain_changed.emit(hit_chain)
	add_rage(rage_per_hit)


func _start_throw(move_input: Vector2) -> void:
	if not is_instance_valid(grab_target):
		return
	var dir := camera_pivot.global_basis * Vector3(move_input.x, 0.0, move_input.y)
	dir.y = 0.0
	if dir.is_zero_approx():
		dir = -visuals.global_basis.z
	dir = dir.normalized()
	_pending_throw_dir = dir
	_throw_released = false
	_set_state(State.THROW, true)
	_sfx(&"throw", -1.0)
	_kick_camera(2.0)
	_rumble(0.35, 0.55, 0.12)


func _release_pending_throw() -> void:
	if _throw_released:
		return
	_throw_released = true
	if is_instance_valid(grab_target) and grab_target.has_method("receive_throw"):
		grab_target.receive_throw(_pending_throw_dir * 16.0, self)
	_kick_camera(2.6)
	_rumble(0.45, 0.7, 0.18)
	_release_grab(false)


func _start_wall_slam(target: Node3D) -> void:
	grab_target = target
	_locked_iframes = true
	current_move = CombatAttackData.wall_slam()
	attack_kind = AttackKind.NONE
	if target.has_method("enter_grabbed"):
		target.enter_grabbed(self)
	_face_target(target)
	_configure_hitbox(current_move)
	_set_state(State.WALL_SLAM, true)
	_sfx(&"wall_slam", -1.0)
	_kick_camera(2.6)
	_rumble(0.5, 0.75, 0.22)
	# Apply slam damage on "hit frame".
	var hit_at := attack_duration * current_move.time * current_move.startup
	await get_tree().create_timer(hit_at).timeout
	if is_instance_valid(target) and state == State.WALL_SLAM:
		var event := HitEvent.from_move(current_move, self, global_position)
		event.blood_tier = CombatAttackData.BloodTier.WALL
		if target.has_node("Hurtbox"):
			(target.get_node("Hurtbox") as Hurtbox).receive_hit(event)
		BloodFx.spawn(get_tree(), target.global_position + Vector3.UP, -visuals.global_basis.z, event.blood_tier)
		_sfx(&"wall_impact", -2.0)


func _start_finisher(target: Node3D) -> void:
	grab_target = target
	_locked_iframes = true
	current_move = CombatAttackData.signature_finisher()
	attack_kind = AttackKind.NONE
	heavy_attack = false
	if target.has_method("enter_grabbed"):
		target.enter_grabbed(self)
	_face_target(target)
	_configure_hitbox(current_move)
	_set_state(State.FINISHER, true)
	_fov_punch = -10.0
	_finisher_cam_blend = 1.0
	# Side offset signed by camera relative to player→target.
	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var cam_right := camera_pivot.global_basis.x
	cam_right.y = 0.0
	_finisher_cam_yaw = 0.28 if cam_right.dot(to_t) >= 0.0 else -0.28
	_sfx(&"finisher_start", -1.0)
	_kick_camera(2.8)
	_rumble(0.4, 0.6, 0.2)
	var hit_at := attack_duration * current_move.time * current_move.startup
	# Real-time timer so brief kill slow-mo cannot soft-lock the finisher script.
	var timer := get_tree().create_timer(hit_at, true, false, true)
	await timer.timeout
	if is_instance_valid(target) and state == State.FINISHER:
		var event := HitEvent.from_move(current_move, self, global_position)
		if target.has_node("Hurtbox"):
			(target.get_node("Hurtbox") as Hurtbox).receive_hit(event)
		BloodFx.spawn(get_tree(), target.global_position + Vector3.UP * 1.0, -visuals.global_basis.z, CombatAttackData.BloodTier.FINISHER)
		hit_stop_left = current_move.hit_stop
		_sfx(&"finisher_hit", 0.0)
		_rumble(0.55, 0.9, 0.28)
		CombatSlowMo.request(get_tree(), minf(current_move.kill_slow_mo, 0.12), 0.25)


func _release_grab(killed: bool) -> void:
	_locked_iframes = false
	if is_instance_valid(grab_target) and grab_target.has_method("exit_grabbed"):
		grab_target.exit_grabbed(killed)
	grab_target = null
	grab_stabs = 0
	_fov_punch = 0.0
	_finisher_cam_blend = 0.0


func _sync_grab_target(delta: float) -> void:
	if not is_instance_valid(grab_target):
		if _locked_iframes and _is_locked_interaction():
			_release_grab(false)
			if state != State.DEAD:
				_set_state(State.IDLE)
		return
	if state == State.GRAB or state == State.FINISHER or state == State.WALL_SLAM or (
		state == State.ATTACK and attack_kind == AttackKind.STAB
	):
		var hold_dist := 0.88 if state == State.GRAB else 0.95
		if state == State.ATTACK and attack_kind == AttackKind.STAB:
			hold_dist = 0.78  # pull in on stab contact
		var anchor := global_position - visuals.global_basis.z * hold_dist
		anchor.y = grab_target.global_position.y
		var pull := 22.0 if state == State.ATTACK and attack_kind == AttackKind.STAB else 18.0
		grab_target.global_position = grab_target.global_position.lerp(anchor, 1.0 - exp(-pull * delta))
		if grab_target.get("visuals") is Node3D:
			var to_player := global_position - grab_target.global_position
			to_player.y = 0.0
			if not to_player.is_zero_approx():
				(grab_target.visuals as Node3D).rotation.y = atan2(-to_player.x, -to_player.z)


func _face_target(target: Node3D) -> void:
	var offset := target.global_position - global_position
	offset.y = 0.0
	if not offset.is_zero_approx():
		visuals.rotation.y = atan2(-offset.x, -offset.z)


func add_rage(amount: float) -> void:
	if raging or state == State.DEAD:
		return
	rage = minf(RAGE_MAX, rage + amount)
	rage_changed.emit(rage, false)


func revive(full_health: bool = true) -> void:
	_release_grab(false)
	if full_health:
		health = max_health
	rage_left = 0.0
	grace_left = 0.9
	since_damage = 0.0
	hit_chain = 0
	hit_stop_left = 0.0
	knockback_velocity = Vector2.ZERO
	lunge_velocity = Vector3.ZERO
	combo_queued = false
	heavy_attack = false
	attack_kind = AttackKind.NONE
	counter_window_left = 0.0
	_locked_iframes = false
	controls_enabled = true
	hurtbox.enabled = true
	hurtbox.collision_layer = 32
	collision_layer = 2
	collision_mask = 1
	velocity = Vector3.ZERO
	Engine.time_scale = 1.0
	_set_state(State.IDLE, true)
	_emit_health()
	rage_changed.emit(rage, false)
	hit_chain_changed.emit(0)


func _current_move() -> CombatAttackData:
	return current_move if current_move else CombatAttackData.light_1()


func _attack_time() -> float:
	var speed := rage_speed_multiplier if raging else 1.0
	return attack_duration * _current_move().time / speed


func _start_light(step: int, move_direction: Vector3) -> void:
	var lights := CombatAttackData.lights()
	step = clampi(step, 0, lights.size() - 1)
	heavy_attack = false
	combo_step = step
	combo_queued = false
	current_move = lights[step]
	attack_kind = [AttackKind.LIGHT_1, AttackKind.LIGHT_2, AttackKind.LIGHT_3][step]
	_configure_hitbox(current_move)
	_aim_attack(move_direction, current_move.magnetism)
	_set_state(State.ATTACK, true)


func _start_heavy_or_lunge(move_direction: Vector3, move_input: Vector2) -> void:
	var target := _find_aim_target(move_direction, aim_assist_range, aim_assist_angle)
	var dist := 0.0
	if target:
		dist = Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z).length()
	var toward_enemy := target != null and dist >= LUNGE_MIN and dist <= LUNGE_MAX
	var stick_held := not move_input.is_zero_approx()
	heavy_attack = true
	combo_step = 0
	combo_queued = false
	# Lunge only when the stick is held toward a mid-range target (predatory gap-close).
	if toward_enemy and stick_held:
		current_move = CombatAttackData.lunge()
		attack_kind = AttackKind.LUNGE
		_configure_hitbox(current_move)
		_aim_attack(move_direction, current_move.magnetism, true)
	elif stick_held:
		current_move = CombatAttackData.heavy_advance()
		attack_kind = AttackKind.HEAVY
		_configure_hitbox(current_move)
		_aim_attack(move_direction, current_move.magnetism)
	else:
		current_move = CombatAttackData.heavy()
		attack_kind = AttackKind.HEAVY
		_configure_hitbox(current_move)
		_aim_attack(move_direction, current_move.magnetism)
	_set_state(State.ATTACK, true)


func _start_counter(move_direction: Vector3) -> void:
	counter_window_left = 0.0
	heavy_attack = false
	combo_step = 0
	combo_queued = false
	current_move = CombatAttackData.counter()
	attack_kind = AttackKind.COUNTER
	_configure_hitbox(current_move)
	_aim_attack(move_direction, current_move.magnetism)
	_set_state(State.ATTACK, true)
	_sfx(&"counter", -1.0)


func _configure_hitbox(move: CombatAttackData) -> void:
	var damage_scale := rage_damage_multiplier if raging else 1.0
	attack_hitbox.configure_from_move(move, damage_scale)


func _find_aim_target(move_direction: Vector3, range_m: float, angle_deg: float) -> Node3D:
	var forward := move_direction.normalized() if not move_direction.is_zero_approx() else -visuals.global_basis.z
	forward.y = 0.0
	var best: Node3D
	var best_score := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > range_m or distance < 0.01:
			continue
		var angle := forward.angle_to(offset)
		if angle > deg_to_rad(angle_deg):
			continue
		if not _has_los(enemy):
			continue
		var score := distance + angle * 2.0
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _aim_attack(move_direction: Vector3, magnetism: float = 1.0, force_lunge: bool = false) -> void:
	lunge_velocity = Vector3.ZERO
	if magnetism <= 0.0:
		return
	var forward := move_direction.normalized() if not move_direction.is_zero_approx() else -visuals.global_basis.z
	forward.y = 0.0
	var target := _find_aim_target(move_direction, aim_assist_range * magnetism, aim_assist_angle)
	if target == null:
		return
	var best_offset: Vector3 = target.global_position - global_position
	best_offset.y = 0.0
	var desired_yaw := atan2(-best_offset.x, -best_offset.z)
	var delta_yaw := wrapf(desired_yaw - visuals.rotation.y, -PI, PI)
	# Soft magnetism — no 180° snaps.
	visuals.rotation.y += clampf(delta_yaw, -max_magnet_yaw * magnetism, max_magnet_yaw * magnetism)
	var gap := best_offset.length() - 1.1
	var do_lunge := force_lunge or (gap > 0.35 and attack_kind == AttackKind.LUNGE)
	if do_lunge and lunge_time > 0.0:
		var close := clampf(gap, 0.0, LUNGE_MAX)
		lunge_velocity = best_offset.normalized() * minf(close / lunge_time, max_lunge_speed)


func _start_rage() -> void:
	rage_left = rage_duration
	_kick_camera(1.6)
	_sfx(&"rage", 2.0, 0.0)
	rage_changed.emit(rage, true)


func _update_vitals(delta: float) -> void:
	since_damage += delta
	grace_left = maxf(0.0, grace_left - delta)
	if hit_chain > 0:
		hit_chain_left -= delta
		if hit_chain_left <= 0.0:
			hit_chain = 0
			hit_chain_changed.emit(0)
	if state == State.DEAD:
		return
	if raging:
		rage_left = maxf(0.0, rage_left - delta)
		rage = RAGE_MAX * rage_left / rage_duration
		health += rage_regen_rate * delta
		rage_changed.emit(rage, raging)
	elif since_damage >= regen_delay:
		health += regen_rate * delta
	health = minf(health, max_health)
	_emit_health()


func _emit_health() -> void:
	var shown := ceili(health)
	if shown != _shown_health:
		_shown_health = shown
		health_changed.emit(shown, max_health)


func _update_hitbox_active() -> void:
	var move := _current_move()
	attack_hitbox.global_position = limbs[int(move.limb)].to_global(Vector3(0, -0.2, 0))
	var swing := _attack_time()
	var want_active := (
		state == State.ATTACK
		and state_time >= swing * move.startup
		and state_time < swing * move.active_end
	)
	if want_active and not attack_hitbox.active and _trail == null:
		_trail = SlashTrail.attach(limbs[int(move.limb)], move.strength)
	elif not want_active and _trail:
		_trail = null
	attack_hitbox.set_active(want_active)
	attack_hitbox.check_hits()


func _set_state(next_state: State, force: bool = false) -> void:
	if state == next_state and not force:
		return
	var leaving_attack := state == State.ATTACK and next_state != State.ATTACK
	var prev := state
	state = next_state
	state_time = 0.0
	attack_hitbox.set_active(false)
	if state == State.ATTACK:
		attack_hitbox.begin_swing(self, current_move)
		var whoosh := -2.0 if current_move and current_move.strength != CombatAttackData.Strength.LIGHT else -4.0
		_sfx(&"swing", whoosh)
	elif state == State.DODGE:
		_sfx(&"dodge", -3.0)
	elif leaving_attack and state != State.GRAB:
		if state != State.THROW and state != State.WALL_SLAM and state != State.FINISHER:
			heavy_attack = false
			combo_queued = false
			attack_kind = AttackKind.NONE
	animator.speed_scale = 1.0
	var animation := _animation_for_state(state)
	if not animator.has_animation(animation):
		animation = &"idle"
	var length := animator.get_animation(animation).length
	var playback_speed := 1.0
	match state:
		State.DODGE:
			playback_speed = length / dodge_duration
		State.ATTACK:
			var bias := current_move.playback_bias if current_move else 1.0
			playback_speed = (length / _attack_time()) * bias
		State.HURT:
			playback_speed = length / maxf(0.08, _hurt_play_duration)
		State.DEAD:
			playback_speed = length / 0.6
		State.GRAB:
			playback_speed = 1.0
		State.THROW:
			playback_speed = length / 0.45
		State.WALL_SLAM:
			playback_speed = length / 1.0
		State.FINISHER:
			playback_speed = length / maxf(0.2, attack_duration * current_move.time)
		State.IDLE, State.RUN:
			playback_speed = 1.0
	var blend := 0.12
	if state == State.DODGE or state == State.ATTACK or state == State.HURT:
		blend = 0.04
	elif _is_locked_interaction():
		blend = 0.06
	elif prev == State.DODGE or prev == State.ATTACK or prev == State.HURT:
		blend = 0.1
	animator.play(animation, blend, playback_speed)
	if force and animator.current_animation == animation:
		animator.seek(0.0, true)
	if state == State.IDLE or state == State.RUN:
		_loco_anim = animation
	print(State.keys()[state])


func _animation_for_state(s: State) -> StringName:
	match s:
		State.IDLE:
			return &"idle"
		State.RUN:
			return _loco_anim if _loco_anim == &"walk" or _loco_anim == &"sprint" else &"sprint"
		State.DODGE:
			return _dodge_animation_name()
		State.ATTACK:
			return current_move.animation if current_move else &"attack-melee-right"
		State.HURT:
			return _hurt_animation_name()
		State.DEAD:
			return &"die"
		State.GRAB:
			return &"actions/grab_hold"
		State.THROW:
			return &"actions/throw"
		State.WALL_SLAM:
			return &"actions/wall_slam"
		State.FINISHER:
			return &"actions/finisher"
	return &"idle"


func _dodge_animation_name() -> StringName:
	var local := visuals.global_basis.inverse() * dodge_direction
	local.y = 0.0
	return CharacterAnimLib.dodge_name(local)


func _hurt_animation_name() -> StringName:
	var local := visuals.global_basis.inverse() * _last_hurt_dir
	local.y = 0.0
	var heavy := _last_hurt_dir.length() > 5.5
	return CharacterAnimLib.hit_name(local, heavy)


func _update_locomotion_anim(delta: float) -> void:
	var ground_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	var run_threshold := 0.08 if state == State.RUN else 0.14
	var next_state := State.RUN if ground_speed > run_threshold else State.IDLE
	if next_state != state:
		_set_state(next_state)
		return
	if state == State.IDLE:
		animator.speed_scale = 1.0
		_footstep_left = 0.0
		return
	# Match clip playback to horizontal speed to reduce foot sliding.
	var want: StringName = &"walk" if ground_speed < walk_anim_threshold else &"sprint"
	if not animator.has_animation(want):
		want = &"sprint"
	var ref_speed := move_speed * (0.45 if want == &"walk" else 1.0)
	animator.speed_scale = clampf(ground_speed / maxf(0.35, ref_speed), 0.35, 1.35)
	if want != _loco_anim or animator.current_animation != want:
		_loco_anim = want
		animator.play(want, 0.14, animator.speed_scale)
	_footstep_left -= delta
	if _footstep_left <= 0.0 and ground_speed > 0.4:
		_sfx(&"footstep", -10.0, 0.1)
		_footstep_left = footstep_interval * clampf(move_speed / maxf(ground_speed, 0.5), 0.55, 1.4)


func _update_finisher_camera(delta: float) -> void:
	if state == State.FINISHER:
		_finisher_cam_blend = move_toward(_finisher_cam_blend, 1.0, delta * 3.5)
	else:
		_finisher_cam_blend = move_toward(_finisher_cam_blend, 0.0, delta * 4.5)
	# Closer boom; SpringArm3D collision keeps the lens out of walls.
	spring_arm.spring_length = lerpf(5.0, 3.55, _finisher_cam_blend)


func _on_hurt(event: HitEvent) -> void:
	if state == State.DEAD or _locked_iframes:
		return
	_release_grab(false)
	health = maxf(0.0, health - event.damage)
	since_damage = 0.0
	_hurt_play_duration = clampf(0.16 + event.knockback * 0.025, 0.14, 0.32)
	grace_left = _hurt_play_duration + hurt_grace
	combo_queued = false
	heavy_attack = false
	attack_kind = AttackKind.NONE
	lunge_velocity = Vector3.ZERO
	hit_stop_left = maxf(hit_stop_left, event.hit_stop)
	_kick_camera(2.4)
	_rumble(0.5, 0.7, 0.2)
	_sfx(&"hurt")
	hurt.emit(event.damage)
	_emit_health()
	var away: Vector3 = global_position - event.source_position
	away.y = 0.0
	away = away.normalized()
	if health <= 0.0:
		rage_left = 0.0
		rage_changed.emit(rage, false)
		_set_state(State.DEAD)
		died.emit()
		return
	knockback_velocity = Vector2(away.x, away.z) * event.knockback
	_last_hurt_dir = away * maxf(event.knockback, 1.0)
	if not away.is_zero_approx():
		visuals.rotation.y = atan2(away.x, away.z)
	_set_state(State.HURT, true)


func _input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("attack")
		or event.is_action_pressed("attack_heavy")
		or event.is_action_pressed("dodge")
		or event.is_action_pressed("grab")
	):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			_attack_device = event.device


func _on_hit_landed(contact_position: Vector3) -> void:
	var move: CombatAttackData = current_move
	var strength: int = move.strength if move else CombatAttackData.Strength.LIGHT
	var event: HitEvent = attack_hitbox.last_hit_event
	hit_stop_left = attack_hitbox.hit_stop_duration
	_kick_camera(move.camera_impulse if move else 1.0)
	var impact := HIT_IMPACT.instantiate()
	impact.size = 1.8 if strength != CombatAttackData.Strength.LIGHT else 1.0
	if strength == CombatAttackData.Strength.FINISHER:
		impact.size = 2.4
	get_tree().current_scene.add_child(impact)
	impact.global_position = contact_position
	var blood: int = move.blood_tier if move else CombatAttackData.BloodTier.LIGHT_FLESH
	if event:
		blood = event.blood_tier
	BloodFx.spawn(get_tree(), contact_position, -visuals.global_basis.z, blood)
	match strength:
		CombatAttackData.Strength.FINISHER:
			_sfx(&"finisher_hit")
		CombatAttackData.Strength.HEAVY, CombatAttackData.Strength.COUNTER:
			_sfx(&"heavy_hit")
		_:
			_sfx(&"hit" if combo_step < 2 else &"heavy_hit")
	if move:
		_rumble(move.rumble_weak, move.rumble_strong, move.rumble_duration)
	hit_chain += 1
	hit_chain_left = 2.0
	hit_chain_changed.emit(hit_chain)
	add_rage(rage_per_hit)
	if move and move.kill_slow_mo > 0.0:
		_check_kill_slow_mo.call_deferred(contact_position, move.kill_slow_mo, strength)


func _check_kill_slow_mo(contact: Vector3, duration: float, _strength: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for body in scene.find_children("*", "CharacterBody3D", true, false):
		if body == self or not is_instance_valid(body):
			continue
		if body.global_position.distance_to(contact) > 2.5:
			continue
		if body.get("is_alive") == false:
			CombatSlowMo.request(get_tree(), duration, 0.22)
			return
		var hp: Variant = body.get("health")
		if hp is int and int(hp) <= 0:
			CombatSlowMo.request(get_tree(), duration, 0.22)
			return


func _rumble(weak: float, strong: float, duration: float) -> void:
	if _attack_device in Input.get_connected_joypads() and Input.has_joy_vibration(_attack_device):
		_rumble_device = _attack_device
		Input.start_joy_vibration(_rumble_device, weak, strong, duration)


func _kick_camera(scale: float) -> void:
	camera_impulse_left = camera_impulse_duration
	_impulse_scale = scale


func _sfx(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, volume_db, pitch_jitter)


func _update_debug_label() -> void:
	if _debug_label == null:
		return
	var parts: PackedStringArray = []
	if DebugCombat.state_label:
		parts.append(State.keys()[state])
		parts.append(AttackKind.keys()[attack_kind])
	if DebugCombat.combo_label:
		parts.append("c%d%s" % [combo_step, "Q" if combo_queued else ""])
	_debug_label.text = " ".join(parts)


func _update_context_prompt() -> void:
	var next := ""
	if state == State.GRAB:
		next = "RT - STAB   RB - THROW"
	elif state == State.IDLE or state == State.RUN:
		var target := _best_grab_target()
		if target != null:
			if _finisher_eligible(target):
				next = "LT - FINISH"
				_offer_tutorial(&"finisher_prompt", "LT - Finish vulnerable enemy")
			elif _grab_eligible(target):
				next = "LT - GRAB"
				_offer_tutorial(&"grab_prompt", "LT - Grab nearby enemy")
	if next != _context_prompt:
		_context_prompt = next
		context_prompt_changed.emit(_context_prompt)


func _offer_tutorial(id: StringName, text: String) -> void:
	if _tutorials_shown.get(id, false):
		return
	_tutorials_shown[id] = true
	tutorial_requested.emit(text)


func _process(delta: float) -> void:
	camera_impulse_left = maxf(0.0, camera_impulse_left - delta)
	var elapsed := camera_impulse_duration - camera_impulse_left
	var strength := camera_impulse_strength * _impulse_scale * pow(camera_impulse_left / camera_impulse_duration, 2.0)
	var side_boom := _finisher_cam_yaw * 0.6 * _finisher_cam_blend
	camera.h_offset = sin(elapsed * 90.0) * strength + side_boom
	camera.v_offset = cos(elapsed * 70.0) * strength * 0.65 + 0.12 * _finisher_cam_blend
	var target_fov := _fov_base + _fov_punch - 6.0 * _finisher_cam_blend
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-8.0 * delta))
	if raging:
		_overlay.albedo_color = Color(1.0, 0.12, 0.05, 0.28 + 0.1 * sin(Time.get_ticks_msec() * 0.02))
	elif grace_left > 0.0 and state != State.DEAD:
		_overlay.albedo_color = Color(1, 1, 1, 0.45 if fmod(grace_left, 0.12) > 0.06 else 0.0)
	elif health / max_health < 0.35:
		_overlay.albedo_color = Color(0.7, 0.05, 0.05, 0.12)
	else:
		_overlay.albedo_color = Color(1, 1, 1, 0)


func _exit_tree() -> void:
	_release_grab(false)
	Engine.time_scale = 1.0
	if _rumble_device in Input.get_connected_joypads():
		Input.stop_joy_vibration(_rumble_device)
