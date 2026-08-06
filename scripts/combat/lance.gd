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
## **The seam is `_acquire()`.** When the ranking layer lands, that one function
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

enum Phase { SEEK, ALIGN, RUN, RESET }

@export var enemy_config: EnemyConfig
## Per-instance seed, set before the node enters the tree. Rep index = seed, so a
## bench rep is the same fight every run (P4.8).
@export var ai_seed: int = -1

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _health: Health = $Health
@onready var _charge: MeshInstance3D = $Visual/Charge

var _rng := RandomNumberGenerator.new()
var _phase: int = Phase.SEEK
var _phase_time: float = 0.0
var _seek_time: float = 0.0
var _player: Node3D
## The point in SPACE this run is committed to. Locked when ALIGN ends and never
## updated afterwards — that is what "committed" means mechanically.
var _locked: Vector3 = Vector3.INF
var _setup_point: Vector3 = Vector3.INF
var _charge_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"enemies")
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


func _physics_process(delta: float) -> void:
	_phase_time += delta
	_player = _find_player()
	if _player == null:
		# Nothing to aim at: hold station rather than flying off the map, which is
		# falx bug four (v1.81) and it cost a whole session to find from the
		# cockpit. Every second before the pilot ARMS is a second with no player.
		velocity = velocity.move_toward(Vector3.ZERO, enemy_config.accel * delta)
		move_and_slide()
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


## Committed. Full thrust at a fixed point; no re-aiming, no turning back.
func _run(delta: float) -> void:
	_fly_toward(_locked, delta, enemy_config.speed)
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
	queue_free()


func _enter(phase: int) -> void:
	_phase = phase
	_phase_time = 0.0
	if phase != Phase.ALIGN:
		_set_charge(0.0)


func _fly_toward(point: Vector3, delta: float, speed: float) -> void:
	var offset: Vector3 = point - global_position
	velocity = velocity.move_toward(offset.normalized() * speed,
			enemy_config.accel * delta)
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
	Effects.explosion(get_tree().root, global_position, 1.2)
	destroyed.emit(enemy_config.points)
	detonated.emit()
	queue_free()
