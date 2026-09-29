class_name CharacterAnim
extends RefCounted

## Procedural AnimationLibrary builder for the Kenney figurine limb rig.
## Keeps control deterministic without an AnimationTree rewrite: directional dodge,
## hit reactions, grab/throw/finisher accents layered on stock clips via playback.

const ROOT := NodePath("figurine-cube-detailed/root")
const LEG_L := NodePath("figurine-cube-detailed/root/leg-left")
const LEG_R := NodePath("figurine-cube-detailed/root/leg-right")
const TORSO := NodePath("figurine-cube-detailed/root/torso")
const ARM_L := NodePath("figurine-cube-detailed/root/torso/arm-left")
const ARM_R := NodePath("figurine-cube-detailed/root/torso/arm-right")
const HEAD := NodePath("figurine-cube-detailed/root/torso/head")


static func build_actions() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"dodge", _make_dodge(Vector3(12, 0, 0), Vector3(-28, 0, 0), Vector3(18, 0, 0), 0.0))
	lib.add_animation(&"dodge_f", _make_dodge(Vector3(18, 0, 0), Vector3(-36, 8, 0), Vector3(22, -8, 0), 0.04))
	lib.add_animation(&"dodge_b", _make_dodge(Vector3(-14, 0, 0), Vector3(20, 0, 0), Vector3(-24, 0, 0), -0.03))
	lib.add_animation(&"dodge_l", _make_dodge(Vector3(6, 0, 18), Vector3(-22, 0, 12), Vector3(10, 0, -8), 0.0))
	lib.add_animation(&"dodge_r", _make_dodge(Vector3(6, 0, -18), Vector3(-10, 0, 8), Vector3(22, 0, -12), 0.0))
	lib.add_animation(&"grab_hold", _make_grab_hold())
	lib.add_animation(&"stab", _make_stab())
	lib.add_animation(&"throw", _make_throw())
	lib.add_animation(&"finisher", _make_finisher())
	lib.add_animation(&"wall_slam", _make_wall_slam())
	return lib


static func build_reactions() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"hit", _make_hit(Vector3(-18, 0, 0), Vector3(14, 0, 8), Vector3(14, 0, -8), 0.24))
	lib.add_animation(&"hit_front", _make_hit(Vector3(-22, 0, 0), Vector3(18, 10, 6), Vector3(18, -10, -6), 0.26))
	lib.add_animation(&"hit_left", _make_hit(Vector3(-10, 0, 22), Vector3(8, 0, 18), Vector3(20, 0, -4), 0.26))
	lib.add_animation(&"hit_right", _make_hit(Vector3(-10, 0, -22), Vector3(20, 0, 4), Vector3(8, 0, -18), 0.26))
	lib.add_animation(&"hit_heavy", _make_hit(Vector3(-32, 0, 0), Vector3(28, 12, 10), Vector3(28, -12, -10), 0.38, true))
	lib.add_animation(&"stagger", _make_stagger())
	lib.add_animation(&"death_launch", _make_death_launch())
	return lib


static func dodge_name(local_dir: Vector3) -> StringName:
	## local_dir in character space: +z back (figurine faces -z after Visuals yaw).
	if local_dir.length_squared() < 0.01:
		return &"actions/dodge_f"
	var flat := Vector3(local_dir.x, 0.0, local_dir.z).normalized()
	var f := -flat.z
	var r := flat.x
	if absf(f) >= absf(r):
		return &"actions/dodge_f" if f > 0.0 else &"actions/dodge_b"
	return &"actions/dodge_r" if r > 0.0 else &"actions/dodge_l"


static func hit_name(away_local: Vector3, heavy: bool) -> StringName:
	if heavy:
		return &"reactions/hit_heavy"
	if away_local.length_squared() < 0.01:
		return &"reactions/hit"
	var flat := Vector3(away_local.x, 0.0, away_local.z).normalized()
	# away_local: direction body is knocked (relative to facing). Front hit → push back (+z).
	if absf(flat.x) > absf(flat.z) * 0.85:
		return &"reactions/hit_right" if flat.x > 0.0 else &"reactions/hit_left"
	return &"reactions/hit"


static func _q(euler_deg: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(
		deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)
	))


static func _anim(length: float) -> Animation:
	var a := Animation.new()
	a.length = length
	return a


static func _add_rot(a: Animation, path: NodePath, times: PackedFloat32Array, eulers: Array) -> void:
	var idx := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(idx, path)
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	for i in times.size():
		a.track_insert_key(idx, times[i], _q(eulers[i]))


static func _add_pos(a: Animation, path: NodePath, times: PackedFloat32Array, positions: Array) -> void:
	var idx := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(idx, path)
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	for i in times.size():
		a.track_insert_key(idx, times[i], positions[i])


static func _make_dodge(torso_e: Vector3, leg_l: Vector3, leg_r: Vector3, lean_z: float) -> Animation:
	var a := _anim(0.32)
	var t := PackedFloat32Array([0.0, 0.05, 0.2, 0.32])
	var z := Vector3.ZERO
	_add_rot(a, ROOT, t, [z, Vector3(0, 0, lean_z * 40.0), Vector3(0, 0, lean_z * 40.0), z])
	_add_rot(a, LEG_L, t, [z, leg_l, leg_l * 0.85, z])
	_add_rot(a, LEG_R, t, [z, leg_r, leg_r * 0.85, z])
	_add_rot(a, TORSO, t, [z, torso_e, torso_e * 0.7, z])
	_add_rot(a, ARM_L, t, [z, Vector3(35, 8, -12), Vector3(20, 4, -6), z])
	_add_rot(a, ARM_R, t, [z, Vector3(35, -8, 12), Vector3(20, -4, 6), z])
	_add_rot(a, HEAD, t, [z, Vector3(-8, 0, 0), Vector3(-4, 0, 0), z])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO, Vector3(0, -0.03, lean_z), Vector3(0, -0.02, lean_z * 0.5), Vector3.ZERO
	])
	return a


static func _make_hit(torso_e: Vector3, arm_l: Vector3, arm_r: Vector3, length: float, heavy: bool = false) -> Animation:
	var a := _anim(length)
	var peak := length * 0.22
	var hold := length * 0.55
	var t := PackedFloat32Array([0.0, peak, hold, length])
	var z := Vector3.ZERO
	var root_pitch := -8.0 if heavy else -3.0
	_add_rot(a, ROOT, t, [z, Vector3(root_pitch, 0, 0), Vector3(root_pitch * 0.5, 0, 0), z])
	_add_rot(a, LEG_L, t, [z, Vector3(8 if heavy else 2, 0, 0), Vector3(4, 0, 0), z])
	_add_rot(a, LEG_R, t, [z, Vector3(-6 if heavy else -2, 0, 0), Vector3(-3, 0, 0), z])
	_add_rot(a, TORSO, t, [z, torso_e, torso_e * 0.45, z])
	_add_rot(a, ARM_L, t, [z, arm_l, arm_l * 0.4, z])
	_add_rot(a, ARM_R, t, [z, arm_r, arm_r * 0.4, z])
	_add_rot(a, HEAD, t, [z, Vector3(-12 if heavy else -6, torso_e.z * 0.4, 0), Vector3(-4, 0, 0), z])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO,
		Vector3(0, -0.04 if heavy else -0.015, 0.02),
		Vector3(0, -0.02 if heavy else -0.008, 0.01),
		Vector3.ZERO,
	])
	return a


static func _make_stagger() -> Animation:
	var a := _anim(0.45)
	var t := PackedFloat32Array([0.0, 0.1, 0.28, 0.45])
	var z := Vector3.ZERO
	_add_rot(a, TORSO, t, [z, Vector3(-16, 8, 6), Vector3(-10, -4, -4), z])
	_add_rot(a, ARM_L, t, [z, Vector3(40, 0, 20), Vector3(22, 0, 10), z])
	_add_rot(a, ARM_R, t, [z, Vector3(40, 0, -20), Vector3(22, 0, -10), z])
	_add_rot(a, HEAD, t, [z, Vector3(-14, 10, 0), Vector3(-6, -4, 0), z])
	_add_rot(a, LEG_L, t, [z, Vector3(12, 0, 0), Vector3(6, 0, 0), z])
	_add_rot(a, LEG_R, t, [z, Vector3(-10, 0, 0), Vector3(-5, 0, 0), z])
	_add_pos(a, ROOT, t, [Vector3.ZERO, Vector3(0, -0.05, 0.03), Vector3(0, -0.03, 0.01), Vector3.ZERO])
	return a


static func _make_grab_hold() -> Animation:
	var a := _anim(1.0)
	a.loop_mode = Animation.LOOP_LINEAR
	var t := PackedFloat32Array([0.0, 0.5, 1.0])
	var z := Vector3.ZERO
	_add_rot(a, TORSO, t, [Vector3(8, 0, 0), Vector3(10, 0, 0), Vector3(8, 0, 0)])
	_add_rot(a, ARM_L, t, [Vector3(-55, 25, -20), Vector3(-50, 22, -18), Vector3(-55, 25, -20)])
	_add_rot(a, ARM_R, t, [Vector3(-55, -25, 20), Vector3(-50, -22, 18), Vector3(-55, -25, 20)])
	_add_rot(a, HEAD, t, [Vector3(6, 0, 0), Vector3(8, 0, 0), Vector3(6, 0, 0)])
	_add_rot(a, LEG_L, t, [z, Vector3(4, 0, 0), z])
	_add_rot(a, LEG_R, t, [z, Vector3(-4, 0, 0), z])
	_add_pos(a, ROOT, t, [Vector3.ZERO, Vector3(0, -0.01, 0.02), Vector3.ZERO])
	return a


static func _make_stab() -> Animation:
	var a := _anim(0.4)
	var t := PackedFloat32Array([0.0, 0.08, 0.18, 0.28, 0.4])
	var z := Vector3.ZERO
	_add_rot(a, TORSO, t, [Vector3(6, 0, 0), Vector3(-4, 0, 0), Vector3(14, 0, 0), Vector3(8, 0, 0), z])
	_add_rot(a, ARM_R, t, [
		Vector3(-40, -20, 10), Vector3(-70, -10, 5), Vector3(-20, -5, 0), Vector3(-35, -15, 8), z
	])
	_add_rot(a, ARM_L, t, [
		Vector3(-45, 20, -10), Vector3(-40, 25, -12), Vector3(-50, 15, -8), Vector3(-42, 18, -10), z
	])
	_add_rot(a, HEAD, t, [Vector3(4, 0, 0), Vector3(-2, 0, 0), Vector3(8, 0, 0), Vector3(2, 0, 0), z])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO, Vector3(0, 0, -0.02), Vector3(0, -0.01, 0.05), Vector3(0, 0, 0.02), Vector3.ZERO
	])
	return a


static func _make_throw() -> Animation:
	var a := _anim(0.45)
	var t := PackedFloat32Array([0.0, 0.12, 0.22, 0.35, 0.45])
	var z := Vector3.ZERO
	_add_rot(a, TORSO, t, [Vector3(10, -20, 0), Vector3(6, -35, 0), Vector3(-8, 25, 0), Vector3(4, 10, 0), z])
	_add_rot(a, ARM_L, t, [
		Vector3(-50, 30, -15), Vector3(-60, 40, -20), Vector3(-10, -20, 30), Vector3(-20, 0, 10), z
	])
	_add_rot(a, ARM_R, t, [
		Vector3(-50, -30, 15), Vector3(-60, -40, 20), Vector3(-10, 20, -30), Vector3(-20, 0, -10), z
	])
	_add_rot(a, LEG_L, t, [z, Vector3(-8, 0, 0), Vector3(18, 0, 0), Vector3(6, 0, 0), z])
	_add_rot(a, LEG_R, t, [z, Vector3(10, 0, 0), Vector3(-12, 0, 0), Vector3(-4, 0, 0), z])
	_add_rot(a, HEAD, t, [Vector3(4, -10, 0), Vector3(2, -16, 0), Vector3(6, 12, 0), Vector3(2, 4, 0), z])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO, Vector3(0, -0.02, -0.02), Vector3(0, -0.01, 0.04), Vector3(0, 0, 0.01), Vector3.ZERO
	])
	return a


static func _make_finisher() -> Animation:
	var a := _anim(1.8)
	var t := PackedFloat32Array([0.0, 0.25, 0.55, 0.72, 0.95, 1.35, 1.8])
	var z := Vector3.ZERO
	_add_rot(a, TORSO, t, [
		Vector3(4, 0, 0), Vector3(-8, 15, 0), Vector3(18, -8, 0), Vector3(-6, 0, 0),
		Vector3(22, 0, 0), Vector3(10, 0, 0), z
	])
	_add_rot(a, ARM_R, t, [
		Vector3(-30, -20, 10), Vector3(-90, -30, 0), Vector3(-20, -10, 0), Vector3(-100, 0, 0),
		Vector3(-15, -5, 0), Vector3(-40, -15, 8), z
	])
	_add_rot(a, ARM_L, t, [
		Vector3(-35, 25, -10), Vector3(-45, 35, -15), Vector3(-70, 20, -10), Vector3(-25, 10, -5),
		Vector3(-55, 15, -8), Vector3(-30, 12, -6), z
	])
	_add_rot(a, HEAD, t, [
		Vector3(2, 0, 0), Vector3(-6, 8, 0), Vector3(10, -4, 0), Vector3(-4, 0, 0),
		Vector3(12, 0, 0), Vector3(4, 0, 0), z
	])
	_add_rot(a, LEG_L, t, [z, Vector3(6, 0, 0), Vector3(-4, 0, 0), Vector3(10, 0, 0), Vector3(4, 0, 0), z, z])
	_add_rot(a, LEG_R, t, [z, Vector3(-8, 0, 0), Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(-2, 0, 0), z, z])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO, Vector3(0, -0.02, -0.02), Vector3(0, -0.01, 0.03), Vector3(0, 0.01, -0.01),
		Vector3(0, -0.02, 0.06), Vector3(0, -0.01, 0.02), Vector3.ZERO
	])
	return a


static func _make_wall_slam() -> Animation:
	var a := _anim(1.0)
	var t := PackedFloat32Array([0.0, 0.25, 0.45, 0.7, 1.0])
	var z := Vector3.ZERO
	_add_rot(a, TORSO, t, [Vector3(8, 0, 0), Vector3(-10, 0, 0), Vector3(25, 0, 0), Vector3(12, 0, 0), z])
	_add_rot(a, ARM_L, t, [
		Vector3(-40, 20, -10), Vector3(-55, 30, -15), Vector3(-15, 10, 20), Vector3(-25, 15, -5), z
	])
	_add_rot(a, ARM_R, t, [
		Vector3(-40, -20, 10), Vector3(-55, -30, 15), Vector3(-15, -10, -20), Vector3(-25, -15, 5), z
	])
	_add_rot(a, HEAD, t, [Vector3(4, 0, 0), Vector3(-8, 0, 0), Vector3(14, 0, 0), Vector3(4, 0, 0), z])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO, Vector3(0, -0.02, -0.03), Vector3(0, -0.01, 0.08), Vector3(0, 0, 0.02), Vector3.ZERO
	])
	return a


static func _make_death_launch() -> Animation:
	var a := _anim(0.55)
	var t := PackedFloat32Array([0.0, 0.12, 0.35, 0.55])
	_add_rot(a, TORSO, t, [Vector3.ZERO, Vector3(-40, 15, 10), Vector3(-55, 20, 8), Vector3(-70, 10, 0)])
	_add_rot(a, ARM_L, t, [Vector3.ZERO, Vector3(50, 0, 30), Vector3(70, 0, 40), Vector3(40, 0, 20)])
	_add_rot(a, ARM_R, t, [Vector3.ZERO, Vector3(50, 0, -30), Vector3(70, 0, -40), Vector3(40, 0, -20)])
	_add_rot(a, HEAD, t, [Vector3.ZERO, Vector3(-20, 0, 0), Vector3(-30, 10, 0), Vector3(-25, 0, 0)])
	_add_rot(a, LEG_L, t, [Vector3.ZERO, Vector3(-20, 0, 0), Vector3(-35, 0, 0), Vector3(-15, 0, 0)])
	_add_rot(a, LEG_R, t, [Vector3.ZERO, Vector3(25, 0, 0), Vector3(40, 0, 0), Vector3(20, 0, 0)])
	_add_pos(a, ROOT, t, [
		Vector3.ZERO, Vector3(0, 0.08, -0.04), Vector3(0, 0.02, -0.08), Vector3(0, -0.06, -0.1)
	])
	return a
