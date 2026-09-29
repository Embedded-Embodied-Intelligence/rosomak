class_name AmbientAudioZone
extends Area3D

## Cheap facility ambience that fades in while the player is inside the volume.

enum Mood { HUM, ALARM, LAB, EXTERIOR }

@export var zone_id: StringName = &"zone"
@export var mood: Mood = Mood.HUM
@export var volume_db: float = -22.0

var _player_audio: AudioStreamPlayer3D
var _inside: bool = false
var _collision: CollisionShape3D
static var _streams: Dictionary = {}


func _ready() -> void:
	configure(Vector3(10, 6, 16))


func configure(size: Vector3 = Vector3(10, 6, 16)) -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2 ## Player body
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_ensure_collision(size)
	_ensure_streams()
	if _player_audio == null:
		_player_audio = AudioStreamPlayer3D.new()
		_player_audio.stream = _streams[mood]
		_player_audio.volume_db = -80.0
		_player_audio.max_distance = 40.0
		_player_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(_player_audio)
	else:
		_player_audio.stream = _streams[mood]


func _ensure_collision(size: Vector3) -> void:
	if _collision == null:
		_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "CollisionShape3D"
		add_child(_collision)
	var box := (_collision.shape as BoxShape3D)
	if box == null:
		box = BoxShape3D.new()
		_collision.shape = box
	box.size = size
	_collision.position = Vector3(0, size.y * 0.5, 0)


func _ensure_streams() -> void:
	if not _streams.is_empty():
		return
	_streams[Mood.HUM] = _make(70.0, 0.04)
	_streams[Mood.ALARM] = _make_alarm()
	_streams[Mood.LAB] = _make(110.0, 0.03)
	_streams[Mood.EXTERIOR] = _make(40.0, 0.025)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_inside = true
	if _player_audio == null:
		return
	if not _player_audio.playing:
		_player_audio.play()
	var tween := create_tween()
	tween.tween_property(_player_audio, "volume_db", volume_db, 0.8)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_inside = false
	if _player_audio == null:
		return
	var tween := create_tween()
	tween.tween_property(_player_audio, "volume_db", -80.0, 0.9)
	tween.tween_callback(func() -> void:
		if not _inside and _player_audio:
			_player_audio.stop()
	)


func _make(freq: float, amp: float) -> AudioStreamWAV:
	return _render(3.0, func(t: float, _p: float) -> float:
		return (sin(TAU * t * freq) * 0.5 + sin(TAU * t * freq * 1.5) * 0.25) * amp
	)


func _make_alarm() -> AudioStreamWAV:
	return _render(1.2, func(t: float, p: float) -> float:
		var siren := sin(TAU * t * lerpf(620.0, 880.0, absf(sin(PI * p))))
		return siren * 0.045 * (0.4 + 0.6 * absf(sin(PI * p * 2.0)))
	)


func _render(duration: float, sample: Callable) -> AudioStreamWAV:
	const RATE := 22050
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var value: float = sample.call(t, t / duration)
		value *= minf(1.0, minf(i, count - i) / 128.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav
