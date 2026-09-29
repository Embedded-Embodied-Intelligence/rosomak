class_name HitEvent
extends RefCounted

## Payload for every successful hurtbox connection. Extends legacy damage fields
## with direction, strength tier, attacker, and source move id for reactions/VFX.

var damage: int = 0
var source_position: Vector3 = Vector3.ZERO
var hit_stop: float = 0.05
var knockback: float = 2.4
var direction: Vector3 = Vector3.FORWARD
var attack_strength: int = CombatAttackData.Strength.LIGHT
var attacker: Node3D
var source_move_id: StringName = &""
var blood_tier: int = CombatAttackData.BloodTier.LIGHT_FLESH
## Extra stagger pressure applied on top of damage-based build.
var stagger_bonus: float = 0.0


static func from_move(
	move: CombatAttackData,
	p_attacker: Node3D,
	p_source_position: Vector3,
	damage_scale: float = 1.0
) -> HitEvent:
	var e := HitEvent.new()
	e.damage = maxi(1, roundi(float(move.damage) * damage_scale))
	e.source_position = p_source_position
	e.hit_stop = move.hit_stop
	e.knockback = move.knockback
	e.attack_strength = move.strength
	e.attacker = p_attacker
	e.source_move_id = move.id
	e.blood_tier = move.blood_tier
	var dir := Vector3.ZERO
	if is_instance_valid(p_attacker):
		dir = -p_attacker.global_basis.z if p_attacker is Node3D else Vector3.FORWARD
		if p_attacker.get("visuals") is Node3D:
			dir = -(p_attacker.visuals as Node3D).global_basis.z
	dir.y = 0.0
	e.direction = dir.normalized() if not dir.is_zero_approx() else Vector3.FORWARD
	match move.strength:
		CombatAttackData.Strength.COUNTER:
			e.stagger_bonus = 80.0
		CombatAttackData.Strength.HEAVY:
			e.stagger_bonus = 45.0
		CombatAttackData.Strength.FINISHER:
			e.stagger_bonus = 999.0
		_:
			e.stagger_bonus = 12.0 if move.id == &"light_3" else 8.0
	return e


static func legacy(
	p_damage: int,
	p_source_position: Vector3,
	p_hit_stop: float,
	p_knockback: float
) -> HitEvent:
	var e := HitEvent.new()
	e.damage = p_damage
	e.source_position = p_source_position
	e.hit_stop = p_hit_stop
	e.knockback = p_knockback
	var away := Vector3.FORWARD
	e.direction = away
	return e
