class_name Lance
extends CharacterBody3D

## Lance — the committed suicider (GAMEPLAY-DESIGN Iteration 14 / A5, A.q5).
##
## The roster's seventh type and its third flight idiom. The raider orbits, the
## falx flies boom-and-zoom passes and goes home, the aegis flies a route it does
## not deviate from. The Lance does one thing and spends itself doing it:
##
##   SEEK    close to its setup distance, watching, harmless
##   ALIGN   stop, point, and CHARGE — the telegraph, and the whole design
##   RUN     commit to a straight line at full speed; it cannot re-decide
##   RESET   if it missed, swing wide and set up again
##
## **THE TELEGRAPH IS THE TYPE** (P4.4's readability rule). A suicider that
## simply flew at you would be a reflex test; one that visibly and audibly
## commits, from a known bearing, a beat before it moves, is a DECISION test —
## you get told what is about to happen and have to choose what to do about it.
## That is why ALIGN holds still and lights up instead of accelerating.
##
## **IT IS AIMED AT WHERE YOU ARE, NOT AT YOU** (P4.2's web role). The run locks a
## point in space at commit time and flies to it, so being somewhere else is the
## answer and lateral speed is the counter. Its poor turn rate is what makes that
## honest: `accel` is what `move_toward` spends to change direction, so a low
## accel against a high `speed` is a body that physically cannot follow you —
## emergent, not scripted, exactly as the falx's wide arc is.
##
## Counter-web (P4.3): area weapons `++` (a burst across the committed line),
## chip gun `0` (one honest window while it aligns, then it is too fast), terrain
## `++` (a committed run cannot follow you round a corner). Frame pressure
## (P4.4): light `++` (out-accelerate the lock), heavy `--` (cannot refuse it).
##
## ---------------------------------------------------------------------------
## IT TARGETS THE PLAYER, UNCONDITIONALLY, AND THAT IS A KNOWN SIMPLIFICATION
## ---------------------------------------------------------------------------
##
## A.q6 asked what a Lance is actually aimed at, and the user ANSWERED it
## (v2.20): *"it should choose the target based on the biggest threat that it can
## see... if I attack a node alone, then I AM the priority. however, in future
## nodes where we have the chance to defend an allied node and it is dispached to
## destroy a major allied asset... its reasonable that it would prioritize the
## major asset and ignore me/evade me."*
##
## That is a RANKING, not a flag, and it is deliberately NOT built here. Two
## things have to exist first and neither does: a shared target-ranking layer
## (every type in the game currently calls `get_first_node_in_group("player")`
## and hard-codes the answer), and allied assets that are not the player, so that
## there is a second thing worth ranking at all.
##
## So this file hard-codes the player like its five siblings do — **and the user
## chose that explicitly** (2026-08-06): *"lets approach it for now that the lance
## will always pick me as his only target... this one should be awesome but should
## not hold us back that much."*
##
## **The seam is `_find_player()`.** When the ranking layer lands, that one function
## becomes a call into it and nothing else in this file changes. Written down
## here rather than only in the design doc, because the next person to read this
## file is the one who needs to know it is a placeholder.

signal destroyed(points: float)
## It spent itself. Fires whether it hit anything or not, because the UNIT is
## over either way — the same bookkeeping `Aegis.detonated` carries, so a wave or
## a sortie holding this body can clear (P4.q5).
signal detonated

## Encounter-design constants (not flight/input physics). Everything a designer
## would TUNE lives in EnemyConfig; these are shape.
##
## How near the locked point counts as arrival. Generous, because the blast is
## what does the work and a suicider that has to touch you would be a suicider
## that never connects.
const ARRIVE_RADIUS: float = 2.6
## Where it sets up from, as a multiple of `preferred_range`. It backs off to
## here before aligning, so the run always has room to reach full speed — a
## suicider that commits from 5 m away has no telegraph at all.
const SETUP_BAND: float = 1.15
## THE TELEGRAPH, in seconds. The single most important number in the type: this
## is how long the player has between "it has chosen" and "it is moving". Long
## enough to react and choose, short enough to be a threat.
const ALIGN_SECONDS: float = 1.15
## How long a committed run may last before it gives up and resets. A run that
## missed must not turn into a chase, or the commitment is a lie.
const RUN_SECONDS: float = 4.0
## Seconds spent swinging wide after a miss, rebuilding the setup geometry.
const RESET_SECONDS: float = 2.4
## Fallback: a body that never manages to acquire anything still has to resolve
## rather than loitering forever in a sortie nobody can clear.
const SEEK_TIMEOUT: float = 45.0
## HOW FAR OUT THE WARNING OPENS, as a multiple of the fuse radius (A.q8).
##
## The fuse is the one number the cue is built from, and the important half of
## that is where it SATURATES: full intensity means "you are inside the envelope
## the warhead actually covers", so the sound can never promise a danger the fuse
## does not deliver. This multiple only decides how much lead-in you get.
##
## 4x an 11 m fuse opens the warning at 44 m — a shade outside the 34.5 m setup
## band the type commits from, so the telegraph starts the alarm quietly (~0.3)
## and the run is what swells it. Opening it exactly at the setup band would mean
## the lock arrived in silence, which is the opposite of what was asked for.
const WARN_RANGE_FUSES: float = 4.0

enum Phase { SEEK, ALIGN, RUN, RESET }

@export var enemy_config: EnemyConfig
## Per-instance seed, set before the node enters the tree. Rep index = seed, so a
## bench rep is the same fight every run (P4.8).
@export var ai_seed: int = -1
## Dev-room affordance (per instance, off everywhere else), the same shape the
## turret's `respawns` and the aegis's `loop_route` already have. Both spawners
## force this to false on anything they place — `WaveDirector` and `SortieRunner`
## each do `set(&"respawns", false)` — so a wave or a sortie can never be made
## unclearable by it.
##
## IT EXISTS BECAUSE THE SPECIMEN WAS UNWATCHABLE. Measured in the real dev room:
## the Lance charges from 78 m and spends itself on the spawn pad at **7.35 s**,
## which is before a pilot has finished arming. The user tried several times and
## never saw it. A suicider is a ONE-SHOT by design, so the only way to look at
## one twice is to let the specimen come back.
@export var respawns: bool = false

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _health: Health = $Health
@onready var _charge: MeshInstance3D = $Visual/Charge
@onready var _warning: AudioStreamPlayer3D = $Warning

var _rng := RandomNumberGenerator.new()
var _phase: int = Phase.SEEK
var _phase_time: float = 0.0
var _seek_time: float = 0.0
var _player: Node3D
## The point in SPACE this run is committed to. Locked when ALIGN ends and never
## updated afterwards — that is what "committed" means mechanically.
var _locked: Vector3 = Vector3.INF
var _setup_point: Vector3 = Vector3.INF
## Nearest the player has been during this run. INF until the fuse arms.
var _closest_approach: float = INF
var _charge_material: StandardMaterial3D
## Where the specimen came back to, captured before it ever moves.
var _home: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(&"enemies")
	_home = global_position
	if ai_seed >= 0:
		_rng.seed = ai_seed
	else:
		_rng.randomize()
	_health.max_health = enemy_config.hull
	_health.configure_defenses(enemy_config)
	_health.revive()
	_health.died.connect(_on_died)
	_charge_material = _charge.get_surface_override_material(0) as StandardMaterial3D
	_set_charge(0.0)
	_start_warning()


func take_hit(damage: float) -> void:
	_health.take(damage)


## Is it in the committed, visible, harmless part of its cycle? Public because
## the telegraph is a DESIGNED STATE rather than an internal one — a check should
## assert it directly, and a HUD threat indicator will want the same answer.
##
## `lance_check` first tried to infer this from "is it nearly stationary", and
## that measured the tail of the phase rather than the phase: the body spends
## most of ALIGN decelerating, so a 1.15 s telegraph read as 0.23 s. Inferring a
## state from its side effects is how you end up measuring the side effect.
func telegraphing() -> bool:
	return _phase == Phase.ALIGN


## HOW CLOSE THIS THING IS TO KILLING YOU: 0 clear, 1 inside the fuse (A.q8).
##
## Public for exactly the reasons `telegraphing()` is. It is a design decision
## rather than an implementation detail, the audio warning is only its first
## consumer (a HUD threat ring wants the same answer), and — the practical one —
## **a headless check cannot hear a sound but it can assert the scalar that
## drives one**, which is the difference between guarding this feature and
## guarding a comment about it.
##
## Zero in SEEK and RESET, because the type is harmless in both. A warning that
## is always on is not a warning.
func warning_level() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	if _phase != Phase.ALIGN and _phase != Phase.RUN:
		return 0.0
	var full_at: float = _warn_full_radius()
	var range_m: float = global_position.distance_to(_player.global_position)
	return clampf(inverse_lerp(full_at * WARN_RANGE_FUSES, full_at, range_m),
			0.0, 1.0)


## The distance at which the warning calls maximum danger: the fuse when there is
## one, the blast when there is not. `blast_fuse_radius` defaults to 0 across the
## roster, and a contact-only Lance is still lethal — a cue that switched off with
## the fuse would go silent on the one build where you have to be touched to be
## hurt.
func _warn_full_radius() -> float:
	if enemy_config.blast_fuse_radius > 0.0:
		return enemy_config.blast_fuse_radius
	return maxf(enemy_config.bomb_radius, 1.0)


func _physics_process(delta: float) -> void:
	_phase_time += delta
	_player = _find_player()
	if _player == null:
		# Nothing to aim at: hold station rather than flying off the map, which is
		# falx bug four (v1.81) and it cost a whole session to find from the
		# cockpit. Every second before the pilot ARMS is a second with no player.
		velocity = velocity.move_toward(Vector3.ZERO, enemy_config.accel * delta)
		move_and_slide()
		_update_warning()
		return
	match _phase:
		Phase.SEEK:
			_seek(delta)
		Phase.ALIGN:
			_align(delta)
		Phase.RUN:
			_run(delta)
		Phase.RESET:
			_reset(delta)
	_face_travel(delta)
	_update_warning()


## Close to the setup band and wait there. Harmless in this phase, which is what
## makes the ALIGN flare mean something when it comes.
func _seek(delta: float) -> void:
	_seek_time += delta
	if _seek_time >= SEEK_TIMEOUT:
		# Never acquired anything. Resolve rather than haunt the level.
		_spend(false)
		return
	var range_m: float = global_position.distance_to(_player.global_position)
	if range_m > enemy_config.sight_range:
		_fly_toward(_player.global_position, delta, enemy_config.speed * 0.5)
		return
	var setup: float = enemy_config.preferred_range * SETUP_BAND
	if absf(range_m - setup) <= enemy_config.preferred_range * 0.25:
		_enter(Phase.ALIGN)
		return
	# Hold the band: close if outside it, back off if inside it.
	var away: Vector3 = (global_position - _player.global_position).normalized()
	_fly_toward(_player.global_position + away * setup, delta,
			enemy_config.speed * 0.5)


## THE TELEGRAPH. It stops, turns to face you, and charges visibly and audibly.
## Nothing about this phase is a threat; the whole point is that you are told.
func _align(delta: float) -> void:
	if _phase_time <= delta:
		# AT THE START of the wind-up, not at the end. The sound IS the warning,
		# so playing it on commit would announce a decision already taken.
		SoundBank.play_at(&"charge", global_position, -3.0, 0.03)
	# BRAKES HARD, and this multiplier is the difference between a telegraph and
	# a coast. At the type's own `accel` of 9 it would still be doing 15 m/s most
	# of the way through the phase, which does not read as "it has stopped and
	# chosen" from the cockpit — it reads as it still flying. Braking is also the
	# one thing this airframe is allowed to be good at: nothing about the design
	# says a suicider decelerates badly, only that it cannot TURN.
	velocity = velocity.move_toward(Vector3.ZERO, enemy_config.accel * 6.0 * delta)
	move_and_slide()
	_set_charge(clampf(_phase_time / ALIGN_SECONDS, 0.0, 1.0))
	if _phase_time >= ALIGN_SECONDS:
		# LOCKED HERE, and never again. The run is aimed at where the player was
		# at the moment of commitment, which is what makes "be somewhere else"
		# the counter rather than "be faster".
		_locked = _player.global_position
		SoundBank.play_at(&"lock", global_position, -4.0, 0.05)
		_enter(Phase.RUN)


## Committed. Full thrust at a fixed point; no re-aiming, no turning back —
## except for the fuse, which is not re-aiming: it changes WHEN the warhead goes
## off, never where the body is going.
func _run(delta: float) -> void:
	_steer_the_run(delta)
	_fly_toward(_locked, delta, enemy_config.speed)
	if _proximity_triggered():
		_spend(true)
		return
	if global_position.distance_to(_locked) <= ARRIVE_RADIUS:
		_spend(true)
		return
	# Contact anywhere along the line still detonates it — flying INTO the player
	# is the same event as reaching the point they were standing on.
	if global_position.distance_to(_player.global_position) <= ARRIVE_RADIUS:
		_spend(true)
		return
	if _phase_time >= RUN_SECONDS:
		_enter(Phase.RESET)


## A BOUNDED COURSE CORRECTION during the run (A.q9, `run_steer_deg_s`).
##
## It rotates the AIM POINT about the body at a capped angular rate, rather than
## moving `_locked` toward the player or blending the two. Everything downstream —
## the arrival test, `_fly_toward`, the fuse — keeps reading `_locked` and needs no
## knowledge that this exists, and the run is still "fly at a point" rather than
## "chase a body".
##
## THE RATE CAP IS THE DESIGN, and it is what keeps P4.2's counterplay intact.
## Turn budget is spent per second, so the correction it can buy over a run is
## bounded by how long the run lasts: a small dodge is inside that budget and gets
## punished, a real break is outside it and still works. A blend toward the player
## would have defeated both equally, which is a homing missile with a slow fuse.
##
## Rotation preserves the offset's LENGTH, so steering never brings the aim point
## nearer or pushes it further — it only changes the bearing. Otherwise the knob
## would quietly be an arrival-time knob as well.
##
## At 0 this function does nothing at all, which is the retraction path.
func _steer_the_run(delta: float) -> void:
	if enemy_config.run_steer_deg_s <= 0.0 or _player == null:
		return
	var offset: Vector3 = _locked - global_position
	var toward: Vector3 = _player.global_position - global_position
	if offset.length_squared() < 0.01 or toward.length_squared() < 0.01:
		return
	var from_dir: Vector3 = offset.normalized()
	var to_dir: Vector3 = toward.normalized()
	var error: float = from_dir.angle_to(to_dir)
	if error <= 0.0001:
		return
	var budget: float = deg_to_rad(enemy_config.run_steer_deg_s) * delta
	var axis: Vector3 = from_dir.cross(to_dir)
	if axis.length_squared() < 1.0e-12:
		# Exactly opposed or exactly aligned: no meaningful rotation axis, and
		# picking one arbitrarily would make a 180-degree error swing a direction
		# that depends on float noise.
		return
	var turned: Vector3 = from_dir.rotated(axis.normalized(),
			minf(budget, error))
	_locked = global_position + turned * offset.length()


## THE PROXIMITY FUSE: inside the fuse radius and no longer closing, go off.
##
## Closest-approach rather than a plain radius test, and the difference is the
## whole mechanic. A plain radius detonates the instant you enter it, which fires
## EARLY on a head-on run and wastes the warhead at the edge of its own blast.
## Waiting for the range to start opening again puts the explosion at the nearest
## point the two bodies ever get — which is what a real proximity fuse does, and
## what makes a graze feel like a graze rather than a miss.
##
## Armed only during RUN. The type is harmless until it commits (that is what the
## telegraph is promising), so flying into one while it is still aligning has to
## stay free.
func _proximity_triggered() -> bool:
	if enemy_config.blast_fuse_radius <= 0.0:
		return false
	var range_m: float = global_position.distance_to(_player.global_position)
	if range_m > enemy_config.blast_fuse_radius:
		# Outside the fuse: forget any earlier approach, so a run that passes
		# wide and comes back later is judged on its own pass.
		_closest_approach = INF
		return false
	if range_m < _closest_approach:
		_closest_approach = range_m
		return false
	# Inside the fuse and the range has started opening again.
	return true


## It missed. Swing wide and rebuild the geometry rather than chasing, or the
## commitment the whole type is built on would be a lie.
func _reset(delta: float) -> void:
	if _setup_point == Vector3.INF:
		var away: Vector3 = (global_position - _player.global_position)
		away.y = 0.0
		if away.length() < 1.0:
			away = -global_basis.z
		_setup_point = _player.global_position \
				+ away.normalized() * (enemy_config.preferred_range * SETUP_BAND) \
				+ Vector3.UP * 6.0
	_fly_toward(_setup_point, delta, enemy_config.speed * 0.6)
	if _phase_time >= RESET_SECONDS \
			or global_position.distance_to(_setup_point) <= ARRIVE_RADIUS:
		_setup_point = Vector3.INF
		_seek_time = 0.0
		_enter(Phase.SEEK)


## Spend itself. `hit` is only used for the sound's weight — the blast is applied
## the same way either way, because a near miss that still catches you is the
## point of having a radius at all.
func _spend(hit: bool) -> void:
	Bomb.blast(get_tree(), global_position, enemy_config, team)
	if not hit:
		SoundBank.play_at(&"explosion", global_position, -10.0, 0.4)
	detonated.emit()
	if respawns:
		_respawn()
		return
	queue_free()


## Back to where it started, ready to do it again. Dev-room only — see `respawns`.
func _respawn() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	_health.revive()
	_locked = Vector3.INF
	_setup_point = Vector3.INF
	_seek_time = 0.0
	_enter(Phase.SEEK)


func _enter(phase: int) -> void:
	_phase = phase
	_phase_time = 0.0
	if phase != Phase.ALIGN:
		_set_charge(0.0)
	# The stuck detector measures TRAVEL, and ALIGN deliberately stops, so a
	# phase change re-arms it rather than letting a legitimate hold read as a
	# wedge. ALIGN never calls `_fly_toward` anyway; this is the belt.
	_stuck_anchor = Vector3.INF
	_stuck_time = 0.0
	# A fresh run gets a fresh fuse, or a previous pass's closest approach
	# would detonate the next one the moment it armed.
	_closest_approach = INF


## Same numbers and same reason as `Aegis`: see the long comment on its
## `_fly_toward`. Both types fly COMMITTED straight lines, which is exactly the
## shape that wedges head-on against geometry and never recovers, because
## `move_and_slide`'s slide vector is zero on a square hit. The orbiting types do
## not need this — their goal keeps moving, so the obstacle stops being in the
## way on its own.
const STUCK_SECONDS: float = 0.8
const STUCK_CLIMB: float = 0.9
const STUCK_TRAVEL: float = 1.5

var _stuck_time: float = 0.0
var _stuck_anchor: Vector3 = Vector3.INF


func _fly_toward(point: Vector3, delta: float, speed: float) -> void:
	if _stuck_anchor == Vector3.INF 			or global_position.distance_to(_stuck_anchor) > STUCK_TRAVEL:
		_stuck_anchor = global_position
		_stuck_time = 0.0
	else:
		_stuck_time += delta
	var offset: Vector3 = point - global_position
	var desired: Vector3 = offset.normalized() * speed
	if _stuck_time > STUCK_SECONDS:
		desired = (desired + Vector3.UP * speed * STUCK_CLIMB).limit_length(speed)
	velocity = velocity.move_toward(desired, enemy_config.accel * delta)
	move_and_slide()


## Faced by HEADING, never by body basis. A freshly spawned enemy has identity
## rotation and zero velocity, and reading the body instead of the velocity is
## the bug that broke the falx twice (standing rule 3).
func _face_travel(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if _phase == Phase.ALIGN and _player != null:
		# While aligning it points at the LOCK, not at where it is drifting —
		# the bearing is half of what the telegraph tells you.
		flat = Vector3(_player.global_position.x - global_position.x, 0.0,
				_player.global_position.z - global_position.z)
	if flat.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z),
				1.0 - exp(-deg_to_rad(enemy_config.turn_speed_deg) * delta))


## The charge glow, 0 cold to 1 committed. The visible half of the telegraph.
func _set_charge(amount: float) -> void:
	_charge.visible = amount > 0.01
	if _charge_material != null:
		_charge_material.emission_energy_multiplier = 0.5 + amount * 7.0
	if amount > 0.01:
		_charge.scale = Vector3.ONE * (0.7 + amount * 0.9)


## THE CONTINUOUS WARNING (A.q8), and it is the audible half of what `_set_charge`
## does with light. The user flew the one-shot and named the gap precisely: *"i
## feel that the lock should have more dramatic sound, a continous warning sound
## that increase the more the danger is close."*
##
## `charge` stays as it is and this plays over it — the two say different things.
## A one-shot can only ever announce an EVENT ("it has chosen"), and the run that
## follows is where the player actually needs telling. This is a live readout.
##
## Volume and pulse rate are both driven by `warning_level()`, so what you hear
## and what hurts you are the same number. That is the screamer's rule
## (`_update_telegraph`: *"a cue that disagrees with the mechanic by even a little
## teaches the player the wrong edge"*) applied to a second mechanic, and here the
## wrong edge would be the expensive one — believing you are clear.
##
## STOPPED rather than faded to inaudible when the level is 0, because a Lance
## spends most of its life harmless and several can be on the field: a silent
## voice per body is a leak with a volume slider on it.
func _update_warning() -> void:
	if _warning == null or _warning.stream == null:
		return
	var level: float = warning_level()
	if level <= 0.001:
		if _warning.playing:
			_warning.stop()
		return
	if not _warning.playing:
		_warning.play()
	# SQUARE-ROOTED for loudness, LINEAR for the scalar, and the split is
	# deliberate. `warning_level()` is honest distance and stays that way — a HUD
	# ring and a check both want the real number. But the level at the moment of
	# commitment is only 0.14 (measured: it locks from ~39 m against a 44 m
	# envelope), and a linear map puts that at -26 dB, which is under the motor
	# bed and therefore not a warning at all. The curve buys audibility at the
	# lock without moving where the alarm PEAKS, which is the half that has to
	# keep meaning "inside the fuse".
	_warning.volume_db = lerpf(-28.0, -3.0, sqrt(level))
	# One dial, two dimensions of alarm: pitch_scale on a gated loop speeds the
	# BEAT up as well as raising the tone, so 4 Hz at the lock becomes ~8 Hz
	# inside the fuse without a second stream or a second curve.
	_warning.pitch_scale = 0.85 + 1.05 * level


func _start_warning() -> void:
	# Headless: active playbacks leak at quit() under the Dummy audio driver, and
	# no bench hears them (motor_audio.gd's rule, same reason). `warning_level()`
	# keeps working, which is what the check reads.
	if _warning == null or DisplayServer.get_name() == "headless":
		return
	_warning.stream = SoundBank.make_warning_loop()
	_warning.volume_db = -60.0


func _find_player() -> Node3D:
	# THE SEAM. One call, replaced wholesale when the target-ranking layer lands
	# (A.q6) — see the header. Re-read every tick rather than cached because the
	# player can die and respawn under it.
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not is_instance_valid(player) or not (player is Node3D):
		return null
	if not (player as Node3D).visible:
		return null
	return player as Node3D


func _on_died() -> void:
	# Killed BEFORE it spent itself: no blast. That is the reward for taking the
	# window the telegraph opened, and it is the whole reason the window exists.
	#
	# `detonated` is deliberately NOT emitted here, matching the aegis exactly.
	# That signal means "the unit ended WITHOUT dying", and `destroyed` already
	# closes the books on a kill. Emitting both is harmless to the counts — every
	# consumer guards with `units.has(unit)` — but `WaveDirector` announces
	# *"bomber reached its target"* on `detonated`, so a Lance the player shot
	# down would have congratulated the enemy on it.
	Effects.explosion(get_tree().root, global_position, 1.2)
	destroyed.emit(enemy_config.points)
	if respawns:
		# The dev-room specimen comes back from a KILL too, not only from a
		# spend. Otherwise the first good shot ends the demonstration, which is
		# the opposite of what a specimen is for.
		_respawn()
		return
	queue_free()
