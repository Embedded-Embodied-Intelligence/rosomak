class_name Hud
extends CanvasLayer

## Builds the whole HUD in code: vitals, wave info, hit counter, banners, and pause.
## It keeps running while the tree is paused so it can also own the pause toggle.

signal pause_changed(paused: bool)

const VIGNETTE_SHADER := preload("res://shaders/vignette.gdshader")
const ACCENT := Color(1.0, 0.72, 0.28)
const RAGE_COLOR := Color(1.0, 0.5, 0.08)
const RAGE_ACTIVE_COLOR := Color(1.0, 0.16, 0.08)

var pause_allowed: bool = false

var _health_bar: ProgressBar
var _health_label: Label
var _rage_bar: ProgressBar
var _rage_fill: StyleBoxFlat
var _rage_hint: Label
var _wave_label: Label
var _enemies_label: Label
var _kills_label: Label
var _banner_box: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _banner_hint: Label
var _chain_label: Label
var _vignette: ShaderMaterial
var _pause_panel: Control
var _banner_tween: Tween
var _chain_tween: Tween
var _hurt: float = 0.0
var _health_ratio: float = 1.0
var _hint_time: float = 0.0
var _context_label: Label
var _tutorial_label: Label
var _tutorial_tween: Tween
var _context_root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var root := _full_rect(Control.new())
	add_child(root)

	var vignette := _full_rect(ColorRect.new())
	_vignette = ShaderMaterial.new()
	_vignette.shader = VIGNETTE_SHADER
	vignette.material = _vignette
	root.add_child(vignette)

	var stats := VBoxContainer.new()
	stats.position = Vector2(28, 22)
	stats.add_theme_constant_override("separation", 6)
	root.add_child(stats)
	stats.add_child(_label("ROSOMAK", 20, ACCENT))
	_health_bar = _bar(Color(0.86, 0.2, 0.18), Vector2(340, 24))
	stats.add_child(_health_bar)
	_health_label = _full_rect(_label("100 / 100", 15)) as Label
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_bar.add_child(_health_label)
	_rage_bar = _bar(RAGE_COLOR, Vector2(340, 12))
	_rage_fill = _rage_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_rage_bar.value = 0.0
	stats.add_child(_rage_bar)
	_rage_hint = _label("", 15, RAGE_COLOR)
	stats.add_child(_rage_hint)

	var info := VBoxContainer.new()
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -320
	info.offset_right = -28
	info.offset_top = 18
	root.add_child(info)
	_wave_label = _label("", 34, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	_enemies_label = _label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_kills_label = _label("", 18, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	for label in [_wave_label, _enemies_label, _kills_label]:
		info.add_child(label)

	_chain_label = _label("", 46, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	_chain_label.anchor_left = 1.0
	_chain_label.anchor_right = 1.0
	_chain_label.anchor_top = 0.42
	_chain_label.anchor_bottom = 0.42
	_chain_label.offset_left = -300
	_chain_label.offset_right = -40
	_chain_label.modulate.a = 0.0
	root.add_child(_chain_label)

	# Contextual action prompt (bottom-center).
	_context_root = Control.new()
	_context_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_context_root.offset_top = -90
	_context_root.offset_bottom = -50
	_context_root.offset_left = -220
	_context_root.offset_right = 220
	root.add_child(_context_root)
	_context_label = _label("", 22, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_context_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_context_label.modulate.a = 0.0
	_context_root.add_child(_context_label)

	_tutorial_label = _label("", 26, Color(1.0, 0.92, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
	_tutorial_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tutorial_label.offset_top = 96
	_tutorial_label.offset_bottom = 140
	_tutorial_label.offset_left = -320
	_tutorial_label.offset_right = 320
	_tutorial_label.modulate.a = 0.0
	root.add_child(_tutorial_label)

	var center := _full_rect(CenterContainer.new())
	center.offset_bottom = -90
	root.add_child(center)
	_banner_box = VBoxContainer.new()
	_banner_box.add_theme_constant_override("separation", 10)
	_banner_box.modulate.a = 0.0
	center.add_child(_banner_box)
	_banner = _label("", 72, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_hint = _label("", 24, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	for label in [_banner, _banner_sub, _banner_hint]:
		_banner_box.add_child(label)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.6)
	_pause_panel = _full_rect(shade)
	_pause_panel.visible = false
	root.add_child(_pause_panel)
	var pause_center := _full_rect(CenterContainer.new())
	_pause_panel.add_child(pause_center)
	var pause_box := VBoxContainer.new()
	pause_center.add_child(pause_box)
	pause_box.add_child(_label("PAUZA", 72, ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	pause_box.add_child(_label("Start / Esc — wróć do walki", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))


func _process(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta * 2.5)
	var danger := 0.0
	if _health_ratio < 0.3:
		danger = (0.3 - _health_ratio) / 0.3 * (0.35 + 0.15 * sin(Time.get_ticks_msec() * 0.008))
	_vignette.set_shader_parameter(&"strength", clampf(maxf(_hurt, danger), 0.0, 1.0))
	_hint_time += delta
	_banner_hint.modulate.a = 0.55 + 0.45 * sin(_hint_time * 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and pause_allowed:
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_panel.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	pause_changed.emit(paused)


func set_health(health: int, max_health: int) -> void:
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_label.text = "%d / %d" % [health, max_health]
	_health_ratio = float(health) / max_health


func set_rage(rage: float, raging: bool) -> void:
	_rage_bar.value = rage
	_rage_fill.bg_color = RAGE_ACTIVE_COLOR if raging else RAGE_COLOR
	if raging:
		_rage_hint.text = "SZAŁ!"
	elif rage >= 100.0:
		_rage_hint.text = "SZAŁ GOTOWY — Y / Q"
	else:
		_rage_hint.text = ""


func set_hit_chain(count: int) -> void:
	if _chain_tween:
		_chain_tween.kill()
	_chain_tween = create_tween()
	if count < 2:
		_chain_tween.tween_property(_chain_label, "modulate:a", 0.0, 0.3)
		return
	_chain_label.text = "%d HIT" % count
	_chain_label.modulate.a = 1.0
	_chain_label.pivot_offset = _chain_label.size * Vector2(1.0, 0.5)
	_chain_label.scale = Vector2.ONE * 1.35
	_chain_tween.tween_property(_chain_label, "scale", Vector2.ONE, 0.12)


func flash_hurt(_damage: int) -> void:
	_hurt = 0.8


func set_counts(remaining: int, kills: int) -> void:
	_enemies_label.text = "Wrogowie: %d" % remaining
	_kills_label.text = "Pokonani: %d" % kills


## Shows a centered message; a duration of 0 keeps it until the next banner.
func banner(title: String, subtitle: String = "", duration: float = 2.2, hint: String = "", title_size: int = 72) -> void:
	_banner.text = title
	_banner.add_theme_font_size_override("font_size", title_size)
	_banner_sub.text = subtitle
	_banner_sub.visible = not subtitle.is_empty()
	_banner_hint.text = hint
	_banner_hint.visible = not hint.is_empty()
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_box, "modulate:a", 1.0, 0.2)
	if duration > 0.0:
		_banner_tween.tween_interval(duration)
		_banner_tween.tween_property(_banner_box, "modulate:a", 0.0, 0.4)


func show_title() -> void:
	banner(
		"ROSOMAK",
		"Trzecioosobowy claw-fighter · jedna arena · jedna fala\n\n"
		+ "Pad:  LS ruch · RS kamera · RT lekki (3×) · RB ciężki · LT chwyt/finisz · A unik · Y szał\n"
		+ "Klawiatura:  WASD · mysz · J lekki · K ciężki · L chwyt · Spacja unik · Q szał · Esc pauza",
		0.0,
		"A / Enter — start · B / Esc — wyjście",
		110
	)


func show_victory(kills: int) -> void:
	banner(
		"AREA CLEAR",
		"Arena oczyszczona · pokonani: %d" % kills,
		0.0,
		"A / Enter — Restart · B / Esc — Exit",
		96
	)


func show_game_over(kills: int) -> void:
	banner(
		"POLEGŁEŚ",
		"Pokonani: %d" % kills,
		0.0,
		"A / Enter — Restart · B / Esc — Exit",
		96
	)


func set_mission_labels(enabled: bool) -> void:
	## Mission mode uses objective presenter for goals; keep vitals, hide arena wave chrome until combat.
	if not enabled:
		return
	_wave_label.text = "PROJECT CLAW"
	_enemies_label.text = ""
	_kills_label.text = ""


func set_section(section: String) -> void:
	_wave_label.text = section


func show_mission_death() -> void:
	banner(
		"YOU DIED",
		"Restoring checkpoint…",
		0.0,
		"A / Enter — Skip wait",
		96
	)


func show_mission_complete(kills: int, time_text: String) -> void:
	banner(
		"MISSION COMPLETE",
		"Hostiles down: %d · Time %s" % [kills, time_text],
		0.0,
		"A / Enter — Replay · B / Esc — Exit",
		88
	)


func set_context_prompt(text: String) -> void:
	if _context_label == null:
		return
	_context_label.text = text
	var target_a := 1.0 if not text.is_empty() else 0.0
	var tw := create_tween()
	tw.tween_property(_context_label, "modulate:a", target_a, 0.12)


func show_tutorial(text: String, duration: float = 2.6) -> void:
	if _tutorial_label == null or text.is_empty():
		return
	_tutorial_label.text = text
	if _tutorial_tween:
		_tutorial_tween.kill()
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial_label, "modulate:a", 1.0, 0.18)
	_tutorial_tween.tween_interval(duration)
	_tutorial_tween.tween_property(_tutorial_label, "modulate:a", 0.0, 0.45)


func clear_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner_box.modulate.a = 0.0
	_banner_hint.visible = false


func set_wave(wave: int) -> void:
	_wave_label.text = "ARENA" if wave <= 1 else "FALA %d" % wave


func _label(text: String, size: int, color: Color = Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(4, size / 6))
	return label


func _bar(color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.55)
	background.border_color = Color(1, 1, 1, 0.18)
	background.set_border_width_all(2)
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _full_rect(control: Control) -> Control:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control
