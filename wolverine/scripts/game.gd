extends Node3D

## Runs the survival loop: title, a short break before each wave, trickle-spawned
## enemies, and game over. The best wave is saved between runs.

enum Phase { TITLE, BREAK, FIGHT, OVER }

const SAVE_PATH := "user://rosomak.cfg"
const GRUNT := preload("res://scenes/enemies/grunt.tscn")
const RUNNER := preload("res://scenes/enemies/runner.tscn")
const BRUTE := preload("res://scenes/enemies/brute.tscn")

@export var break_time: float = 3.0
@export var spawn_interval: float = 0.8
## Each wave after the first adds this fraction of base health to every enemy.
@export var health_per_wave: float = 0.1
@export var kill_rage: float = 10.0

var phase: Phase = Phase.TITLE
var phase_time: float = 0.0
var wave: int = 0
var kills: int = 0
var best_wave: int = 0
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
	best_wave = _load_best()
	player.controls_enabled = false
	player.health_changed.connect(hud.set_health)
	player.rage_changed.connect(hud.set_rage)
	player.hit_chain_changed.connect(hud.set_hit_chain)
	player.hurt.connect(hud.flash_hurt)
	player.died.connect(_on_player_died)
	hud.set_health(player.max_health, player.max_health)
	hud.set_rage(0.0, false)
	hud.show_title(best_wave)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	if phase == Phase.TITLE:
		start_run()
	elif phase == Phase.OVER and phase_time > 1.5:
		get_tree().reload_current_scene()


func start_run() -> void:
	wave = 1
	kills = 0
	player.controls_enabled = true
	hud.pause_allowed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_enter_break()


func _process(delta: float) -> void:
	phase_time += delta
	match phase:
		Phase.BREAK:
			if phase_time >= break_time:
				_begin_wave()
		Phase.FIGHT:
			_spawn_timer -= delta
			if not _roster.is_empty() and alive < _max_alive() and _spawn_timer <= 0.0:
				_spawn(_roster.pop_back())
				_spawn_timer = spawn_interval
			elif _roster.is_empty() and alive == 0:
				Sfx.play(&"clear", 0.0, 0.0)
				hud.banner("FALA %d ODPARTA" % wave, "Rosomak się regeneruje…", 1.8)
				wave += 1
				_enter_break(1.8)


func _enter_break(delay: float = 0.0) -> void:
	phase = Phase.BREAK
	phase_time = -delay
	hud.set_wave(wave)
	_roster = build_roster(wave)
	hud.set_counts(_roster.size(), kills)
	if delay <= 0.0:
		_announce_wave()
	else:
		get_tree().create_timer(delay, false).timeout.connect(_announce_wave)


func _announce_wave() -> void:
	if phase != Phase.BREAK:
		return
	var subtitle := "Przygotuj się"
	if wave == 2:
		subtitle = "Uwaga na szybkich — zielonych"
	elif wave == 3:
		subtitle = "Nadchodzi brutal — fioletowy, odporny na lekkie ciosy"
	hud.banner("FALA %d" % wave, subtitle, break_time - 0.6)


func _begin_wave() -> void:
	phase = Phase.FIGHT
	phase_time = 0.0
	_spawn_timer = 0.0
	# Later waves let a third enemy swing at once.
	Enemy.max_attackers = 2 if wave < 5 else 3
	Sfx.play(&"wave", 0.0, 0.0)


## Wave n: more grunts every wave, runners from wave 2, brutes from wave 3.
static func build_roster(wave_number: int) -> Array[PackedScene]:
	var roster: Array[PackedScene] = []
	for i in 2 + wave_number:
		roster.append(GRUNT)
	for i in maxi(0, wave_number - 1):
		roster.append(RUNNER)
	for i in maxi(0, (wave_number - 1) / 2):
		roster.append(BRUTE)
	roster.shuffle()
	return roster


func _max_alive() -> int:
	return mini(3 + wave, 8)


func _spawn(scene: PackedScene) -> void:
	var enemy := scene.instantiate() as Enemy
	enemy.max_health = roundi(enemy.max_health * (1.0 + health_per_wave * (wave - 1)))
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


func _on_enemy_died(_enemy: Enemy) -> void:
	alive -= 1
	kills += 1
	player.add_rage(kill_rage)
	hud.set_counts(alive + _roster.size(), kills)


func _on_player_died() -> void:
	phase = Phase.OVER
	phase_time = 0.0
	hud.pause_allowed = false
	var new_record := wave > best_wave
	if new_record:
		best_wave = wave
		_save_best()
	Sfx.play(&"game_over", 0.0, 0.0)
	await get_tree().create_timer(1.4).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_game_over(wave, kills, best_wave, new_record)


func _load_best() -> int:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0
	return int(config.get_value("records", "best_wave", 0))


func _save_best() -> void:
	var config := ConfigFile.new()
	config.set_value("records", "best_wave", best_wave)
	config.save(SAVE_PATH)
