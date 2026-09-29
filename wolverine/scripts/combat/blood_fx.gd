class_name BloodFx
extends RefCounted

## Lightweight blood/impact library: particles + capped decal pool + sound hooks.
## No fluid sim. Max ~32 decals. Call spawn() from hit confirmation.

const MAX_DECALS := 32
const DECAL_LIFE := 8.0

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
	if tier == Tier.HEAVY_FLESH or tier == Tier.WALL or tier == Tier.DEATH or tier == Tier.FINISHER:
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
		elif t > 0.7:
			var mat := mesh.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = lerpf(0.55, 0.0, (t - 0.7) / 0.3)


static func _spawn_burst(tree: SceneTree, position: Vector3, direction: Vector3, tier: Tier) -> void:
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var particles := GPUParticles3D.new()
	particles.position = position
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.lifetime = 0.35 if tier != Tier.FINISHER else 0.55
	particles.amount = _amount(tier)
	particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var mat := ParticleProcessMaterial.new()
	mat.direction = direction if not direction.is_zero_approx() else Vector3.UP
	mat.spread = 48.0 if tier != Tier.FINISHER else 70.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.5 if tier == Tier.LIGHT_FLESH else 7.5
	mat.gravity = Vector3(0, -12, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08 if tier == Tier.LIGHT_FLESH else 0.12
	mat.color = Color(0.45, 0.05, 0.05)
	particles.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.04
	draw.height = 0.08
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(0.55, 0.06, 0.06)
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
	var size := 0.35 if tier == Tier.HEAVY_FLESH else 0.55
	if tier == Tier.FINISHER:
		size = 0.7
	quad.size = Vector2(size, size)
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.35, 0.04, 0.04, 0.55)
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
			return 8
		Tier.HEAVY_FLESH:
			return 14
		Tier.WALL:
			return 12
		Tier.DEATH:
			return 18
		Tier.FINISHER:
			return 28
	return 8


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
