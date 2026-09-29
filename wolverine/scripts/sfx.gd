extends Node

## Autoloaded as `Sfx`. Synthesized combat kit — 3–5 variants per category with pitch jitter.
## Categories: swing, dodge, flesh_hit, heavy_hit, finisher, grab, throw, wall, counter, hurt, die.

const RATE := 22050
const VOICES := 16

var _streams: Dictionary = {}
var _variants: Dictionary = {} # StringName -> Array[AudioStreamWAV]
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_build_sounds()


## Plays a named sound on the next free voice; unknown names are ignored.
## Prefer play_variant for layered combat categories.
func play(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if _variants.has(sound):
		_play_stream(_pick_variant(sound), volume_db, pitch_jitter)
		return
	if not _streams.has(sound):
		return
	_play_stream(_streams[sound], volume_db, pitch_jitter)


func play_layered(primary: StringName, secondary: StringName, volume_db: float = 0.0) -> void:
	play(primary, volume_db, 0.05)
	play(secondary, volume_db - 4.0, 0.08)


func active_voice_count() -> int:
	var n := 0
	for player in _players:
		if player.playing:
			n += 1
	return n


func _play_stream(stream: AudioStream, volume_db: float, pitch_jitter: float) -> void:
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func _pick_variant(sound: StringName) -> AudioStreamWAV:
	var list: Array = _variants[sound]
	return list[randi() % list.size()]


func _add_variants(name: StringName, builders: Array) -> void:
	var list: Array[AudioStreamWAV] = []
	for builder in builders:
		list.append(builder.call())
	_variants[name] = list
	_streams[name] = list[0]


func _build_sounds() -> void:
	_add_variants(&"swing", [
		func() -> AudioStreamWAV: return _whoosh(0.12, 0.08, 1.4),
		func() -> AudioStreamWAV: return _whoosh(0.14, 0.1, 1.5),
		func() -> AudioStreamWAV: return _whoosh(0.11, 0.06, 1.3),
		func() -> AudioStreamWAV: return _whoosh(0.16, 0.12, 1.6),
	])
	_add_variants(&"dodge", [
		func() -> AudioStreamWAV: return _whoosh(0.18, 0.05, 1.5),
		func() -> AudioStreamWAV: return _whoosh(0.2, 0.04, 1.7),
		func() -> AudioStreamWAV: return _whoosh(0.16, 0.06, 1.4),
	])
	_add_variants(&"footstep", [
		func() -> AudioStreamWAV: return _footstep(0.08, 0.55),
		func() -> AudioStreamWAV: return _footstep(0.09, 0.5),
		func() -> AudioStreamWAV: return _footstep(0.07, 0.6),
	])
	_add_variants(&"hit", [
		func() -> AudioStreamWAV: return _impact(0.16, 150.0, 45.0, 26.0),
		func() -> AudioStreamWAV: return _impact(0.15, 170.0, 50.0, 28.0),
		func() -> AudioStreamWAV: return _impact(0.18, 140.0, 40.0, 24.0),
		func() -> AudioStreamWAV: return _impact(0.14, 160.0, 48.0, 30.0),
	])
	_add_variants(&"flesh_hit", [
		func() -> AudioStreamWAV: return _flesh(0.16, 0.7),
		func() -> AudioStreamWAV: return _flesh(0.18, 0.8),
		func() -> AudioStreamWAV: return _flesh(0.14, 0.65),
		func() -> AudioStreamWAV: return _flesh(0.2, 0.85),
	])
	_add_variants(&"heavy_hit", [
		func() -> AudioStreamWAV: return _impact(0.3, 110.0, 28.0, 12.0, 1.4),
		func() -> AudioStreamWAV: return _impact(0.34, 100.0, 26.0, 11.0, 1.5),
		func() -> AudioStreamWAV: return _impact(0.28, 120.0, 32.0, 13.0, 1.35),
	])
	_add_variants(&"finisher_hit", [
		func() -> AudioStreamWAV: return _finisher(0.45),
		func() -> AudioStreamWAV: return _finisher(0.5),
		func() -> AudioStreamWAV: return _finisher(0.4),
	])
	_streams[&"finisher_start"] = _render(0.35, func(t: float, p: float) -> float:
		return sin(TAU * t * lerpf(90.0, 40.0, p)) * (1.0 - p) * 0.45 + randf_range(-1.0, 1.0) * exp(-t * 20.0) * 0.3
	)
	_add_variants(&"grab", [
		func() -> AudioStreamWAV: return _grab_thud(0.2),
		func() -> AudioStreamWAV: return _grab_thud(0.22),
		func() -> AudioStreamWAV: return _grab_thud(0.18),
	])
	_streams[&"grab_resist"] = _render(0.15, func(t: float, p: float) -> float:
		return signf(sin(TAU * t * 90.0)) * (1.0 - p) * 0.25 + randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.35
	)
	_add_variants(&"throw", [
		func() -> AudioStreamWAV: return _whoosh(0.22, 0.07, 1.8),
		func() -> AudioStreamWAV: return _whoosh(0.2, 0.08, 1.6),
		func() -> AudioStreamWAV: return _whoosh(0.24, 0.06, 1.9),
	])
	_add_variants(&"wall_impact", [
		func() -> AudioStreamWAV: return _wall(0.28),
		func() -> AudioStreamWAV: return _wall(0.32),
		func() -> AudioStreamWAV: return _wall(0.26),
	])
	_streams[&"wall_slam"] = _wall(0.4)
	_streams[&"counter"] = _impact(0.22, 200.0, 60.0, 18.0, 1.3)
	_streams[&"counter_ready"] = _render(0.08, func(t: float, p: float) -> float:
		return sin(TAU * t * 1400.0) * (1.0 - p) * 0.3
	)
	_add_variants(&"hurt", [
		func() -> AudioStreamWAV: return _hurt(0.22),
		func() -> AudioStreamWAV: return _hurt(0.24),
		func() -> AudioStreamWAV: return _hurt(0.2),
	])
	_add_variants(&"enemy_die", [
		func() -> AudioStreamWAV: return _die(0.45),
		func() -> AudioStreamWAV: return _die(0.5),
		func() -> AudioStreamWAV: return _die(0.55),
		func() -> AudioStreamWAV: return _die(0.4),
	])
	_streams[&"telegraph"] = _render(0.09, func(t: float, p: float) -> float:
		return sin(TAU * t * 1250.0) * (1.0 - p) * 0.35
	)
	_streams[&"rage"] = _render(0.8, func(t: float, p: float) -> float:
		var frequency := lerpf(70.0, 180.0, sqrt(p))
		var saw := fmod(t * frequency, 1.0) * 2.0 - 1.0
		var growl := saw * (0.7 + 0.3 * sin(TAU * t * 23.0))
		return clampf(growl * 1.8, -1.0, 1.0) * sin(PI * p) * 0.55
	)
	_streams[&"wave"] = _chime([392.0, 523.25], 0.7)
	_streams[&"clear"] = _chime([523.25, 659.25, 783.99], 0.9)
	_streams[&"game_over"] = _chime([392.0, 311.13, 261.63], 1.1)
	_streams[&"door_open"] = _render(0.55, func(t: float, p: float) -> float:
		var grind := sin(TAU * t * lerpf(90.0, 40.0, p)) * (1.0 - p)
		return grind * 0.35 + randf_range(-1.0, 1.0) * exp(-t * 8.0) * 0.25
	)
	_streams[&"power_fail"] = _render(0.7, func(t: float, p: float) -> float:
		var drop := sin(TAU * t * lerpf(200.0, 40.0, p)) * pow(1.0 - p, 0.6)
		return drop * 0.45 + randf_range(-1.0, 1.0) * exp(-t * 12.0) * 0.35
	)
	_streams[&"glass"] = _render(0.35, func(t: float, p: float) -> float:
		return randf_range(-1.0, 1.0) * exp(-t * 18.0) * 0.7 + sin(TAU * t * 2400.0) * exp(-t * 40.0) * 0.3
	)
	_streams[&"alarm"] = _render(0.9, func(t: float, p: float) -> float:
		var siren := sin(TAU * t * lerpf(680.0, 920.0, absf(sin(PI * p * 2.0))))
		return siren * 0.22 * sin(PI * p)
	)
	_streams[&"spark"] = _render(0.12, func(t: float, p: float) -> float:
		return randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.8
	)
	_streams[&"mission_complete"] = _chime([523.25, 659.25, 783.99, 1046.5], 1.4)


func _footstep(duration: float, amp: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		var thump := sin(TAU * t * lerpf(110.0, 55.0, p)) * exp(-t * 55.0)
		var grit := randf_range(-1.0, 1.0) * exp(-t * 80.0)
		return (thump * 0.7 + grit * 0.35) * amp * (1.0 - p)
	)


func _whoosh(duration: float, filter: float, amp: float) -> AudioStreamWAV:
	var low := [0.0]
	return _render(duration, func(_t: float, p: float) -> float:
		low[0] = lerpf(low[0], randf_range(-1.0, 1.0), filter + 0.2 * p)
		return low[0] * sin(PI * p) * amp
	)


func _impact(duration: float, f0: float, f1: float, decay: float, amp: float = 1.0) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		var thump := sin(TAU * t * lerpf(f0, f1, p)) * exp(-t * decay)
		return clampf(thump * amp, -1.0, 1.0) * 0.9 + randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.5
	)


func _flesh(duration: float, wet: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		var body := sin(TAU * t * lerpf(180.0, 50.0, p)) * exp(-t * 22.0)
		var splat := randf_range(-1.0, 1.0) * exp(-t * 55.0) * wet
		return body * 0.7 + splat * 0.55
	)


func _finisher(duration: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		var boom := sin(TAU * t * lerpf(90.0, 28.0, p)) * exp(-t * 8.0)
		var shred := randf_range(-1.0, 1.0) * exp(-t * 25.0)
		return clampf(boom * 1.5 + shred * 0.7, -1.0, 1.0) * 0.85
	)


func _grab_thud(duration: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		return sin(TAU * t * lerpf(80.0, 35.0, p)) * exp(-t * 14.0) * 0.8 + randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.3
	)


func _wall(duration: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		var crack := sin(TAU * t * lerpf(70.0, 25.0, p)) * exp(-t * 10.0)
		var grit := randf_range(-1.0, 1.0) * exp(-t * 18.0)
		return clampf(crack * 1.3 + grit * 0.6, -1.0, 1.0) * 0.8
	)


func _hurt(duration: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, p: float) -> float:
		var square := signf(sin(TAU * t * lerpf(280.0, 110.0, p)))
		return square * pow(1.0 - p, 1.5) * 0.35 + randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.4
	)


func _die(duration: float) -> AudioStreamWAV:
	var fall := [0.0]
	return _render(duration, func(t: float, p: float) -> float:
		fall[0] = lerpf(fall[0], randf_range(-1.0, 1.0), lerpf(0.4, 0.03, p))
		var tone := sin(TAU * t * lerpf(220.0, 55.0, p))
		return (fall[0] * 0.7 + tone * 0.4) * pow(1.0 - p, 1.2)
	)


func _chime(notes: Array, duration: float) -> AudioStreamWAV:
	var step := duration / notes.size()
	return _render(duration, func(t: float, _p: float) -> float:
		var index := mini(int(t / step), notes.size() - 1)
		var local := t - index * step
		var frequency: float = notes[index]
		var tone := sin(TAU * t * frequency) + 0.35 * sin(TAU * t * frequency * 2.0)
		return tone * exp(-local * 7.0) * 0.4
	)


func _render(duration: float, sample: Callable) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var value: float = sample.call(t, t / duration)
		value *= minf(1.0, i / 64.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
