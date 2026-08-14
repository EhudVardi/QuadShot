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
	_streams[&"charge"] = _make_charge()
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


## Looping motor tone for ONE rotor, built at that rotor's own fundamental.
##
## THE TONE IS BAKED PER FRAME RATHER THAN PITCH-SHIFTED, and the reason is the
## size ladder (V10). A 0.28 m rotor and a 3 m rotor are nearly four octaves
## apart; reaching that by dragging `pitch_scale` down from one baked 120 Hz loop
## slows the whole waveform like a tape, which smears the blade chop into a
## flutter and thins out exactly the low end a big machine is supposed to have.
## Synthesising each frame's loop costs a few milliseconds once, at a frame swap.
##
## `bass` mixes in the sub-octave (weight and body, what a heavy rotor has) and
## `bright` the octave above (the whine of a small one). Callers ramp one up as
## the other comes down, so the timbre changes with size and not just the pitch.
##
## The buffer holds a whole number of cycles of BOTH the fundamental and the
## sub-octave — hence the even cycle count and the re-derived `exact_hz` — or the
## loop seam clicks once per pass, which is the most audible defect a looping
## synth can have.
## `phase_seed` gives each rotor its own waveform SHAPE at the identical spectrum:
## the partials are the same frequencies, started at different phases. Four
## sources sharing one buffer sum like one louder source; four with scrambled
## phases comb against each other into something thicker and less pointy, which
## is width you do not have to pay for in detune (see motor_audio.gd's beat-rate
## rule). A phase offset never breaks the loop — each partial still completes a
## whole number of cycles in the buffer.
static func make_motor_loop(fundamental_hz: float, bass: float,
		bright: float, phase_seed: int = 0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x40702 + phase_seed
	var saw_phase: float = rng.randf()
	var octave_phase: float = rng.randf()
	var sub_phase: float = rng.randf()
	var hz: float = maxf(fundamental_hz, 20.0)
	var cycles: int = maxi(16, int(round(hz * 0.25)))
	if cycles % 2 == 1:
		cycles += 1
	var count: int = int(round(float(cycles) * MIX_RATE / hz))
	var exact_hz: float = float(cycles) * MIX_RATE / float(count)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var peak: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var phase: float = exact_hz * t
		# Saw for the blade chop, sine for the sub — a saw an octave down would
		# add harmonics that land back on the fundamental and muddy it.
		var saw: float = fmod(phase + saw_phase, 1.0) * 2.0 - 1.0
		var octave: float = fmod(phase * 2.0 + octave_phase, 1.0) * 2.0 - 1.0
		var sub: float = sin(TAU * (phase * 0.5 + sub_phase))
		var value: float = saw * 0.35 + octave * 0.15 * bright + sub * 0.55 * bass
		samples[i] = value
		peak = maxf(peak, absf(value))
	# Normalise so timbre choices never change the level — the level is the
	# caller's decision, and a bassier loop being louder for free would put the
	# size-to-loudness relationship back somewhere nobody can see it.
	if peak > 0.0001:
		var scale: float = 0.9 / peak
		for i: int in count:
			samples[i] *= scale
	return _make_wav(samples, true)


## Looping EW jam: a warbling carrier under a band of hiss — the sound of a video
## link losing its argument (P4.2's screamer). Two detuned tones beating against
## each other give the warble for free, and the beat frequency is what makes it
## read as INTERFERENCE rather than as an engine.
##
## Volume and pitch are driven live by the jam level at the player (screamer.gd),
## so the cue and the mechanic are the same number.
static func make_jam_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5CEA11
	# Exactly 2 s so the 7 Hz beat closes on itself at the loop seam.
	var count: int = int(2.0 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var hiss: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var carrier: float = sin(TAU * 320.0 * t) + sin(TAU * 327.0 * t)
		hiss += 0.25 * (rng.randf_range(-1.0, 1.0) - hiss)
		# The sweep is what stops it sitting still in the ear — a jam that is one
		# steady tone stops being heard within seconds.
		var sweep: float = 0.6 + 0.4 * sin(TAU * 0.4 * t)
		samples[i] = clampf(carrier * 0.22 * sweep + hiss * 0.5, -1.0, 1.0)
	return _make_wav(samples, true)


## THE LANCE'S PROXIMITY WARNING (A.q8). A pulsed alarm over a continuous bed,
## looping, with volume AND pulse rate driven live by how close the thing is to
## killing you (`lance.gd`, `_update_warning`).
##
## It is a second cue rather than a louder `charge`, and the distinction is the
## whole request. `charge` is a 1.05 s one-shot at the start of the wind-up: it
## says *a Lance has committed* and then goes quiet for the entire run, which is
## the stretch where the information is worth most. The user flew exactly that and
## asked for *"a continous warning sound that increase the more the danger is
## close"* — the classic missile-warning idiom, where the cue is not an event but
## a live readout.
##
## TWO LAYERS, and both are load-bearing:
##
##   the PULSE  is the urgency. Nothing else in the bank beats at a steady rate,
##              and driving `pitch_scale` speeds the beat up as well as raising
##              the tone — one dial, two dimensions of alarm, for free.
##   the BED    is the *continuous* half the user asked for. Pulses alone read as
##              intermittent at low intensity, and a warning with gaps in it is a
##              warning you can be half way through missing.
##
## Each pulse FALLS in pitch, which is what separates it from `lock` (two rising
## pips, the friendly one): rising is confirmation, falling is alarm.
static func make_warning_loop() -> AudioStreamWAV:
	# Exactly 0.5 s holding exactly two pulses, so the gate is silent at the loop
	# seam and the bed's 98 Hz closes on a whole number of cycles. A seam that
	# clicks twice a second would be the loudest thing in the cue.
	var count: int = int(0.5 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	var bed_phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var within: float = fmod(t, 0.25)
		# 4 Hz at rest, ~8 Hz once the pitch is driven to 1.9 inside the fuse.
		var gate: float = exp(-within * 26.0) if within < 0.16 else 0.0
		phase += TAU * (780.0 - 160.0 * (within / 0.16)) / MIX_RATE
		bed_phase += TAU * 98.0 / MIX_RATE
		var pulse: float = (sin(phase) * 0.72 + sin(phase * 3.0) * 0.28) * gate
		samples[i] = clampf(pulse * 0.5 + sin(bed_phase) * 0.14, -1.0, 1.0)
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


## THE LANCE'S TELEGRAPH (A5). A rising tone that arrives somewhere, so the ear
## can tell how far through the wind-up the thing is without looking at it.
##
## It has to be UNMISTAKABLE against the rest of the bank, which is why it sweeps
## instead of pulsing: `lock` is a two-tone beep, `shot` is a click, `launch` is
## noise. The user asked for it in exactly those terms after flying the glow —
## *"i think it should have a different sound just to differentiate"* — and the
## reason it matters is P4.4's readability rule: a telegraph you can only see is
## a telegraph you miss whenever you are looking somewhere else, which against a
## thing that attacks from any bearing is most of the time.
##
## The sweep runs a shade under `Lance.ALIGN_SECONDS` so it FINISHES as the run
## begins rather than being cut off by it.
static func _make_charge() -> AudioStreamWAV:
	var count: int = int(1.05 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var progress: float = t / 1.05
		# Accelerating sweep: slow at first, urgent at the end, so the last
		# quarter-second reads as "now" rather than as more of the same.
		var freq: float = 220.0 + 700.0 * progress * progress
		phase += TAU * freq / MIX_RATE
		# A hard second harmonic keeps it from sounding like a UI tone.
		var tone: float = sin(phase) * 0.7 + sin(phase * 2.0) * 0.3
		var envelope: float = minf(t / 0.08, 1.0) * (0.35 + 0.65 * progress)
		samples[i] = tone * 0.32 * envelope
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
