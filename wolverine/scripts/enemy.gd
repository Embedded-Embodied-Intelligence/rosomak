class_name Enemy
extends CharacterBody3D

## A melee brawler: chase, telegraphed windup, strike, recover. Variants (grunt, runner,
## brute) are inherited scenes that only override the exported numbers below.
## StaggerComponent fields live on the enemy for grab resist / finisher eligibility.

signal died(enemy: Enemy)

const CharacterAnimLib := preload("res://scripts/combat/character_anim.gd")

enum State { SPAWN, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD, CHEER, GRABBED, THROWN }
enum DeathStyle { COLLAPSE, KNOCKDOWN, LAUNCH, WALL, FINISHER }

const HEALTH_BAR_SHADER := preload("res://shaders/health_bar.gdshader")
const SPAWN_TIME := 0.7
const CORPSE_TIME := 1.4

static var max_attackers: int = 2
static var attackers: int = 0

@export_group("Body")
@export var max_health: int = 60
@export var body_scale: float = 1.0
@export var body_color := Color(0.85, 0.34, 0.12)
@export var move_speed: float = 3.0
@export var move_animation: StringName = &"walk"
@export var move_animation_speed: float = 2.5
@export var turn_speed: float = 10.0
## Hits dealing less damage than this only flinch (legacy armor gate).
@export var poise: int = 0
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0
@export var stagger_duration: float = 0.35
## StaggerComponent: build toward threshold; heavies resist light stagger/grab.
@export var stagger_threshold: float = 40.0
@export var stagger_resist: float = 0.0
@export var is_heavy: bool = false
@export var grab_resist_unless_staggered: bool = false

@export_group("Attack")
@export var attack_range: float = 1.5
@export var attack_damage: int = 12
@export var attack_knockback: float = 4.0
@export var attack_animation: StringName = &"attack-melee-right"
@export var attack_limb: StringName = &"arm-right"
@export var windup_time: float = 0.55
@export var strike_time: float = 0.3
@export var recover_time: float = 0.55
@export var lunge_speed: float = 3.5
@export var cooldown_range := Vector2(0.5, 1.4)

var state: State = State.SPAWN
var state_time: float = 0.0
var health: int
var hit_stop_left: float = 0.0
var knockback_velocity := Vector2.ZERO
var attack_cooldown: float = 0.0
var target: Node3D
var stagger_build: float = 0.0
var _has_slot: bool = false
var _strafe_sign: float = 1.0
var _flash: float = 0.0
var _grabber: Node3D
var _throw_velocity := Vector3.ZERO
var _wall_bonus_used: bool = false
var _death_style: DeathStyle = DeathStyle.COLLAPSE
var _last_hit_strength: int = CombatAttackData.Strength.LIGHT
var _last_hit_away := Vector3.FORWARD
var _overlay := StandardMaterial3D.new()
var _bar_material := ShaderMaterial.new()
var _bar: MeshInstance3D
var _debug_label: Label3D

var is_alive: bool:
	get:
		return state != State.DEAD

@onready var visuals: Node3D = $Visuals
@onready var animator: AnimationPlayer = $Visuals/Humanoid/AnimationPlayer
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: MeleeHitbox = $AttackHitbox
@onready var limb: Node3D = $Visuals/Humanoid.find_child(attack_limb, true, false)


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	if grab_resist_unless_staggered == false and (is_heavy or poise >= 25):
		grab_resist_unless_staggered = true
	if is_heavy and stagger_resist <= 0.0:
		stagger_resist = 0.55
	if is_heavy and stagger_threshold < 70.0:
		stagger_threshold = 85.0
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	target = get_tree().get_first_node_in_group("player")
	hurtbox.enabled = false
	hurtbox.hit_received.connect(_receive_hit)
	attack_hitbox.damage = attack_damage
	attack_hitbox.knockback = attack_knockback
	attack_hitbox.hit_stop_duration = 0.06
	_apply_body_scale()
	_setup_materials()
	_setup_health_bar()

	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if animator.has_animation_library(&"reactions"):
		animator.remove_animation_library(&"reactions")
	animator.add_animation_library(&"reactions", CharacterAnimLib.build_reactions())
	animator.get_animation(&"walk").loop_mode = Animation.LOOP_LINEAR
	animator.get_animation(&"emote-yes").loop_mode = Animation.LOOP_LINEAR
	if animator.has_animation(&"sprint"):
		animator.get_animation(&"sprint").loop_mode = Animation.LOOP_LINEAR
	animator.play(&"idle")
	visuals.scale = Vector3.ONE * body_scale * 0.2
	_face(_to_target(), 1.0)
	_apply_variant_silhouette()
	if DebugCombat.stagger_label:
		_debug_label = Label3D.new()
		_debug_label.position = Vector3(0, 2.4 * body_scale, 0)
		_debug_label.font_size = 22
		add_child(_debug_label)


func _apply_body_scale() -> void:
	var body := ($CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	body.radius *= body_scale
	body.height *= body_scale
	$CollisionShape3D.shape = body
	$CollisionShape3D.position.y *= body_scale
	var hurt := ($Hurtbox/CollisionShape3D.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	hurt.radius *= body_scale
	hurt.height *= body_scale
	$Hurtbox/CollisionShape3D.shape = hurt
	hurtbox.position.y *= body_scale
	var reach := ($AttackHitbox/CollisionShape3D.shape as SphereShape3D).duplicate() as SphereShape3D
	reach.radius *= body_scale
	$AttackHitbox/CollisionShape3D.shape = reach


func _setup_materials() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 0.85 if is_heavy else 0.95
	material.metallic = 0.18 if is_heavy else 0.02
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for mesh in $Visuals/Humanoid.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.material_overlay = _overlay


func _setup_health_bar() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.1) * maxf(1.0, body_scale)
	_bar_material.shader = HEALTH_BAR_SHADER
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = _bar_material
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.position.y = 2.15 * body_scale
	_bar.visible = false
	add_child(_bar)


func can_be_grabbed() -> bool:
	if state == State.DEAD or state == State.SPAWN or state == State.GRABBED:
		return false
	if grab_resist_unless_staggered or is_heavy:
		return state == State.STAGGER or stagger_build >= stagger_threshold * 0.7
	# Lights: allow grab outside active strike frames for reliability.
	return state != State.STRIKE


func is_staggered() -> bool:
	return state == State.STAGGER


func is_finisher_ready() -> bool:
	if state == State.DEAD or state == State.SPAWN:
		return false
	if float(health) / float(max_health) <= 0.35:
		return true
	if stagger_build >= stagger_threshold * 0.85 and (state == State.STAGGER or state == State.RECOVER):
		return true
	if is_heavy and health <= int(max_health * 0.45) and state == State.STAGGER:
		return true
	return false


func enter_grabbed(grabber: Node3D) -> void:
	_grabber = grabber
	_release_slot()
	attack_hitbox.set_active(false)
	state = State.GRABBED
	state_time = 0.0
	knockback_velocity = Vector2.ZERO
	_throw_velocity = Vector3.ZERO
	var hold := &"reactions/stagger" if animator.has_animation(&"reactions/stagger") else &"reactions/hit"
	animator.play(hold, 0.05, 0.12)
	hurtbox.enabled = true


func exit_grabbed(_killed: bool) -> void:
	_grabber = null
	if state == State.DEAD:
		return
	if state == State.GRABBED or state == State.THROWN:
		if health <= 0:
			_die(Vector2.ZERO)
		else:
			_enter(State.STAGGER)


func receive_throw(velocity_xz: Vector3, _thrower: Node3D) -> void:
	_grabber = null
	_wall_bonus_used = false
	_throw_velocity = velocity_xz
	_throw_velocity.y = 2.5
	state = State.THROWN
	state_time = 0.0
	attack_hitbox.set_active(false)
	animator.play(&"reactions/hit", 0.03, 0.5)
	_sfx(&"throw", -4.0)


func _physics_process(delta: float) -> void:
	var stopped := hit_stop_left > 0.0 and state != State.THROWN
	hit_stop_left = maxf(0.0, hit_stop_left - delta)
	var desired := Vector3.ZERO
	if not stopped:
		state_time += delta
		attack_cooldown = maxf(0.0, attack_cooldown - delta)
		desired = _think(delta)
	var horizontal := Vector2.ZERO if stopped else Vector2(desired.x, desired.z) + knockback_velocity
	if state == State.THROWN:
		horizontal = Vector2(_throw_velocity.x, _throw_velocity.z)
		velocity.y = _throw_velocity.y
		_throw_velocity.y += get_gravity().y * delta
		_throw_velocity.x = move_toward(_throw_velocity.x, 0.0, 8.0 * delta)
		_throw_velocity.z = move_toward(_throw_velocity.z, 0.0, 8.0 * delta)
		_check_wall_impact()
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if state != State.THROWN and not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if not stopped:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 12.0 * delta)
		if state == State.CHASE:
			var ground_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
			animator.speed_scale = clampf(ground_speed / maxf(0.5, move_animation_speed), 0.45, 1.6)
		animator.advance(delta)

	if state != State.GRABBED and state != State.THROWN:
		attack_hitbox.global_position = limb.to_global(Vector3(0, -0.2, 0))
		attack_hitbox.set_active(
			state == State.STRIKE and state_time >= strike_time * 0.1 and state_time < strike_time * 0.65
		)
		attack_hitbox.check_hits()
	_update_overlay(delta)
	if _debug_label:
		_debug_label.text = "stg %.0f/%0.f" % [stagger_build, stagger_threshold]


func _check_wall_impact() -> void:
	if _wall_bonus_used or state != State.THROWN:
		return
	if get_slide_collision_count() <= 0:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is StaticBody3D or col.get_collider() is CSGShape3D:
			_wall_bonus_used = true
			var event := HitEvent.legacy(28, global_position - col.get_normal(), 0.12, 3.2)
			event.attack_strength = CombatAttackData.Strength.HEAVY
			event.blood_tier = CombatAttackData.BloodTier.WALL
			event.source_move_id = &"wall_throw"
			event.stagger_bonus = 60.0
			_apply_damage_only(event)
			BloodFx.spawn(get_tree(), global_position + Vector3.UP * 0.9, col.get_normal(), CombatAttackData.BloodTier.WALL)
			BloodFx.spawn(get_tree(), global_position + Vector3.UP * 0.5, -col.get_normal(), CombatAttackData.BloodTier.HEAVY_FLESH)
			_sfx(&"wall_impact", 0.0)
			stagger_build = stagger_threshold
			if health <= 0:
				_death_style = DeathStyle.WALL
				_die(Vector2(-col.get_normal().x, -col.get_normal().z) * 5.0)
			else:
				_enter(State.STAGGER)
			_throw_velocity = Vector3.ZERO
			return


func _think(delta: float) -> Vector3:
	if state == State.GRABBED:
		return Vector3.ZERO
	if state == State.THROWN:
		if state_time >= 0.85 or (is_on_floor() and state_time > 0.25 and _throw_velocity.length() < 2.0):
			if health <= 0:
				_die(Vector2(_throw_velocity.x, _throw_velocity.z))
			else:
				_enter(State.STAGGER)
		return Vector3.ZERO
	var to_target := _to_target()
	var distance := to_target.length()
	match state:
		State.SPAWN:
			var progress := clampf(state_time / SPAWN_TIME, 0.0, 1.0)
			visuals.scale = Vector3.ONE * body_scale * lerpf(0.2, 1.0, ease(progress, 0.4))
			_face(to_target, delta)
			if progress >= 1.0:
				hurtbox.enabled = true
				_enter(State.CHASE)
		State.CHASE:
			if not _target_alive():
				_enter(State.CHEER)
				return Vector3.ZERO
			if distance <= attack_range and attack_cooldown <= 0.0 and _claim_slot():
				_enter(State.WINDUP)
				return Vector3.ZERO
			var direction := to_target / distance if distance > 0.01 else Vector3.ZERO
			var speed := move_speed
			if distance < attack_range + 1.4:
				var tangent := Vector3(-direction.z, 0.0, direction.x) * _strafe_sign
				var spacing := clampf(distance - (attack_range + 0.7), -1.0, 1.0)
				direction = tangent * 0.8 + direction * spacing
				speed *= 0.5
			direction += _separation()
			_face(to_target, delta)
			return direction.limit_length(1.0) * speed
		State.WINDUP:
			_face(to_target, delta)
			if state_time >= windup_time:
				_enter(State.STRIKE)
		State.STRIKE:
			if state_time >= strike_time:
				_enter(State.RECOVER)
			elif state_time < 0.12 and distance > 1.0:
				return _forward() * lunge_speed
		State.RECOVER:
			if state_time >= recover_time:
				_enter(State.CHASE)
		State.STAGGER:
			stagger_build = maxf(0.0, stagger_build - delta * 12.0)
			if state_time >= stagger_duration:
				_enter(State.CHASE)
		State.DEAD:
			if state_time >= CORPSE_TIME:
				queue_free()
			elif state_time > CORPSE_TIME - 0.45:
				var shrink := (CORPSE_TIME - state_time) / 0.45
				visuals.scale = Vector3.ONE * body_scale * shrink
		State.CHEER:
			if _target_alive():
				_enter(State.CHASE)
	return Vector3.ZERO


func _enter(next_state: State) -> void:
	if next_state != State.WINDUP and next_state != State.STRIKE:
		_release_slot()
	state = next_state
	state_time = 0.0
	animator.speed_scale = 1.0
	attack_hitbox.set_active(false)
	match state:
		State.CHASE:
			animator.play(move_animation, 0.15)
		State.WINDUP:
			animator.play(attack_animation, 0.12)
			# Stretch the early portion of the clip for readable anticipation.
			animator.speed_scale = animator.get_animation(attack_animation).length * 0.35 / windup_time
			_sfx(&"telegraph", -8.0)
		State.STRIKE:
			attack_hitbox.begin_swing(self)
			animator.speed_scale = animator.get_animation(attack_animation).length * 0.55 / strike_time
			animator.seek(animator.get_animation(attack_animation).length * 0.35, true)
			_sfx(&"swing", -9.0)
		State.RECOVER:
			attack_cooldown = randf_range(cooldown_range.x, cooldown_range.y)
			animator.play(&"idle", 0.2)
		State.STAGGER:
			var react := &"reactions/stagger" if animator.has_animation(&"reactions/stagger") else &"reactions/hit"
			animator.play(react, 0.04, animator.get_animation(react).length / maxf(0.12, stagger_duration))
			animator.seek(0.0, true)
		State.CHEER:
			animator.play(&"emote-yes", 0.3)


func _receive_hit(event: HitEvent) -> void:
	if state == State.DEAD or state == State.SPAWN:
		return
	if state == State.GRABBED and event.source_move_id != &"grab_stab" and event.attack_strength != CombatAttackData.Strength.FINISHER:
		# Only grab stab / finisher damage while locked, unless wall.
		if event.source_move_id != &"wall_slam":
			pass
	_last_hit_strength = event.attack_strength
	_apply_damage_only(event)
	_add_stagger(event)
	hit_stop_left = maxf(hit_stop_left, event.hit_stop)
	var away := event.direction
	if away.is_zero_approx():
		away = global_position - event.source_position
		away.y = 0.0
		away = away.normalized()
	var resist := knockback_resistance
	if is_heavy and event.attack_strength == CombatAttackData.Strength.LIGHT:
		resist = maxf(resist, 0.7)
	var push := Vector2(away.x, away.z) * event.knockback * (1.0 - resist)
	if health <= 0:
		_pick_death_style(event, push)
		_die(push)
		return
	# Heavy armor: light hits flinch without full interrupt until stagger breaks.
	var armored := is_heavy or poise > 0
	var light := event.attack_strength == CombatAttackData.Strength.LIGHT
	if armored and light and event.damage < maxi(poise, 1) and stagger_build < stagger_threshold:
		knockback_velocity += push * 0.25
		_flash = 1.0
		return
	if state == State.GRABBED:
		_flash = 1.0
		return
	knockback_velocity = push
	if not away.is_zero_approx():
		visuals.rotation.y = atan2(away.x, away.z)
	_last_hit_away = away
	_enter(State.STAGGER)
	_play_hit_reaction(away, event.attack_strength != CombatAttackData.Strength.LIGHT)


func _apply_damage_only(event: HitEvent) -> void:
	health = maxi(0, health - event.damage)
	_flash = 1.0
	_bar.visible = true
	_bar_material.set_shader_parameter(&"fill", float(health) / max_health)


func _add_stagger(event: HitEvent) -> void:
	var amount := event.stagger_bonus + float(event.damage) * 0.35
	amount *= 1.0 - stagger_resist
	if event.attack_strength == CombatAttackData.Strength.LIGHT and is_heavy:
		amount *= 0.45
	stagger_build = minf(stagger_threshold * 1.25, stagger_build + amount)


func _pick_death_style(event: HitEvent, push: Vector2) -> void:
	if event.attack_strength == CombatAttackData.Strength.FINISHER or event.source_move_id == &"signature_finisher":
		_death_style = DeathStyle.FINISHER
	elif event.blood_tier == CombatAttackData.BloodTier.WALL or event.source_move_id == &"wall_slam":
		_death_style = DeathStyle.WALL
	elif event.attack_strength == CombatAttackData.Strength.HEAVY and push.length() > 4.0:
		_death_style = DeathStyle.LAUNCH
	elif push.length() > 2.5:
		_death_style = DeathStyle.KNOCKDOWN
	else:
		_death_style = DeathStyle.COLLAPSE


func _die(push: Vector2) -> void:
	_release_slot()
	_grabber = null
	state = State.DEAD
	state_time = 0.0
	remove_from_group("enemies")
	hurtbox.disable()
	attack_hitbox.set_active(false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	match _death_style:
		DeathStyle.LAUNCH:
			knockback_velocity = push * 2.2
			if animator.has_animation(&"reactions/death_launch"):
				animator.play(&"reactions/death_launch", 0.03, 1.0)
			else:
				animator.play(&"die", 0.04, animator.get_animation(&"die").length / 0.45)
		DeathStyle.WALL, DeathStyle.FINISHER:
			knockback_velocity = push * 0.4
			animator.play(&"die", 0.02, animator.get_animation(&"die").length / 0.75)
			BloodFx.spawn(get_tree(), global_position + Vector3.UP, Vector3.UP, CombatAttackData.BloodTier.DEATH)
		DeathStyle.KNOCKDOWN:
			knockback_velocity = push * 1.8
			animator.play(&"die", 0.04, animator.get_animation(&"die").length / 0.5)
		_:
			knockback_velocity = push * 1.2
			animator.play(&"die", 0.05, animator.get_animation(&"die").length / 0.55)
	_bar.visible = false
	animator.speed_scale = 1.0
	_sfx(&"enemy_die", -2.0)
	died.emit(self)


func _sfx(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, volume_db, pitch_jitter)


func _update_overlay(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 8.0)
	var color := Color(1, 1, 1, 0)
	if state == State.SPAWN:
		color = Color(1.0, 0.5, 0.2, 1.0 - state_time / SPAWN_TIME)
	elif state == State.WINDUP:
		var progress := state_time / windup_time
		var pulse := 0.5 + 0.5 * sin(state_time * lerpf(18.0, 40.0, progress))
		color = Color(1.0, 0.85, 0.2, lerpf(0.15, 0.65, progress) * pulse + 0.1)
	if _flash > 0.0:
		color = Color(1, 1, 1, _flash * 0.8)
	_overlay.albedo_color = color


func _to_target() -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset


func _target_alive() -> bool:
	return is_instance_valid(target) and target.get(&"is_alive") == true


func _forward() -> Vector3:
	var forward := -visuals.global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _face(direction: Vector3, delta: float) -> void:
	if direction.is_zero_approx():
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.001 and distance < 1.6:
			push += offset / distance * (1.6 - distance) / 1.6
	return push


func _claim_slot() -> bool:
	if _has_slot:
		return true
	if attackers >= max_attackers:
		return false
	attackers += 1
	_has_slot = true
	return true


func _release_slot() -> void:
	if _has_slot:
		attackers -= 1
		_has_slot = false


func _play_hit_reaction(away: Vector3, heavy: bool) -> void:
	var local := visuals.global_basis.inverse() * away
	local.y = 0.0
	var anim := CharacterAnimLib.hit_name(local, heavy)
	if not animator.has_animation(anim):
		anim = &"reactions/hit"
	var length := animator.get_animation(anim).length
	animator.play(anim, 0.03, length / maxf(0.12, stagger_duration))
	animator.seek(0.0, true)


func _apply_variant_silhouette() -> void:
	## Cheap silhouette props — no cloth/IK. Differentiates light / standard / heavy.
	if visuals.get_node_or_null("SilhouetteProps"):
		return
	var props := Node3D.new()
	props.name = "SilhouetteProps"
	visuals.add_child(props)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color.darkened(0.25)
	mat.roughness = 0.7
	mat.metallic = 0.25 if is_heavy else 0.05
	if is_heavy or body_scale >= 1.2:
		for side in [-1.0, 1.0]:
			var pad := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.14, 0.28)
			pad.mesh = box
			pad.material_override = mat
			pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pad.position = Vector3(side * 0.38, 1.35, 0.05)
			props.add_child(pad)
		var helm := MeshInstance3D.new()
		var helm_mesh := BoxMesh.new()
		helm_mesh.size = Vector3(0.36, 0.16, 0.38)
		helm.mesh = helm_mesh
		helm.material_override = mat
		helm.position = Vector3(0.0, 1.72, 0.02)
		props.add_child(helm)
	elif body_scale <= 0.9:
		var pack := MeshInstance3D.new()
		var pack_mesh := BoxMesh.new()
		pack_mesh.size = Vector3(0.28, 0.32, 0.14)
		pack.mesh = pack_mesh
		pack.material_override = mat
		pack.position = Vector3(0.0, 1.15, -0.22)
		props.add_child(pack)
		var ant := MeshInstance3D.new()
		var ant_mesh := BoxMesh.new()
		ant_mesh.size = Vector3(0.04, 0.28, 0.04)
		ant.mesh = ant_mesh
		ant.material_override = mat
		ant.position = Vector3(0.1, 1.7, -0.05)
		props.add_child(ant)
	else:
		var vest := MeshInstance3D.new()
		var vest_mesh := BoxMesh.new()
		vest_mesh.size = Vector3(0.42, 0.36, 0.12)
		vest.mesh = vest_mesh
		vest.material_override = mat
		vest.position = Vector3(0.0, 1.15, 0.16)
		props.add_child(vest)


func _exit_tree() -> void:
	_release_slot()
	# Softlock safeguard: living enemies freed without _die still notify directors.
	if state != State.DEAD:
		state = State.DEAD
		died.emit(self)
