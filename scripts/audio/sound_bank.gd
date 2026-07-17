class_name SoundBank
extends Node

## Procedurally synthesized placeholder audio — no external assets, per
## house rules; replace per the roadmap asset-policy decision. A single node
## in main.tscn registers itself as the static instance; the static API is
## null-safe so scenes without it (headless drone-only tests) stay silent
## instead of crashing. One-shots play through a small round-robin pool of
## 3D players; loop factories serve the drone's motor/wind emitters.
##
## Waveform constants are aesthetic placeholder choices, not flight/input
## tunables — exempt from the config rule.

const MIX_RATE: int = 22050
const PLAYER_COUNT: int = 16

static var _instance: SoundBank

@export var audio_config: AudioConfig

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
var _muffle: AudioEffectLowPassFilter
var _muffle_index: int = -1


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	if audio_config.load_from_user():
		print("[config] loaded %s" % audio_config.save_path())
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE
	_streams[&"shot"] = _make_shot()
	_streams[&"explosion"] = _make_explosion(rng)
	_streams[&"lock"] = _make_lock()
	_streams[&"launch"] = _make_launch(rng)
	for i: int in PLAYER_COUNT:
		var player := AudioStreamPlayer3D.new()
		player.max_distance = 250.0
		add_child(player)
		_players.append(player)
	# Pause muffle: a Master-bus low-pass, disabled until slow-mo engages.
	_muffle = AudioEffectLowPassFilter.new()
	_muffle_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, _muffle)
	AudioServer.set_bus_effect_enabled(0, _muffle_index, false)


## The "stepped out of the club" effect while pause/slow-mo is active.
static func set_muffled(muffled: bool) -> void:
	if _instance == null or _instance._muffle_index < 0:
		return
	var cutoff: float = _instance.audio_config.pause_muffle_hz
	_instance._muffle.cutoff_hz = maxf(cutoff, 40.0)
	AudioServer.set_bus_effect_enabled(0, _instance._muffle_index,
			muffled and cutoff > 0.0)


func _process(_delta: float) -> void:
	# Master gain on the Master bus, re-read every frame so overlay tuning is live.
	AudioServer.set_bus_volume_db(0, AudioConfig.gain_to_db(audio_config.master_volume))


static func play_at(sound: StringName, position: Vector3, volume_db: float = 0.0,
		pitch_jitter: float = 0.1) -> void:
	# Null-safe and headless-safe: silent no-op in tests (see motor_audio.gd).
	if _instance == null or DisplayServer.get_name() == "headless":
		return
	_instance._play_at(sound, position, volume_db, pitch_jitter)


func _play_at(sound: StringName, position: Vector3, volume_db: float,
		pitch_jitter: float) -> void:
	var stream: AudioStreamWAV = _streams.get(sound)
	if stream == null:
		return
	# Round-robin steals the oldest player when all are busy.
	var player: AudioStreamPlayer3D = _players[_next_player]
	_next_player = (_next_player + 1) % PLAYER_COUNT
	player.stop()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db + AudioConfig.gain_to_db(audio_config.sfx_volume)
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## Looping motor tone: saw fundamental + octave, pitch-scaled live by
## motor_audio.gd.
static func make_motor_loop() -> AudioStreamWAV:
	var count: int = int(0.5 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i: int in count:
		phase += 120.0 / MIX_RATE
		var saw: float = fmod(phase, 1.0) * 2.0 - 1.0
		var octave: float = fmod(phase * 2.0, 1.0) * 2.0 - 1.0
		samples[i] = saw * 0.35 + octave * 0.15
	return _make_wav(samples, true)


## Looping wind rush: one-pole lowpassed noise, crossfaded at the seam.
static func make_wind_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB1E55
	var count: int = int(1.0 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low: float = 0.0
	for i: int in count:
		low += 0.04 * (rng.randf_range(-1.0, 1.0) - low)
		samples[i] = low * 3.0
	var fade: int = int(0.05 * MIX_RATE)
	for k: int in fade:
		var t: float = float(k) / float(fade)
		samples[count - fade + k] = lerpf(samples[count - fade + k], samples[k], t)
	return _make_wav(samples, true)


static func _make_shot() -> AudioStreamWAV:
	var duration: float = 0.14
	var count: int = int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		phase += lerpf(1600.0, 280.0, t / duration) / MIX_RATE
		var saw: float = fmod(phase, 1.0) * 2.0 - 1.0
		samples[i] = saw * 0.55 * exp(-t * 26.0)
	return _make_wav(samples)


static func _make_explosion(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var count: int = int(1.1 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		low += 0.08 * (rng.randf_range(-1.0, 1.0) - low)
		var thump: float = sin(TAU * 55.0 * t) * exp(-t * 7.0)
		samples[i] = clampf(low * 2.2 * exp(-t * 3.5) + thump * 0.8, -1.0, 1.0)
	return _make_wav(samples)


## Lock-acquired: two rising sine pips.
static func _make_lock() -> AudioStreamWAV:
	var count: int = int(0.22 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var freq: float = 880.0 if t < 0.1 else 1320.0
		var gate: float = 1.0 if fmod(t, 0.11) < 0.08 else 0.0
		samples[i] = sin(TAU * freq * t) * 0.4 * gate
	return _make_wav(samples)


## Missile launch: noise whoosh swelling then fading, pitched down.
static func _make_launch(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var count: int = int(0.6 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		low += 0.15 * (rng.randf_range(-1.0, 1.0) - low)
		var envelope: float = minf(t / 0.06, 1.0) * exp(-t * 5.0)
		samples[i] = low * 2.5 * envelope
	return _make_wav(samples)


static func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav
