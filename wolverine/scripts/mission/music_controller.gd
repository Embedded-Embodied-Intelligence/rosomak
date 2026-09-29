class_name MusicController
extends Node

## Simple looped bed crossfades: EXPLORATION / COMBAT / FINAL_COMBAT / MISSION_COMPLETE.
## Intensity accents: COMBAT_LOW / COMBAT_HIGH / FINAL — duck/boost without rewriting beds.

enum Bed { SILENCE, EXPLORATION, COMBAT, FINAL_COMBAT, MISSION_COMPLETE }
enum Intensity { NONE, COMBAT_LOW, COMBAT_HIGH, FINAL }

const RATE := 22050
const CROSSFADE := 1.1

var current: Bed = Bed.SILENCE
var intensity: Intensity = Intensity.NONE
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _active_index: int = 0
var _fade_tween: Tween
var _base_db: float = -14.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	_streams[Bed.EXPLORATION] = _build_drone(55.0, 82.5, 0.035)
	_streams[Bed.COMBAT] = _build_pulse(90.0, 135.0, 0.055)
	_streams[Bed.FINAL_COMBAT] = _build_pulse(70.0, 175.0, 0.07)
	_streams[Bed.MISSION_COMPLETE] = _build_resolve()


func set_bed(bed: Bed, immediate: bool = false) -> void:
	if bed == current and not immediate:
		return
	current = bed
	if bed == Bed.SILENCE:
		_fade_to(-1, -80.0 if immediate else null)
		return
	var next := 1 - _active_index
	_players[next].stream = _streams[bed]
	_players[next].play()
	if immediate:
		_players[_active_index].volume_db = -80.0
		_players[_active_index].stop()
		_players[next].volume_db = _base_db
		_active_index = next
		_apply_intensity_db()
		return
	_fade_cross(_active_index, next)


## Accent combat beds: LOW softer, HIGH hotter, FINAL hottest. Call from mission phases.
func set_intensity(level: Intensity) -> void:
	intensity = level
	_apply_intensity_db()


func _apply_intensity_db() -> void:
	match intensity:
		Intensity.COMBAT_LOW:
			_base_db = -16.0
		Intensity.COMBAT_HIGH:
			_base_db = -12.0
		Intensity.FINAL:
			_base_db = -10.0
		_:
			_base_db = -14.0
	if current != Bed.SILENCE:
		_players[_active_index].volume_db = _base_db


func _fade_cross(from_i: int, to_i: int) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_players[to_i].volume_db = -80.0
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(_players[from_i], "volume_db", -80.0, CROSSFADE)
	_fade_tween.tween_property(_players[to_i], "volume_db", _base_db, CROSSFADE)
	_fade_tween.chain().tween_callback(func() -> void:
		_players[from_i].stop()
		_active_index = to_i
	)


func _fade_to(_unused: int, _db) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for player in _players:
		_fade_tween.tween_property(player, "volume_db", -80.0, CROSSFADE)
	_fade_tween.chain().tween_callback(func() -> void:
		for player in _players:
			player.stop()
	)


func _build_drone(f1: float, f2: float, amp: float) -> AudioStreamWAV:
	var duration := 4.0
	return _loop_wav(duration, func(t: float, _p: float) -> float:
		var a := sin(TAU * t * f1) * 0.55 + sin(TAU * t * f2) * 0.35
		var slow := 0.85 + 0.15 * sin(TAU * t * 0.25)
		return a * amp * slow
	)


func _build_pulse(f1: float, f2: float, amp: float) -> AudioStreamWAV:
	var duration := 2.0
	return _loop_wav(duration, func(t: float, p: float) -> float:
		var beat := pow(1.0 - fmod(p * 4.0, 1.0), 2.0)
		var tone := sin(TAU * t * f1) * 0.5 + sin(TAU * t * f2) * 0.25
		return (tone * 0.4 + beat * sin(TAU * t * 55.0) * 0.6) * amp
	)


func _build_resolve() -> AudioStreamWAV:
	return _loop_wav(3.0, func(t: float, p: float) -> float:
		var notes := [523.25, 659.25, 783.99]
		var idx := mini(int(p * notes.size()), notes.size() - 1)
		var f: float = notes[idx]
		return sin(TAU * t * f) * exp(-fmod(t, 1.0) * 2.5) * 0.08
	)


func _loop_wav(duration: float, sample: Callable) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var value: float = sample.call(t, t / duration)
		value *= minf(1.0, minf(i, count - i) / 256.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav
