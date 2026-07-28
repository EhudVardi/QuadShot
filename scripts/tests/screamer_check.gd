extends SceneTree

## Screamer behaviour check (P4.2, roster type six) — the falx_check discipline
## applied to a type that is even harder to read from a results table.
##
## The falx taught this lesson four times: **the harness can only ever say "this
## cell reads 0%", which is equally consistent with a tough enemy, a broken enemy,
## and an enemy that has flown to the next postcode.** The screamer is worse. It
## deals no damage, so `dmg-taken 0.0` is its CORRECT reading; it is invisible to
## Layer 1 and to Layer 3a by design; and the one thing it does — degrade your
## FCS — leaves no trace in any duel column at all. A screamer whose jam field
## silently failed to emit would produce a harness board that looks completely
## normal.
##
## So the three things that can quietly break get an assertion each:
##
##   1. DOES IT STAY? (the falx's bug one.) With no player it must wander near
##      home, not leave the level.
##   2. DOES IT JAM, AND DOES THE JAM FADE? At its own standoff the player's gun
##      director must be degraded but alive; pressed to point blank it must be
##      gone — director silent, missile lock refused, flak fuse collapsed. Both
##      ends, because a jam stuck ON and a jam stuck OFF are both invisible
##      downstream, and a gradient asserted at one end is not a gradient.
##   3. DOES IT KEEP ITS DISTANCE, WITHOUT ABSCONDING? Its counterplay is being
##      closed on (P4.2: "tissue once reached"), so it must back off from a player
##      inside its standoff — and it must NOT keep running, or the type has no
##      counterplay and every cell against it reads 0% forever.
##
## Run: <godot> --headless -s scripts/tests/screamer_check.gd --path .

const SCREAMER_SCENE: String = "res://scenes/combat/screamer.tscn"
const CONFIG: String = "res://resources/default_enemy_screamer.tres"

## Seconds of wander before the leash is measured.
const PATROL_SECONDS: float = 8.0
## How far from home an unengaged screamer may drift: its wander radius plus room
## to reach the far side of it. Generous on purpose — this guards ABSCONDING.
const LEASH_FACTOR: float = 2.2
## Seconds of standoff behaviour before the distance assertions are made. Long
## enough for a body at 15 m/s to have travelled 150 m if it were running.
const STANDOFF_SECONDS: float = 10.0
## Where the player is parked for phases 2 and 3.
const ALTITUDE: float = 14.0
## Phase 3 spawns the screamer WELL inside its standoff, so "does it back off" is
## a real question rather than one it starts out already answering.
const CROWD_RANGE: float = 8.0
## How far past its own `preferred_range` a screamer may end up before it counts
## as running rather than repositioning. Two things are being separated here and
## the margin is what separates them: a standoff keeper eases toward a slot, a
## runner keeps accelerating.
const STANDOFF_TOLERANCE_M: float = 25.0

enum { PATROL, JAM, CROWD, DONE }

var _pps: float
var _phase: int = PATROL
var _ticks: int = 0
var _arena: Node3D
var _screamer: Node3D
var _drone: FlightController
var _weapon: Weapon
var _missile: MissileSystem
var _flak: FlakPod
var _pool: ProjectilePool
var _config: EnemyConfig
var _home: Vector3
## Phase 3: the closest and the furthest the screamer got from the parked player.
var _closest: float = INF
var _furthest: float = 0.0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_config = load(CONFIG) as EnemyConfig
	print("[screamer] three phases: does it stay, does its jam fade, does it hold its distance")
	if _config.jam_range <= _config.jam_full_range:
		# Checked before anything flies, because every later assertion assumes an
		# ordering that a tuning edit could invert in one keystroke, and a
		# collapsed gradient would otherwise read as "the jam is binary" rather
		# than as a broken config.
		_failures.append("config broken: jam_range %.0f must exceed jam_full_range %.0f, or there is no gradient to fade across"
				% [_config.jam_range, _config.jam_full_range])
	_build_patrol()
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_ticks += 1
	match _phase:
		PATROL:
			if _ticks >= int(PATROL_SECONDS * _pps):
				_score_patrol()
				_teardown()
				_build_jam()
				_phase = JAM
				_ticks = 0
		JAM:
			# One settled tick is enough: the jam is a pure function of position,
			# and the drone's systems are read after a frame of physics so the
			# weapon nodes have had their `_physics_process`.
			if _ticks >= 4:
				_score_jam()
				_teardown()
				_build_crowd()
				_phase = CROWD
				_ticks = 0
		CROWD:
			if is_instance_valid(_screamer) and is_instance_valid(_drone):
				var range_m: float = _screamer.global_position.distance_to(
						_drone.global_position)
				_closest = minf(_closest, range_m)
				_furthest = maxf(_furthest, range_m)
			if _ticks >= int(STANDOFF_SECONDS * _pps):
				_score_crowd()
				_report()


## PHASE 1: no player in the tree, so `_can_engage` is false every tick and the
## type is on its idle behaviour — the state the falx's first bug lived in.
func _build_patrol() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)
	_home = Vector3(0.0, 20.0, 0.0)
	_screamer = _spawn(_home)


func _score_patrol() -> void:
	if not is_instance_valid(_screamer):
		_failures.append("the screamer did not survive an empty arena")
		return
	var drift: float = _screamer.global_position.distance_to(_home)
	var leash: float = Screamer.WANDER_RADIUS * LEASH_FACTOR
	print("[screamer] patrol: %.0f m from home after %.0fs (leash %.0f m)"
			% [drift, PATROL_SECONDS, leash])
	if drift > leash:
		_failures.append("ABSCONDED: %.0f m from home after %.0fs with no target (leash %.0f m) — the idle behaviour is flying it out of the level"
				% [drift, PATROL_SECONDS, leash])


## PHASE 2: an armed player and a screamer placed at TWO stated ranges in turn,
## so the field is read where its two ends live.
##
## No pilot: the drone is parked and immortal, because what is being checked is
## what the JAM does to its systems, and a brain flying the aircraft would move
## the range this measurement is a function of.
func _build_jam() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)
	_drone = Frames.build(Frames.KESTREL)
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALTITUDE, 0.0)
	_drone.freeze = true
	_drone.arm()
	var health: Health = _drone.get_node("Health") as Health
	health.max_health = 1.0e9
	health.revive()
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod
	# The human's own play setting, as everywhere else that measures the director.
	_weapon.combat_config.fire_assist_miss_m = 1.2
	_screamer = _spawn(Vector3(0.0, ALTITUDE, -_config.preferred_range))


func _score_jam() -> void:
	var standoff: float = _jam_at(_config.preferred_range)
	var outside: float = _jam_at(_config.jam_range + 5.0)
	var point_blank: float = _jam_at(_config.jam_full_range * 0.5)
	print("[screamer] jam field: %.0f m -> %.2f (outside), %.0f m -> %.2f (its own standoff), %.0f m -> %.2f (pressed)"
			% [_config.jam_range + 5.0, outside, _config.preferred_range,
			standoff, _config.jam_full_range * 0.5, point_blank])
	if outside > 0.001:
		_failures.append("the jam reaches past jam_range (%.2f at %.0f m) — the field has no edge"
				% [outside, _config.jam_range + 5.0])
	if point_blank < 0.999:
		_failures.append("the jam is not total inside jam_full_range (%.2f) — nothing downstream can rely on the `jammed` state existing"
				% point_blank)
	# THE GRADIENT ITSELF. A jam that is 1.0 at the standoff would be the binary
	# bubble the user overruled; one that is 0.0 there would make engaging the type
	# free. Both ends are asserted because both are one edit away.
	if standoff <= 0.01 or standoff >= 0.99:
		_failures.append("the jam does not FADE: %.2f at the type's own standoff (%.0f m). It should be partial there — engaging costs some FCS, killing it costs all of it"
				% [standoff, _config.preferred_range])
	# And what the field actually DOES, read off the shipped systems rather than
	# off the number — the two could drift, and this is the seam they would drift
	# at. Placed at full jam for the assertions, since that is the state the
	# delivery bench and the design both name.
	_place(_config.jam_full_range * 0.5)
	var window: float = _weapon.director_window()
	var fuse: float = _flak.fuse_radius()
	print("[screamer] pressed to %.0f m: director window %.2f m (config %.2f), flak fuse %.2f m (config %.2f), lock progress %.2f"
			% [_config.jam_full_range * 0.5, window,
			_weapon.combat_config.fire_assist_miss_m, fuse,
			_weapon.combat_config.flak_fuse_radius, _missile.lock_progress])
	if _weapon.director_active():
		_failures.append("the gun director survives a full jam (window %.2f m) — the pilot would never reach for the manual trigger, which is the whole type"
				% window)
	if fuse > 0.001:
		_failures.append("the flak fuse survives a full jam (%.2f m) — P3.6 says a screamer degrades it to contact-only"
				% fuse)
	if _missile.is_locked():
		_failures.append("a missile lock completed inside a full jam — P4.3's `--` for missile-vs-screamer is this refusal, and without it the row is just a hull number")
	# The other end, and the reason this check is not two asserts on one number: a
	# jam stuck ON is as broken as one stuck OFF, and it would read as "the FCS is
	# gear that never works" rather than as a screamer.
	_place(_config.jam_range + 5.0)
	if not _weapon.director_active():
		_failures.append("the gun director is dead OUTSIDE the jam field (window %.2f m) — the jam is not switching off, so every fight in the game is a jammed fight"
				% _weapon.director_window())


## PHASE 3: the screamer spawned WELL inside its standoff against a parked player.
## It must back away — and then stop.
func _build_crowd() -> void:
	_build_jam()
	_drone.freeze = true
	_place(CROWD_RANGE)


func _score_crowd() -> void:
	var final_range: float = _screamer.global_position.distance_to(
			_drone.global_position)
	var ceiling: float = _config.preferred_range + STANDOFF_TOLERANCE_M
	print("[screamer] standoff: spawned at %.0f m, closest %.0f m, furthest %.0f m, settled at %.0f m (wants %.0f, ceiling %.0f)"
			% [CROWD_RANGE, _closest, _furthest, final_range,
			_config.preferred_range, ceiling])
	if final_range < CROWD_RANGE + 2.0:
		_failures.append("NEVER BACKED OFF: still %.0f m away after %.0fs from a %.0f m start — it is not holding a standoff, so its counterplay (close and kill it) has nothing to work against"
				% [final_range, STANDOFF_SECONDS, CROWD_RANGE])
	if final_range > ceiling:
		# The failure mode that would make every screamer cell read 0% while
		# looking like a hard enemy: a type that keeps running is unkillable, not
		# difficult, and the harness cannot tell those apart.
		_failures.append("RAN AWAY: %.0f m after %.0fs, past the %.0f m ceiling — an EW asset that simply leaves has no counterplay and every cell against it reads 0%% forever"
				% [final_range, STANDOFF_SECONDS, ceiling])


## The jam level a player at `range_m` would suffer, read through the same static
## the game reads — never by calling the screamer's own method, or this would
## check the type against itself and skip the group wiring entirely (a screamer
## missing from the `jammers` group is a silent no-op everywhere else).
func _jam_at(range_m: float) -> float:
	_place(range_m)
	return Jamming.level_at(_drone)


func _place(range_m: float) -> void:
	_screamer.global_position = Vector3(0.0, ALTITUDE, -range_m)


func _spawn(at: Vector3) -> Node3D:
	var screamer: Node3D = (load(SCREAMER_SCENE) as PackedScene).instantiate() \
			as Node3D
	# Seeded for determinism (P4.8), set before the node enters the tree.
	screamer.set(&"ai_seed", 0)
	screamer.position = at
	_arena.add_child(screamer)
	return screamer


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_screamer = null
	_drone = null
	_weapon = null
	_missile = null
	_flak = null
	_pool = null


func _report() -> void:
	_phase = DONE
	if _failures.is_empty():
		print("[screamer] PASS")
		quit(0)
		return
	for failure: String in _failures:
		print("[screamer] FAIL: %s" % failure)
	print("[screamer] FAIL")
	quit(1)
