class_name BloodFx
extends RefCounted

## Lightweight blood/impact library: particles + capped decal pool + sound hooks.
## No fluid sim. Max ~48 decals. Call spawn() from hit confirmation.

const MAX_DECALS := 48
const DECAL_LIFE := 10.0

enum Tier {
	LIGHT_FLESH,
	HEAVY_FLESH,
	WALL,
	DEATH,
	FINISHER,
}

static var _decal_pool: Array[MeshInstance3D] = []
static var _decal_ages: Array[float] = []
static var _host: Node


static func ensure_host(tree: SceneTree) -> void:
	if is_instance_valid(_host):
		return
	_host = tree.current_scene if tree.current_scene else tree.root
	if _host == null:
		return
	if not _host.has_meta(&"_blood_fx_tick"):
		_host.set_meta(&"_blood_fx_tick", true)
		var ticker := Node.new()
		ticker.name = "BloodFxTicker"
		ticker.set_script(load("res://scripts/combat/blood_fx_ticker.gd"))
		_host.add_child(ticker)


static func tier_from_combat(blood_tier: int) -> Tier:
	match blood_tier:
		CombatAttackData.BloodTier.HEAVY_FLESH:
			return Tier.HEAVY_FLESH
		CombatAttackData.BloodTier.WALL:
			return Tier.WALL
		CombatAttackData.BloodTier.DEATH:
			return Tier.DEATH
		CombatAttackData.BloodTier.FINISHER:
			return Tier.FINISHER
		_:
			return Tier.LIGHT_FLESH


static func spawn(tree: SceneTree, position: Vector3, direction: Vector3, blood_tier: int) -> void:
	if tree == null:
		return
	ensure_host(tree)
	var tier := tier_from_combat(blood_tier)
	_spawn_burst(tree, position, direction, tier)
	# Secondary mist burst for heavier tiers (still cheap one-shot particles).
	if tier == Tier.HEAVY_FLESH or tier == Tier.WALL or tier == Tier.DEATH or tier == Tier.FINISHER:
		_spawn_burst(tree, position + Vector3(0, 0.15, 0), direction.lerp(Vector3.UP, 0.35), tier)
		_spawn_decal(tree, position, direction, tier)
	elif tier == Tier.LIGHT_FLESH:
		_spawn_decal(tree, position, direction, tier)
	_sfx(tree, tier)


static func tick(delta: float) -> void:
	for i in range(_decal_pool.size() - 1, -1, -1):
		_decal_ages[i] += delta
		var mesh: MeshInstance3D = _decal_pool[i]
		if not is_instance_valid(mesh):
			_decal_pool.remove_at(i)
			_decal_ages.remove_at(i)
			continue
		var t := _decal_ages[i] / DECAL_LIFE
		if t >= 1.0:
			mesh.queue_free()
			_decal_pool.remove_at(i)
			_decal_ages.remove_at(i)
		elif t > 0.65:
			var mat := mesh.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = lerpf(0.7, 0.0, (t - 0.65) / 0.35)


static func _spawn_burst(tree: SceneTree, position: Vector3, direction: Vector3, tier: Tier) -> void:
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var particles := GPUParticles3D.new()
	particles.position = position
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = _lifetime(tier)
	particles.amount = _amount(tier)
	particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var mat := ParticleProcessMaterial.new()
	mat.direction = direction if not direction.is_zero_approx() else Vector3.UP
	mat.spread = _spread(tier)
	mat.initial_velocity_min = _vel_min(tier)
	mat.initial_velocity_max = _vel_max(tier)
	mat.gravity = Vector3(0, -14, 0)
	mat.scale_min = _scale_min(tier)
	mat.scale_max = _scale_max(tier)
	mat.color = Color(0.55, 0.04, 0.04)
	particles.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.05
	draw.height = 0.1
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(0.62, 0.05, 0.05)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.material = draw_mat
	particles.draw_pass_1 = draw
	parent.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


static func _spawn_decal(tree: SceneTree, position: Vector3, direction: Vector3, tier: Tier) -> void:
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	while _decal_pool.size() >= MAX_DECALS:
		var old: MeshInstance3D = _decal_pool.pop_front()
		_decal_ages.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(_decal_size(tier), _decal_size(tier))
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.38, 0.03, 0.03, 0.72)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	var flat := direction
	flat.y = 0.0
	if flat.is_zero_approx():
		flat = Vector3.FORWARD
	mesh.global_position = position + Vector3(0, 0.02, 0)
	mesh.look_at(mesh.global_position + Vector3.UP, flat.normalized())
	_decal_pool.append(mesh)
	_decal_ages.append(0.0)


static func _amount(tier: Tier) -> int:
	match tier:
		Tier.LIGHT_FLESH:
			return 16
		Tier.HEAVY_FLESH:
			return 28
		Tier.WALL:
			return 26
		Tier.DEATH:
			return 34
		Tier.FINISHER:
			return 48
	return 16


static func _lifetime(tier: Tier) -> float:
	match tier:
		Tier.FINISHER:
			return 0.7
		Tier.DEATH, Tier.WALL:
			return 0.55
		Tier.HEAVY_FLESH:
			return 0.48
		_:
			return 0.4


static func _spread(tier: Tier) -> float:
	match tier:
		Tier.FINISHER:
			return 85.0
		Tier.WALL:
			return 55.0
		Tier.HEAVY_FLESH, Tier.DEATH:
			return 62.0
		_:
			return 42.0


static func _vel_min(tier: Tier) -> float:
	return 2.2 if tier == Tier.LIGHT_FLESH else 3.0


static func _vel_max(tier: Tier) -> float:
	match tier:
		Tier.FINISHER:
			return 11.0
		Tier.HEAVY_FLESH, Tier.WALL, Tier.DEATH:
			return 9.0
		_:
			return 5.5


static func _scale_min(tier: Tier) -> float:
	return 0.04 if tier == Tier.LIGHT_FLESH else 0.055


static func _scale_max(tier: Tier) -> float:
	match tier:
		Tier.FINISHER:
			return 0.2
		Tier.HEAVY_FLESH, Tier.WALL, Tier.DEATH:
			return 0.16
		_:
			return 0.1


static func _decal_size(tier: Tier) -> float:
	match tier:
		Tier.FINISHER:
			return 1.05
		Tier.DEATH:
			return 0.85
		Tier.WALL:
			return 0.75
		Tier.HEAVY_FLESH:
			return 0.6
		_:
			return 0.4


static func _sfx(tree: SceneTree, tier: Tier) -> void:
	var bus := tree.root.get_node_or_null("Sfx")
	if bus == null or not bus.has_method("play"):
		return
	match tier:
		Tier.FINISHER:
			bus.play(&"finisher_hit", -1.0, 0.04)
		Tier.DEATH, Tier.HEAVY_FLESH:
			bus.play(&"heavy_hit", -2.0, 0.05)
		Tier.WALL:
			bus.play(&"wall_impact", -3.0, 0.05)
		_:
			bus.play(&"flesh_hit", -4.0, 0.08)
