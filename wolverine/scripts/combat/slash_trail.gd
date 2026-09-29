class_name SlashTrail
extends MeshInstance3D

## Cheap claw slash ribbon attached for active frames. Procedural placeholder.

var life: float = 0.18
var age: float = 0.0
var _mat: StandardMaterial3D


static func attach(parent: Node3D, strength: int) -> SlashTrail:
	var trail := SlashTrail.new()
	var box := BoxMesh.new()
	match strength:
		CombatAttackData.Strength.FINISHER:
			box.size = Vector3(0.08, 0.55, 0.02)
			trail.life = 0.28
		CombatAttackData.Strength.HEAVY, CombatAttackData.Strength.COUNTER:
			box.size = Vector3(0.06, 0.48, 0.018)
			trail.life = 0.22
		_:
			box.size = Vector3(0.045, 0.38, 0.015)
	trail.mesh = box
	trail._mat = StandardMaterial3D.new()
	trail._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail._mat.albedo_color = Color(0.85, 0.9, 1.0, 0.55)
	trail._mat.emission_enabled = true
	trail._mat.emission = Color(0.5, 0.65, 0.85)
	trail._mat.emission_energy_multiplier = 1.2
	trail.material_override = trail._mat
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.position = Vector3(0.0, -0.15, 0.05)
	parent.add_child(trail)
	return trail


func _process(delta: float) -> void:
	age += delta
	var t := age / life
	if t >= 1.0:
		queue_free()
		return
	_mat.albedo_color.a = lerpf(0.55, 0.0, t)
	scale.y = lerpf(1.0, 1.35, t)
