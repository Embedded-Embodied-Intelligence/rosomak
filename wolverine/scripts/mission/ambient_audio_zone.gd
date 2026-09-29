class_name AmbientAudioZone
extends Area3D

## Cheap facility ambience that fades in while the player is inside the volume.

enum Mood { HUM, ALARM, LAB, EXTERIOR }

@export var zone_id: StringName = &"zone"
@export var mood: Mood = Mood.HUM
@export var volume_db: float = -22.0

var _player_audio: AudioStreamPlayer3D
var _inside: bool = false
static var _streams: Dictionary = {}


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2 ## Player body
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not has_node("CollisionShape3D"):
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10, 6, 16)
		col.shape = box
		col.position = Vector3(0, 3, 0)
		add_child(col)
	_ensure_streams()
	_player_audio = AudioStreamPlayer3D.new()
	_player_audio.stream = _streams[mood]
	_player_audio.volume_db = -80.0
	_player_audio.max_distance = 40.0
	_player_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_player_audio)


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
	if not _player_audio.playing:
		_player_audio.play()
	var tween := create_tween()
	tween.tween_property(_player_audio, "volume_db", volume_db, 0.8)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_inside = false
	var tween := create_tween()
	tween.tween_property(_player_audio, "volume_db", -80.0, 0.9)
	tween.tween_callback(func() -> void:
		if not _inside:
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
