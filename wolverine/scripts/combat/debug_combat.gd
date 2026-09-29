class_name DebugCombat
extends Node

## Runtime combat debug overlays. Forced off outside debug/editor builds.

static var hitboxes: bool = false
static var hurtboxes: bool = false
static var target_cone: bool = false
static var state_label: bool = false
static var combo_label: bool = false
static var stagger_label: bool = false


static func enabled_in_build() -> bool:
	return OS.is_debug_build()


static func any() -> bool:
	return enabled_in_build() and (
		hitboxes or hurtboxes or target_cone or state_label or combo_label or stagger_label
	)


static func reset_release() -> void:
	if enabled_in_build():
		return
	hitboxes = false
	hurtboxes = false
	target_cone = false
	state_label = false
	combo_label = false
	stagger_label = false


func _ready() -> void:
	reset_release()
