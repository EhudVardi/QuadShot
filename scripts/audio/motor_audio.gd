extends Node3D

## FOUR ROTORS, HEARD SEPARATELY (the user's ask, 2026-08-13: *"i wish the sound
## would be of all its engines (in this case 4) which is a composition of each
## individual sound source"*). One emitter per motor, at that motor's real mount,
## driven by that motor's own output — so an asymmetric hover, a damaged rotor
## and the yaw of a hard turn are all audible, and the stereo width of the sound
## is the airframe's actual span.
##
## IT REPLACES A SINGLE EMITTER THAT GOT QUIETER AS THE AIRCRAFT GOT BIGGER,
## which is worth recording because the cause was two separate numbers that both
## failed to scale, and neither was the "size factor with the wrong sign" it
## sounded like — there was no size factor at all:
##
##  1. **Volume was driven by motor output, which is a FRACTION of maximum
##     thrust.** Hover sits at 1/TWR, so the TWR-12 frames hovered at 8% stick
##     against the Kestrel's 22% and were rendered 3.6 dB quieter — while
##     actually moving five hundred kilograms of aircraft. Thrust is what makes
##     the noise, so `load` below is thrust in g (1.0 at hover on EVERY frame)
##     rather than stick position.
##  2. **`unit_size` was a fixed 10 m while chase distance scales with the
##     frame.** In chase view that put the Kestrel at +3 dB (clamped), the Condor
##     at -3.5 and the Roc at -12.6. Tying `unit_size` to the airframe's own body
##     size makes "one aircraft away" sound the same on every frame, which is the
##     only frame-independent thing a distance can mean here.
##
## Placeholder aesthetics constants, exempt from the config rule (see
## sound_bank.gd) — the mix is tuned by ear, not derived.

## The roster datum's arm and the tone that goes with it; every other frame is
## placed relative to these.
const REFERENCE_ARM_M: float = 0.12
const REFERENCE_BODY_M: float = 0.28
const REFERENCE_HZ: float = 420.0
## Blade-pass frequency really goes as 1/radius (tip speed is roughly constant
## across propeller sizes), which over this roster's 10.7x span would put the Roc
## near 11 Hz — under the audible floor and no longer a pitch at all. The
## exponent compresses the honest law into a range a speaker can render: 420 Hz
## whine / 163 Hz mid / 90 Hz bass across kestrel / condor / roc.
const PITCH_EXPONENT: float = 0.65
## unit_size as a multiple of body size. Chase sits near 14x body on every frame,
## so this puts every chase view at the same -11 dB regardless of scale.
const UNIT_SIZE_PER_BODY: float = 4.0
## Level of ONE ROTOR at hover (load 1.0), before the size bonus and the config's
## own gain. Set about 6 dB under what a single emitter wanted, because there are
## now four of them and four incoherent sources sum to roughly +6 dB — otherwise
## splitting one emitter into four would have been a loudness change wearing a
## spatialisation change's clothes.
const HOVER_DB: float = -30.0
## How hard thrust drives level. Rotor sound power grows faster than thrust, so
## this is a log law rather than the old linear ramp on stick position.
const LOAD_DB_PER_DECADE: float = 15.0
## The biggest frame is this much louder than the datum at the same load — the
## user's *"not nessecarily a lot louder but a little louder and with presence"*.
const SIZE_DB: float = 4.0
## The tone band: idle sits at 0.80x the baked fundamental and the sweep adds
## 1.20x on top, so a rotor spans a ratio of 2.5 — about an octave and a third —
## between idle and the top of its sweep.
##
## `RPM_SWEEP_TOP` is where the climb ENDS, as a fraction of full stick. Past it
## the tone holds and only the level keeps rising, which is the user's *"the tone
## climbs until the middle and then empehesized"* — the plateau is what makes the
## last of the throttle read as effort rather than as more noise. It is a
## fraction of STICK, so every frame gets the same shape regardless of TWR.
const PITCH_AT_IDLE: float = 0.80
const PITCH_SWEEP: float = 1.20
const RPM_SWEEP_TOP: float = 0.60
## Per-rotor detune, as multiples of a spacing `u` chosen per frame below. Evenly
## spaced on purpose: the six pairwise differences collapse to just u, 2u and 3u,
## so a single number decides every beat rate instead of six unrelated ones.
const DETUNE_STEPS: Array[float] = [-1.5, -0.5, 0.5, 1.5]


## The same even spacing for any rotor count: symmetric about zero, one step
## apart. Reproduces DETUNE_STEPS exactly at four, and gives six rotors
## -2.5 .. 2.5.
##
## **THE SPACING RULE GENERALISES; WHETHER SIX OF THEM SOUND RIGHT IS AN EAR
## QUESTION AND IS NOT ANSWERED HERE** (E.q1's second complication). The four-
## emitter scheme was tuned by ear in v2.43/v2.45, and six sources at the same
## per-pair beat rate is measurably a denser texture, not the same one. The hexa
## ships with the quad's numbers deliberately, and this wants a human before any
## of it is called done.
static func detune_step(index: int, count: int) -> float:
	return float(index) - float(count - 1) * 0.5
## THE BEAT-RATE RULE, and it is the whole fix for the Condor's *"noticeable
## repeating hum"*.
##
## Four detuned rotors beat against each other at (detune difference x pitch).
## **Fast beating is TEXTURE and slow beating is a DEFECT**, and human hearing
## peaks in sensitivity to amplitude modulation right around 4 Hz — exactly where
## the old fixed ratio put the Condor (1.5–5.9 Hz). The Kestrel escaped upward
## (3.8–15.1 Hz reads as shimmer) and the Roc escaped downward (0.8–3.2 Hz reads
## as a heavy engine breathing). Only the middle frame landed in the hole.
##
## So the detune is chosen to reach `BEAT_TARGET_HZ` — and when the fundamental
## is too low to get there inside `MAX_SPREAD` without sounding like a chord
## rather than an engine, it goes the OTHER WAY instead, to a drift so slow it
## cannot be heard as a pulse. It is never allowed to sit in between.
const BEAT_TARGET_HZ: float = 12.0
const MAX_SPREAD: float = 0.09
const BEAT_FLOOR_SPACING: float = 0.0008
## Level/pitch response, seconds. Bigger rotors carry more rotational inertia and
## spool audibly slower — the user's *"the slow reaction will give the slower and
## heavier feel"*. NOT the same knob as `motor_lag_tau`, which is flight and is
## the human's to tune.
const RESPONSE_TAU_MIN: float = 0.03
const RESPONSE_TAU_PER_BODY: float = 0.04

@export var audio_config: AudioConfig

var _drone: FlightController
var _players: Array[AudioStreamPlayer3D] = []
## Smoothed per-rotor thrust, in g. Hover is 1.0 on every frame.
var _load: PackedFloat32Array = PackedFloat32Array()
var _tau: float = RESPONSE_TAU_MIN
var _size_db: float = 0.0
## Per-rotor pitch offset, derived per frame by the beat-rate rule.
var _detune: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	# Headless (tests): active playbacks leak at quit() under the Dummy
	# audio driver, and nothing hears them anyway.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_drone = owner as FlightController
	# The airframe can change under us (V10's size ladder), and the whole point
	# of this node is that its tone and spacing ARE the airframe.
	_drone.frame_changed.connect(_rebuild)
	# Deferred: children ready before parents, so the drone has not resolved its
	# own `config` yet at this point in the frame.
	_rebuild.call_deferred()


func _rebuild() -> void:
	for player: AudioStreamPlayer3D in _players:
		remove_child(player)
		player.queue_free()
	_players.clear()
	var config: FlightConfig = _drone.config
	if config == null:
		return
	var body: float = maxf(config.body_m, 0.01)
	# Size, as a 0..1 position on the ladder from the datum to the largest frame.
	var ladder: float = clampf(log(body / REFERENCE_BODY_M) / log(10.714), 0.0, 1.0)
	_size_db = SIZE_DB * ladder
	_tau = RESPONSE_TAU_MIN + RESPONSE_TAU_PER_BODY * body
	var hz: float = REFERENCE_HZ * pow(REFERENCE_ARM_M / maxf(config.arm_length, 0.001),
			PITCH_EXPONENT)
	# ONE EMITTER PER ACTUAL ROTOR, AT ITS ACTUAL MOUNT (E.q1). The mounts are read
	# from the motor model rather than rebuilt from `arm_length` here, so the
	# emitters cannot drift from the physics — which they would have the first
	# time a layout was not a quad-X, since the four lines this replaced assumed
	# the corners.
	var motors: MotorModel = _drone.get_node_or_null("MotorModel") as MotorModel
	if motors == null:
		return
	var count: int = motors.rotor_count
	# Either fast enough to be texture, or slow enough to be inaudible — never
	# the 2–8 Hz band in between. See BEAT_TARGET_HZ.
	#
	# THE WIDEST PAIR IS (count - 1) STEPS APART, not always three: with six
	# rotors the extremes are 5u rather than 3u, so a guard hard-coded to 3.0
	# would let the widest beat run past MAX_SPREAD and put a slow wobble back in
	# the band this rule exists to keep clear.
	var spread_steps: float = maxf(float(count - 1), 1.0)
	var spacing: float = BEAT_TARGET_HZ / hz
	if spacing * spread_steps > MAX_SPREAD:
		spacing = BEAT_FLOOR_SPACING
	_load.resize(count)
	var lift: float = body * FlightController.MOTOR_LIFT_RATIO
	var mounts: Array[Vector3] = []
	for i: int in count:
		var mount: Vector3 = motors.motor_position(i, config)
		mounts.append(Vector3(mount.x, lift, mount.z))
	_detune.resize(count)
	for i: int in count:
		var player := AudioStreamPlayer3D.new()
		# Its OWN loop, not a shared one: same spectrum, scrambled partial phases.
		# That is where the width comes from now that the detune is no longer
		# allowed to supply it.
		player.stream = SoundBank.make_motor_loop(hz, ladder, 1.0 - ladder * 0.7, i)
		player.position = mounts[i]
		player.unit_size = body * UNIT_SIZE_PER_BODY
		_detune[i] = detune_step(i, count) * spacing
		player.volume_db = -60.0
		_players.append(player)
		add_child(player)
		player.play()
		_load[i] = 0.0
	var beats: PackedStringArray = []
	for step: int in range(1, count):
		beats.append("%.1f" % (spacing * float(step) * hz))
	print("[audio] %s %d rotors at %.0f Hz, unit_size %.2f m, response %.0f ms, beats %s Hz"
			% [config.frame_id, count, hz, player_unit_size(), _tau * 1000.0,
			"/".join(beats)])


func player_unit_size() -> float:
	return 0.0 if _players.is_empty() else _players[0].unit_size


func _process(delta: float) -> void:
	if _players.is_empty():
		return
	var config: FlightConfig = _drone.config
	var gain_db: float = AudioConfig.gain_to_db(audio_config.motor_volume)
	var blend: float = 1.0 - exp(-delta / _tau)
	for i: int in _players.size():
		# Thrust in g: stick fraction times the frame's thrust-to-weight. Hover is
		# 1.0 on a 0.65 kg quad and on a 500 kg aircraft alike, which is the whole
		# correction — the old code compared stick positions instead.
		var target: float = absf(_drone.motor_output(i)) * config.thrust_to_weight_ratio
		_load[i] = lerpf(_load[i], target, blend)
		var player: AudioStreamPlayer3D = _players[i]
		if not _drone.armed and _load[i] < 0.02:
			player.volume_db = -60.0
			continue
		var load: float = maxf(_load[i], 0.02)
		player.volume_db = HOVER_DB + _size_db + gain_db \
				+ LOAD_DB_PER_DECADE * log(load) / log(10.0)
		# PITCH FOLLOWS RPM, NOT THRUST, and separating the two is the point.
		# A rotor's tone is its blade-pass frequency, which is how fast it SPINS;
		# its loudness is how much air it MOVES. `motor_output` is the spin
		# command as a fraction of maximum, so it sweeps 0..1 on every airframe
		# and the tone band is the same width whatever the thrust-to-weight is.
		#
		# Driving pitch off `load` instead — as this did until 2026-08-13 — makes
		# the band collapse on exactly the frames that need it most: saturating at
		# 2 g is 44% of the Kestrel's stick and **17% of the Roc's**, so the big
		# frames climbed for a sixth of their travel and then sat flat. That is
		# the same mistake as the fixed 35 m/s wind and the Kestrel-ranged
		# sliders, made a third time inside the very function that fixed the
		# volume version of it.
		var rpm: float = clampf(absf(_drone.motor_output(i)) / RPM_SWEEP_TOP, 0.0, 1.0)
		player.pitch_scale = (1.0 + _detune[i]) \
				* (PITCH_AT_IDLE + PITCH_SWEEP * rpm)
