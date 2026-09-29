extends Node

## Autoloaded as `Sfx`. A tiny synthesized sound kit: every sound is generated once at
## startup from math, so the project still ships no audio assets.

const RATE := 22050
const VOICES := 12

var _streams: Dictionary = {}
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
func play(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if not _streams.has(sound):
		return
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func _build_sounds() -> void:
	# Filter state lives in arrays because lambdas capture locals by value.
	var low := [0.0]
	_streams[&"swing"] = _render(0.14, func(t: float, p: float) -> float:
		low[0] = lerpf(low[0], randf_range(-1.0, 1.0), 0.08 + 0.35 * p)
		return low[0] * sin(PI * p) * 1.4
	)
	var whoosh := [0.0]
	_streams[&"dodge"] = _render(0.2, func(t: float, p: float) -> float:
		whoosh[0] = lerpf(whoosh[0], randf_range(-1.0, 1.0), 0.05 + 0.12 * sin(PI * p))
		return whoosh[0] * sin(PI * p) * 1.6
	)
	_streams[&"hit"] = _render(0.18, func(t: float, p: float) -> float:
		var thump := sin(TAU * t * lerpf(150.0, 45.0, p)) * exp(-t * 26.0)
		return thump * 0.9 + randf_range(-1.0, 1.0) * exp(-t * 110.0) * 0.6
	)
	_streams[&"heavy_hit"] = _render(0.32, func(t: float, p: float) -> float:
		var thump := sin(TAU * t * lerpf(120.0, 32.0, p)) * exp(-t * 14.0)
		return clampf(thump * 1.4, -1.0, 1.0) * 0.9 + randf_range(-1.0, 1.0) * exp(-t * 45.0) * 0.55
	)
	_streams[&"hurt"] = _render(0.24, func(t: float, p: float) -> float:
		var square := signf(sin(TAU * t * lerpf(280.0, 110.0, p)))
		return square * pow(1.0 - p, 1.5) * 0.35 + randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.4
	)
	var fall := [0.0]
	_streams[&"enemy_die"] = _render(0.5, func(t: float, p: float) -> float:
		fall[0] = lerpf(fall[0], randf_range(-1.0, 1.0), lerpf(0.4, 0.03, p))
		var tone := sin(TAU * t * lerpf(220.0, 55.0, p))
		return (fall[0] * 0.7 + tone * 0.4) * pow(1.0 - p, 1.2)
	)
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


func _chime(notes: Array, duration: float) -> AudioStreamWAV:
	var step := duration / notes.size()
	return _render(duration, func(t: float, p: float) -> float:
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
		# A few-sample fade-in avoids clicks on sounds that start at full amplitude.
		value *= minf(1.0, i / 64.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
