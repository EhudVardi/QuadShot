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

## Seconds each lock phase runs. `missile_lock_time` is 0.9 s, so a clear lock
## has time to complete nearly three times over — which is what makes "it never
## completed" mean something rather than "we did not wait".
const LOCK_SECONDS: float = 2.5

## Seconds the PURSUIT phase runs — a real pilot chasing a real screamer.
## Comfortably longer than the duel harness's 10 s cap, so "it was never caught"
## cannot be "the clock ran out".
const PURSUE_SECONDS: float = 18.0

enum { PATROL, LOCK_CLEAR, JAM, CROWD, PURSUE, DONE }

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
## Phase 4: the closest and the furthest the screamer got from the parked player.
var _closest: float = INF
var _furthest: float = 0.0
## Peak missile lock progress reached in the current lock phase.
var _peak_lock: float = 0.0
## Phase 5: the pursuing pilot, and what the chase produced.
var _pilot: ReferencePilot
var _hits: int = 0
var _start_range: float = 0.0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_config = load(CONFIG) as EnemyConfig
	print("[screamer] five phases: does it stay, does a lock work at all, does its jam fade, does it hold its distance, CAN IT BE CAUGHT")
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
				_build_lock_phase(_config.jam_range + 3.0)
				_phase = LOCK_CLEAR
				_ticks = 0
		LOCK_CLEAR:
			_place(_config.jam_range + 3.0)
			_peak_lock = maxf(_peak_lock, _missile.lock_progress)
			if _ticks >= int(LOCK_SECONDS * _pps):
				_score_lock_clear()
				_teardown()
				_build_lock_phase(_config.jam_full_range * 0.5)
				_phase = JAM
				_ticks = 0
				_peak_lock = 0.0
		JAM:
			_place(_config.jam_full_range * 0.5)
			_peak_lock = maxf(_peak_lock, _missile.lock_progress)
			if _ticks >= int(LOCK_SECONDS * _pps):
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
				_teardown()
				_build_pursue()
				_phase = PURSUE
				_ticks = 0
				_closest = INF
		PURSUE:
			if _pilot != null:
				_pilot.update(1.0 / _pps)
			if is_instance_valid(_screamer) and is_instance_valid(_drone):
				_closest = minf(_closest, _screamer.global_position.distance_to(
						_drone.global_position))
			if _ticks >= int(PURSUE_SECONDS * _pps):
				_score_pursue()
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


## PHASES 2 AND 3: an armed, parked player with a screamer held at a stated range
## on the MISSILE'S OWN BORESIGHT, run long enough for a lock to complete.
##
## No pilot: what is being checked is what the JAM does to the drone's systems,
## and a brain flying the aircraft would move the range the whole measurement is
## a function of.
##
## ON THE BORESIGHT, not simply "in front". The seeker sits under the FPV camera
## and inherits its ~44 degree uptilt, so a target placed level with the drone
## sits far outside a 12 degree lock cone and NO LOCK IS EVER ATTEMPTED. An
## earlier draft of this file did exactly that, and its "no lock under jam"
## assertion passed while proving nothing — the vacuous-guard failure this
## project keeps catching in its own instruments. Placing along
## `-missile.global_basis.z` guarantees the cone is not the reason.
##
## And that is why phase 2 exists at all: it is the CONTROL. "The lock refused"
## only means something once "the lock completes when nothing is jamming it" has
## been shown on the same rig, a few seconds earlier.
func _build_lock_phase(range_m: float) -> void:
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
	_screamer = _spawn(Vector3.ZERO)
	_place(range_m)


## PHASE 2's verdict: the CONTROL. Outside the field entirely, a lock must
## complete — otherwise phase 3's refusal proves nothing about the jam.
func _score_lock_clear() -> void:
	var range_m: float = _config.jam_range + 3.0
	print("[screamer] control: at %.0f m (outside the %.0f m field) peak lock progress %.2f after %.1fs"
			% [range_m, _config.jam_range, _peak_lock, LOCK_SECONDS])
	if _peak_lock < 1.0:
		_failures.append("CONTROL FAILED: no lock completed in %.1fs at %.0f m with nothing jamming (peak %.2f) — the rig cannot lock at all, so the jam phase below would prove nothing"
				% [LOCK_SECONDS, range_m, _peak_lock])
	if Jamming.level_at(_drone) > 0.001:
		_failures.append("CONTROL FAILED: the control range %.0f m is still inside the jam field (%.2f)"
				% [range_m, Jamming.level_at(_drone)])


func _score_jam() -> void:
	print("[screamer] pressed: peak lock progress %.2f after %.1fs at %.0f m"
			% [_peak_lock, LOCK_SECONDS, _config.jam_full_range * 0.5])
	if _peak_lock > 0.001:
		_failures.append("A MISSILE LOCK BUILT INSIDE A FULL JAM (peak %.2f) — P4.3's `--` for missile-vs-screamer IS this refusal; without it the row is just a hull number"
				% _peak_lock)
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
	print("[screamer] pressed to %.0f m: director window %.2f m (config %.2f), flak fuse %.2f m (config %.2f)"
			% [_config.jam_full_range * 0.5, window,
			_weapon.combat_config.fire_assist_miss_m, fuse,
			_weapon.combat_config.flak_fuse_radius])
	if _weapon.director_active():
		_failures.append("the gun director survives a full jam (window %.2f m) — the pilot would never reach for the manual trigger, which is the whole type"
				% window)
	if fuse > 0.001:
		_failures.append("the flak fuse survives a full jam (%.2f m) — P3.6 says a screamer degrades it to contact-only"
				% fuse)
	# The other end, and the reason this check is not two asserts on one number: a
	# jam stuck ON is as broken as one stuck OFF, and it would read as "the FCS is
	# gear that never works" rather than as a screamer.
	_place(_config.jam_range + 5.0)
	if not _weapon.director_active():
		_failures.append("the gun director is dead OUTSIDE the jam field (window %.2f m) — the jam is not switching off, so every fight in the game is a jammed fight"
				% _weapon.director_window())


## PHASE 4: the screamer spawned WELL inside its standoff against a parked player.
## It must back away — and then stop.
func _build_crowd() -> void:
	_build_lock_phase(CROWD_RANGE)
	# Level with the player rather than up the boresight: this phase is about
	# horizontal standoff, and starting it 8 m up a 44-degree line would hand the
	# type most of its separation before it had done anything.
	_screamer.global_position = Vector3(0.0, ALTITUDE, -CROWD_RANGE)


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


## PHASE 5: CAN IT ACTUALLY BE CAUGHT? A real reference pilot flying a real
## Kestrel with a real blaster, chasing a real screamer for 18 s.
##
## THIS PHASE EXISTS BECAUSE PHASE 4 PASSED WHILE THE TYPE WAS UNWINNABLE. Phase 4
## asks "does it hold a standoff against a PARKED player", which it does — and that
## told us nothing about a player who is chasing it. The v7 duels then read
## `Blaster x Screamer` 0/6 with **69 rounds spent**: the pilot shooting hard and
## hitting nothing. A results table cannot distinguish "it outran me" from "I could
## not aim at it", so this phase separates them by measuring both — the closest the
## chase ever got, and whether anything landed.
##
## Diagnostic first, assertion second. It FAILS only on the unambiguous break (the
## screamer leaves the fight entirely); the interesting middle — caught but not
## hittable, or hittable but never caught — is PRINTED, because which of those the
## roster wants is a design call and not a test's business.
func _build_pursue() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)
	_drone = Frames.build(Frames.KESTREL)
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALTITUDE, 0.0)
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())
	# Immortal, because the screamer cannot shoot anyway and a crash mid-chase
	# would end the measurement early with no way to tell that from being outrun.
	var health: Health = _drone.get_node("Health") as Health
	health.max_health = 1.0e9
	health.revive()
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod
	_weapon.combat_config.fire_assist_miss_m = 1.2
	# The harness's own engagement distance, so this phase and the duel rows it is
	# diagnosing start from the same geometry.
	_screamer = _spawn(Vector3(0.0, ALTITUDE, -40.0))
	# Immortal too: the question is whether the chase CLOSES, and a screamer that
	# dies at second three stops answering it. Rounds landed are counted instead.
	var screamer_health: Health = _screamer.get_node("Health") as Health
	screamer_health.max_health = 1.0e9
	screamer_health.revive()
	screamer_health.struck.connect(func(_amount: float) -> void: _hits += 1)
	_pilot = ReferencePilot.new()
	_pilot.drone = _drone
	_pilot.weapon = _weapon
	_pilot.missile = _missile
	_pilot.flak = _flak
	_pilot.weapon_id = "blaster"
	_pilot.cruise_altitude = ALTITUDE
	_pilot.target = _screamer
	_start_range = 40.0
	_hits = 0


func _score_pursue() -> void:
	var final_range: float = _screamer.global_position.distance_to(
			_drone.global_position)
	var shots: int = _weapon.shots_fired
	print("[screamer] pursuit: started %.0f m, closest %.0f m, ended %.0f m; %d rounds fired, %d landed (jam here %.2f)"
			% [_start_range, _closest, final_range, shots, _hits,
			Jamming.level_at(_drone)])
	if shots == 0:
		_failures.append("the pursuing pilot fired NOTHING in %.0fs — the iron trigger is broken again (this is the v6 defect, and it is why this phase counts rounds)"
				% PURSUE_SECONDS)
	# The unambiguous break, and the only thing asserted here: an EW asset that
	# simply leaves is unkillable rather than difficult, and every cell against it
	# reads 0% forever while looking like a hard enemy.
	if _closest > _start_range:
		_failures.append("UNCATCHABLE: an 18s chase never got closer than %.0f m from a %.0f m start — it outruns a committed pursuit, so no gun answer to this type can exist"
				% [_closest, _start_range])
	# Everything else is a REPORT, not a verdict, because which way the roster wants
	# it is a design call. Both readings are named so the reader does not have to
	# infer which one they are looking at.
	if _hits == 0 and _closest < _start_range:
		print("[screamer]   ^ caught but not hit: the chase closed to %.0f m and %d rounds still landed nothing. Reads as an AIM problem (stern chase against a body-fixed gun), not a footrace."
				% [_closest, shots])
	elif _hits == 0:
		print("[screamer]   ^ neither caught nor hit: the chase never closed AND nothing landed. Reads as a FOOTRACE — compare `speed` %.0f against the pilot's closing rate."
				% _config.speed)


## The jam level a player at `range_m` would suffer, read through the same static
## the game reads — never by calling the screamer's own method, or this would
## check the type against itself and skip the group wiring entirely (a screamer
## missing from the `jammers` group is a silent no-op everywhere else).
func _jam_at(range_m: float) -> float:
	_place(range_m)
	return Jamming.level_at(_drone)


## Hold the screamer at `range_m` along the seeker's boresight (see
## _build_lock_phase). Distance is what the jam is a function of, so this places
## the field reads exactly where they claim to be AND keeps the lock cone out of
## the argument.
##
## RE-APPLIED EVERY TICK during the lock phases, for two reasons that both cost a
## debugging round to find. The screamer is ALIVE — it flies to its own standoff
## against a parked player, so a one-shot placement measures wherever it drifted
## to by the time anything is scored (58 m read back as 40 m and 0.37 jam). And
## the camera's uptilt is applied in `_process`, not `_ready`, so the boresight
## does not exist yet on the frame the arena is built: a one-shot placement aims
## down an UNTILTED axis, lands the target 44 degrees off the seeker, and the lock
## never even attempts to build.
func _place(range_m: float) -> void:
	_screamer.global_position = _missile.global_position \
			+ (-_missile.global_basis.z) * range_m


func _spawn(at: Vector3) -> Node3D:
	var screamer: Node3D = (load(SCREAMER_SCENE) as PackedScene).instantiate() \
			as Node3D
	# Seeded for determinism (P4.8), set before the node enters the tree.
	screamer.set(&"ai_seed", 0)
	screamer.position = at
	_arena.add_child(screamer)
	return screamer


func _teardown() -> void:
	_pilot = null
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
