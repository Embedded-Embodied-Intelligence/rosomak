class_name CombatAttackData
extends RefCounted

## Data-driven attack definition shared by player moves, hitboxes, and feedback.
## Timings are fractions of the move's total duration (0..1) unless noted.

enum Strength { LIGHT, HEAVY, COUNTER, FINISHER }
enum BloodTier { NONE, LIGHT_FLESH, HEAVY_FLESH, WALL, DEATH, FINISHER }

var id: StringName = &""
var damage: int = 20
## Multiplier on Player.attack_duration for total swing length.
var time: float = 1.0
var startup: float = 0.40
var active_end: float = 0.58
## Earliest fraction where RT buffers the next light.
var combo_window: float = 0.32
## Fraction where recovery may cancel into next light / late dodge.
var cancel_window: float = 0.72
var hit_stop: float = 0.05
var knockback: float = 2.4
var rumble_weak: float = 0.16
var rumble_strong: float = 0.24
var rumble_duration: float = 0.09
var camera_impulse: float = 1.0
var blood_tier: BloodTier = BloodTier.LIGHT_FLESH
var strength: Strength = Strength.LIGHT
var can_dodge_cancel_late: bool = true
## 0..1+ aim-assist / gap-close weight for this move.
var magnetism: float = 1.0
var animation: StringName = &"attack-melee-right"
var limb: int = 0
## Slight forward drive during active (advancing heavy / lunge).
var advance_speed: float = 0.0
var kill_slow_mo: float = 0.0


static func make(
	p_id: StringName,
	p_damage: int,
	p_time: float,
	p_startup: float,
	p_active_end: float,
	p_combo: float,
	p_cancel: float,
	p_hit_stop: float,
	p_knockback: float,
	p_strength: Strength,
	p_blood: BloodTier,
	p_anim: StringName,
	p_limb: int,
	extras: Dictionary = {}
) -> CombatAttackData:
	var d := CombatAttackData.new()
	d.id = p_id
	d.damage = p_damage
	d.time = p_time
	d.startup = p_startup
	d.active_end = p_active_end
	d.combo_window = p_combo
	d.cancel_window = p_cancel
	d.hit_stop = p_hit_stop
	d.knockback = p_knockback
	d.strength = p_strength
	d.blood_tier = p_blood
	d.animation = p_anim
	d.limb = p_limb
	d.rumble_weak = float(extras.get("rumble_weak", d.rumble_weak))
	d.rumble_strong = float(extras.get("rumble_strong", d.rumble_strong))
	d.rumble_duration = float(extras.get("rumble_duration", d.rumble_duration))
	d.camera_impulse = float(extras.get("camera_impulse", 1.0 if p_strength == Strength.LIGHT else 1.8))
	d.can_dodge_cancel_late = bool(extras.get("can_dodge_cancel_late", true))
	d.magnetism = float(extras.get("magnetism", 1.0))
	d.advance_speed = float(extras.get("advance_speed", 0.0))
	d.kill_slow_mo = float(extras.get("kill_slow_mo", 0.0))
	return d


## Canonical player moveset — tuned for Xbox RT light / RB heavy claw feel.
static func light_1() -> CombatAttackData:
	return make(
		&"light_1", 20, 0.85, 0.38, 0.56, 0.30, 0.70, 0.045, 2.2,
		Strength.LIGHT, BloodTier.LIGHT_FLESH, &"attack-melee-right", 0,
		{magnetism = 0.85, camera_impulse = 0.9}
	)


static func light_2() -> CombatAttackData:
	return make(
		&"light_2", 25, 0.95, 0.36, 0.55, 0.28, 0.68, 0.055, 2.8,
		Strength.LIGHT, BloodTier.LIGHT_FLESH, &"attack-melee-left", 1,
		{magnetism = 0.9, camera_impulse = 1.1, rumble_strong = 0.28}
	)


static func light_3() -> CombatAttackData:
	return make(
		&"light_3", 35, 1.15, 0.34, 0.58, 0.40, 0.78, 0.085, 4.2,
		Strength.LIGHT, BloodTier.HEAVY_FLESH, &"attack-melee-right", 0,
		{
			magnetism = 1.0, camera_impulse = 1.9, rumble_weak = 0.28, rumble_strong = 0.45,
			rumble_duration = 0.14, kill_slow_mo = 0.14, can_dodge_cancel_late = true
		}
	)


static func heavy() -> CombatAttackData:
	return make(
		&"heavy", 52, 1.35, 0.42, 0.62, 1.0, 0.82, 0.09, 7.2,
		Strength.HEAVY, BloodTier.HEAVY_FLESH, &"attack-kick-right", 2,
		{
			magnetism = 1.05, camera_impulse = 2.2, rumble_weak = 0.35, rumble_strong = 0.55,
			rumble_duration = 0.16, kill_slow_mo = 0.18, can_dodge_cancel_late = true
		}
	)


static func heavy_advance() -> CombatAttackData:
	var d := heavy()
	d.id = &"heavy_advance"
	d.advance_speed = 4.5
	d.magnetism = 1.15
	d.knockback = 6.4
	return d


static func lunge() -> CombatAttackData:
	return make(
		&"lunge", 48, 1.2, 0.30, 0.55, 1.0, 0.80, 0.08, 6.5,
		Strength.HEAVY, BloodTier.HEAVY_FLESH, &"attack-kick-right", 2,
		{
			magnetism = 1.35, advance_speed = 0.0, camera_impulse = 2.0,
			rumble_weak = 0.3, rumble_strong = 0.5, rumble_duration = 0.14, kill_slow_mo = 0.16
		}
	)


static func counter() -> CombatAttackData:
	return make(
		&"counter", 40, 0.7, 0.18, 0.42, 1.0, 0.75, 0.1, 5.5,
		Strength.COUNTER, BloodTier.HEAVY_FLESH, &"attack-melee-left", 1,
		{
			magnetism = 1.2, camera_impulse = 2.4, rumble_weak = 0.4, rumble_strong = 0.7,
			rumble_duration = 0.18, kill_slow_mo = 0.2, can_dodge_cancel_late = false
		}
	)


static func grab_stab() -> CombatAttackData:
	return make(
		&"grab_stab", 30, 1.1, 0.35, 0.48, 1.0, 0.9, 0.12, 1.0,
		Strength.HEAVY, BloodTier.HEAVY_FLESH, &"attack-melee-right", 0,
		{
			magnetism = 0.0, camera_impulse = 2.0, rumble_weak = 0.45, rumble_strong = 0.7,
			rumble_duration = 0.2, can_dodge_cancel_late = false
		}
	)


static func wall_slam() -> CombatAttackData:
	return make(
		&"wall_slam", 45, 1.0, 0.40, 0.55, 1.0, 0.9, 0.11, 3.0,
		Strength.HEAVY, BloodTier.WALL, &"attack-melee-right", 0,
		{
			magnetism = 0.0, camera_impulse = 2.6, rumble_weak = 0.5, rumble_strong = 0.75,
			rumble_duration = 0.22, kill_slow_mo = 0.12, can_dodge_cancel_late = false
		}
	)


static func signature_finisher() -> CombatAttackData:
	return make(
		&"signature_finisher", 999, 2.0, 0.55, 0.68, 1.0, 0.95, 0.18, 2.0,
		Strength.FINISHER, BloodTier.FINISHER, &"attack-melee-right", 0,
		{
			magnetism = 0.0, camera_impulse = 3.0, rumble_weak = 0.55, rumble_strong = 0.9,
			rumble_duration = 0.28, kill_slow_mo = 0.22, can_dodge_cancel_late = false
		}
	)


static func lights() -> Array[CombatAttackData]:
	return [light_1(), light_2(), light_3()]
