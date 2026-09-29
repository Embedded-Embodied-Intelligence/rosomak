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
## Playback bias: >1 speeds the clip slightly within the same move time (snappier recovery feel).
var playback_bias: float = 1.0


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
	d.playback_bias = float(extras.get("playback_bias", 1.0))
	return d


## Canonical player moveset — distinct L1/L2/L3 choreography with readable anticipation.
static func light_1() -> CombatAttackData:
	return make(
		&"light_1", 20, 0.85, 0.42, 0.58, 0.28, 0.70, 0.05, 2.4,
		Strength.LIGHT, BloodTier.LIGHT_FLESH, &"attack-melee-right", 0,
		{
			magnetism = 0.9, camera_impulse = 1.05, rumble_weak = 0.18, rumble_strong = 0.26,
			advance_speed = 1.4, playback_bias = 1.02
		}
	)


static func light_2() -> CombatAttackData:
	return make(
		&"light_2", 26, 0.86, 0.30, 0.50, 0.20, 0.62, 0.06, 3.1,
		Strength.LIGHT, BloodTier.LIGHT_FLESH, &"attack-melee-left", 1,
		{
			magnetism = 0.95, camera_impulse = 1.35, rumble_weak = 0.22, rumble_strong = 0.34,
			rumble_duration = 0.11, advance_speed = 2.0, playback_bias = 1.08
		}
	)


static func light_3() -> CombatAttackData:
	return make(
		&"light_3", 38, 1.05, 0.28, 0.55, 0.48, 0.76, 0.095, 4.8,
		Strength.LIGHT, BloodTier.HEAVY_FLESH, &"attack-kick-right", 2,
		{
			magnetism = 1.08, camera_impulse = 2.15, rumble_weak = 0.34, rumble_strong = 0.52,
			rumble_duration = 0.16, kill_slow_mo = 0.14, can_dodge_cancel_late = true,
			advance_speed = 2.8, playback_bias = 0.95
		}
	)


static func heavy() -> CombatAttackData:
	return make(
		&"heavy", 52, 1.28, 0.46, 0.64, 1.0, 0.80, 0.095, 7.2,
		Strength.HEAVY, BloodTier.HEAVY_FLESH, &"attack-kick-right", 2,
		{
			magnetism = 1.05, camera_impulse = 2.35, rumble_weak = 0.36, rumble_strong = 0.58,
			rumble_duration = 0.17, kill_slow_mo = 0.18, can_dodge_cancel_late = true,
			playback_bias = 0.92
		}
	)


static func heavy_advance() -> CombatAttackData:
	var d := heavy()
	d.id = &"heavy_advance"
	d.advance_speed = 5.0
	d.magnetism = 1.15
	d.knockback = 6.4
	d.startup = 0.40
	return d


static func lunge() -> CombatAttackData:
	return make(
		&"lunge", 48, 1.1, 0.26, 0.52, 1.0, 0.78, 0.085, 6.5,
		Strength.HEAVY, BloodTier.HEAVY_FLESH, &"attack-kick-right", 2,
		{
			magnetism = 1.4, advance_speed = 0.0, camera_impulse = 2.1,
			rumble_weak = 0.32, rumble_strong = 0.52, rumble_duration = 0.14,
			kill_slow_mo = 0.16, playback_bias = 1.05
		}
	)


static func counter() -> CombatAttackData:
	return make(
		&"counter", 40, 0.65, 0.16, 0.40, 1.0, 0.72, 0.1, 5.5,
		Strength.COUNTER, BloodTier.HEAVY_FLESH, &"attack-melee-left", 1,
		{
			magnetism = 1.25, camera_impulse = 2.5, rumble_weak = 0.42, rumble_strong = 0.72,
			rumble_duration = 0.18, kill_slow_mo = 0.2, can_dodge_cancel_late = false,
			playback_bias = 1.12
		}
	)


static func grab_stab() -> CombatAttackData:
	return make(
		&"grab_stab", 34, 0.72, 0.32, 0.48, 1.0, 0.86, 0.14, 1.2,
		Strength.HEAVY, BloodTier.HEAVY_FLESH, &"actions/stab", 0,
		{
			magnetism = 0.0, camera_impulse = 2.4, rumble_weak = 0.52, rumble_strong = 0.82,
			rumble_duration = 0.22, can_dodge_cancel_late = false, playback_bias = 1.0
		}
	)


static func wall_slam() -> CombatAttackData:
	return make(
		&"wall_slam", 45, 1.0, 0.38, 0.55, 1.0, 0.9, 0.12, 3.0,
		Strength.HEAVY, BloodTier.WALL, &"actions/wall_slam", 0,
		{
			magnetism = 0.0, camera_impulse = 2.7, rumble_weak = 0.5, rumble_strong = 0.78,
			rumble_duration = 0.22, kill_slow_mo = 0.12, can_dodge_cancel_late = false
		}
	)


static func signature_finisher() -> CombatAttackData:
	## ~1.9s total at default attack_duration 0.5 (time * duration).
	return make(
		&"signature_finisher", 999, 3.8, 0.48, 0.62, 1.0, 0.94, 0.2, 2.0,
		Strength.FINISHER, BloodTier.FINISHER, &"actions/finisher", 0,
		{
			magnetism = 0.0, camera_impulse = 3.2, rumble_weak = 0.58, rumble_strong = 0.92,
			rumble_duration = 0.3, kill_slow_mo = 0.22, can_dodge_cancel_late = false,
			playback_bias = 1.0
		}
	)


static func lights() -> Array[CombatAttackData]:
	return [light_1(), light_2(), light_3()]
