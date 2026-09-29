extends Node3D

## Single-wave vertical slice: title → trickle-spawned encounter → AREA CLEAR or death.

enum Phase { TITLE, BREAK, FIGHT, VICTORY, OVER }

const GRUNT := preload("res://scenes/enemies/grunt.tscn")
const RUNNER := preload("res://scenes/enemies/runner.tscn")
const BRUTE := preload("res://scenes/enemies/brute.tscn")

@export var break_time: float = 2.5
@export var spawn_interval: float = 0.75
@export var kill_rage: float = 10.0

var phase: Phase = Phase.TITLE
var phase_time: float = 0.0
var kills: int = 0
var alive: int = 0
var _roster: Array[PackedScene] = []
var _spawn_timer: float = 0.0

@onready var player: Player = $Player
@onready var hud: Hud = $Hud
@onready var enemies: Node3D = $Enemies
@onready var spawn_points: Array[Node] = $SpawnPoints.get_children()


func _ready() -> void:
	# Static slots survive scene reloads, so every run starts from an empty pool.
	Enemy.attackers = 0
	Enemy.max_attackers = 2
	player.controls_enabled = false
	player.health_changed.connect(hud.set_health)
	player.rage_changed.connect(hud.set_rage)
	player.hit_chain_changed.connect(hud.set_hit_chain)
	player.hurt.connect(hud.flash_hurt)
	if player.has_signal("context_prompt_changed"):
		player.context_prompt_changed.connect(hud.set_context_prompt)
	if player.has_signal("tutorial_requested"):
		player.tutorial_requested.connect(hud.show_tutorial)
	player.died.connect(_on_player_died)
	hud.set_health(player.max_health, player.max_health)
	hud.set_rage(0.0, false)
	hud.show_title()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.TITLE:
		if event.is_action_pressed("ui_accept"):
			start_run()
		elif event.is_action_pressed("ui_cancel"):
			get_tree().quit()
		return
	if phase == Phase.VICTORY or phase == Phase.OVER:
		if phase_time < 1.2:
			return
		if event.is_action_pressed("ui_accept"):
			get_tree().reload_current_scene()
		elif event.is_action_pressed("ui_cancel"):
			get_tree().quit()


func start_run() -> void:
	kills = 0
	player.controls_enabled = true
	hud.pause_allowed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_roster = build_roster()
	hud.set_wave(1)
	hud.set_counts(_roster.size(), kills)
	phase = Phase.BREAK
	phase_time = 0.0
	_sfx(&"wave", 0.0, 0.0)
	hud.banner("FALA 1", "7 wrogów — w tym brutal. Unikaj telewizowanych ciosów.", break_time - 0.4)


func _process(delta: float) -> void:
	phase_time += delta
	match phase:
		Phase.BREAK:
			if phase_time >= break_time:
				_begin_fight()
		Phase.FIGHT:
			_spawn_timer -= delta
			if not _roster.is_empty() and alive < 5 and _spawn_timer <= 0.0:
				_spawn(_roster.pop_back())
				_spawn_timer = spawn_interval
			elif _roster.is_empty() and alive == 0:
				_on_area_clear()


## Fixed vertical-slice roster: 4 grunts, 2 runners, 1 brute (7 total).
static func build_roster() -> Array[PackedScene]:
	var roster: Array[PackedScene] = [GRUNT, GRUNT, GRUNT, GRUNT, RUNNER, RUNNER, BRUTE]
	roster.shuffle()
	return roster


func _begin_fight() -> void:
	phase = Phase.FIGHT
	phase_time = 0.0
	_spawn_timer = 0.0
	Enemy.max_attackers = 2


func _spawn(scene: PackedScene) -> void:
	var enemy := scene.instantiate() as Enemy
	# Prefer one of the two gates farthest from the player, so nothing pops in at melee range.
	var points := spawn_points.duplicate()
	points.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(player.global_position) > b.global_position.distance_to(player.global_position)
	)
	var gate: Node3D = points[randi() % mini(2, points.size())]
	enemy.position = gate.global_position + Vector3(randf_range(-1.5, 1.5), 0.05, randf_range(-1.5, 1.5))
	enemy.died.connect(_on_enemy_died)
	enemies.add_child(enemy)
	alive += 1
	hud.set_counts(alive + _roster.size(), kills)


func _on_enemy_died(_enemy: Enemy) -> void:
	alive -= 1
	kills += 1
	player.add_rage(kill_rage)
	hud.set_counts(alive + _roster.size(), kills)


func _on_area_clear() -> void:
	phase = Phase.VICTORY
	phase_time = 0.0
	hud.pause_allowed = false
	player.controls_enabled = false
	_sfx(&"clear", 0.0, 0.0)
	await get_tree().create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_victory(kills)


func _on_player_died() -> void:
	phase = Phase.OVER
	phase_time = 0.0
	hud.pause_allowed = false
	_sfx(&"game_over", 0.0, 0.0)
	await get_tree().create_timer(1.4).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_game_over(kills)


func _sfx(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var bus := get_node_or_null("/root/Sfx")
	if bus and bus.has_method("play"):
		bus.play(sound, volume_db, pitch_jitter)
