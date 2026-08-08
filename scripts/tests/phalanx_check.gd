extends SceneTree

## Headless behaviour check for the PHALANX (GAMEPLAY-DESIGN A7, screen reworked
## in A.q10). Standing rule 2: every bestiary type gets a behaviour check, because
## a results table can only ever say "this cell reads 0%", which is equally
## consistent with a tough enemy, a broken enemy, and an enemy that flew out of
## the level.
##
## THE SHIELD STAGES WERE REWRITTEN WITH THE MECHANIC. The old ones asserted that
## the screen TRACKED its attacker and that an orbit found a reachable opening;
## both became meaningless when the tracking arc was replaced by two rotating
## shells, and leaving either would have left an assertion that passes for a
## reason nobody intends. What survives is the SHAPE that made them worth having:
## every claim is two runs differing in one thing, and the beatability claim FLIES
## THE REAL GEOMETRY rather than asserting on a config field — because whether a
## pilot can get through is a property of the gap widths and the rates TOGETHER,
## and no single-field assertion can catch the pair that fails.
##
##   1. THE SCREEN IS A PATTERN, NOT A FACING. Its open bearings must change over
##      time on their own, and must NOT depend on where the attacker is. The
##      second half is the regression test for the thing that was deleted: if
##      anyone re-adds tracking beside the rotation, this fails.
##   2. ONE SLOT IS NOT AN ANSWER. A pilot camped on one bearing must land
##      materially less than one who flies with a shell — that is P4.2's anti-orbit
##      job, and a SINGLE rotating shell does not do it. Measured, not assumed.
##   3. AND IT MUST STILL BE BEATABLE FROM ANYWHERE. Every bearing has to get a
##      window worth shooting through, inside a bounded wait.
##   4. THE STERN VENT IS A WEAK POINT, NOT A HOLE. A round on the plate reaches
##      the hull while the window is open and does not while it is shut.
##
## Plus the things a new type always has to prove: it is registered everywhere,
## its mounts die one at a time and score, it holds its station (falx bug four,
## and now also the vent collider that pushed the fortress off its own keel), and
## Layer 1 can price it.
##
## SIX MUTATIONS ARE ON RECORD AND EACH FAILS A DIFFERENT SENTENCE — the answer to
## *"would this still pass if the feature were deleted?"*, run rather than
## reasoned:
##
##   delete the second shell   -> camping reads 40% against the shipped 17%
##   stop both shells          -> 9 stages, starting with "0 changes in 30 s"
##   re-add tracking (code)    -> the two attacker positions stop agreeing
##   vent never shuts          -> a shut vent lands 40 points on the hull
##   vent never opens          -> an open vent lands 0
##   vent widened to 100 deg   -> camping astern beats flying the pattern, 55/49
##
## The tracking mutation is the one worth keeping in mind, because it PASSED the
## first version of its own stage: watching a single bearing, a re-added tracker
## left that bearing blocked in both runs, so two constant timelines compared
## equal. The stage now fingerprints eight bearings at once. Same family as the
## seventh unfailable check — *fixing what a test fires on does not fix what it
## reads*.
##
## Run: <godot> --headless -s scripts/tests/phalanx_check.gd --path .

const TICK_HZ: float = 240.0
const PHALANX_AT := Vector3(0.0, 12.0, 0.0)
## Far enough to be outside `preferred_range`, so the body has a reason to hold
## its leash rather than sitting exactly on its spawn.
const PLAYER_AT := Vector3(0.0, 12.0, 40.0)
## Range every screen measurement is taken at — a real fighting distance, and
## comfortably outside `SCREEN_INNER_RADIUS_M`.
const SAMPLE_RANGE_M: float = 30.0

var _failures: int = 0
var _arena: Node3D
var _phalanx: Phalanx
var _player: Node3D


var _started: bool = false


func _initialize() -> void:
	# The static half needs no tree and runs immediately.
	_check_registration()
	_check_the_config()
	# THE FLYING HALF WAITS FOR A REAL FRAME. A node added during `_initialize`
	# is not `is_inside_tree()` until the tree runs, so `get_tree()` inside it
	# returns null and every body-driven stage dies on the first tick. This trap
	# bit three separate rigs on 2026-08-07 alone — the shield timeline, the
	# overlap sweep, and this one — always with a failure that looks like the
	# feature rather than like the harness.
	process_frame.connect(_run_flying_stages)


func _run_flying_stages() -> void:
	if _started:
		return
	_started = true
	_check_the_pattern_turns()
	_check_the_pattern_ignores_the_attacker()
	_check_one_slot_is_not_an_answer()
	_check_every_bearing_opens()
	_check_the_stern_vent()
	_check_mounts_die_one_at_a_time()
	_check_it_holds_station()
	_report()


## ---------- standing rule 4: a new type joins every list the same day ----------

func _check_registration() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_expect(config != null and config.type_id == &"phalanx",
			"the phalanx has a config and it names itself")
	_expect(WarManifest.ROSTER.has(&"phalanx"),
			"the war knows it exists (WarManifest.ROSTER)")
	_expect(WaveDirector.ROSTER.has(&"phalanx"),
			"the arcade run can spawn it (WaveDirector.ROSTER)")
	var planned: bool = false
	for sortie: Array in WaveDirector.PLAN:
		for wave: Dictionary in sortie:
			if wave.has(&"phalanx"):
				planned = true
	_expect(planned, "and some wave actually calls for one (WaveDirector.PLAN)")
	var doctrine: int = 0
	for node_type: StringName in WarManifest.DOCTRINE:
		if WarManifest.DOCTRINE[node_type].has(&"phalanx"):
			doctrine += 1
	_expect(doctrine > 0,
			"the campaign garrisons it somewhere (%d node types)" % doctrine)
	# THE WHOLE REASON THE TYPE EXISTS (A7). Before it, `HEAVY_TYPES` held a
	# bomber that correctly leaves defensive garrisons and a jammer with no
	# weapon, so escalation could only make the war foggier.
	_expect(WarManifest.HEAVY_TYPES.has(&"phalanx"),
			"and it is a HEAVY type, which is the escalation hole A7 was opened for")
	var armed_heavies: int = 0
	for type_id: StringName in WarManifest.HEAVY_TYPES:
		var heavy: EnemyConfig = load(
				"res://resources/default_enemy_%s.tres" % type_id)
		if heavy != null and heavy.damage > 0.0:
			armed_heavies += 1
	_expect(armed_heavies > 0,
			"so escalation now fields something that SHOOTS (%d of %d heavies armed)"
			% [armed_heavies, WarManifest.HEAVY_TYPES.size()])
	# Layer 1 has to be able to price it, or the balance model is blind to the
	# heaviest thing in the game.
	var kestrel: FrameConfig = Frames.config(Frames.KESTREL)
	var incoming: Dictionary = Lethality.incoming(config, kestrel)
	_expect(incoming["mode"] == &"ranged",
			"Layer 3a prices it as a RANGED threat (mode `%s`)" % incoming["mode"])
	# AND ITS BATTERY IS PART OF ITS DURABILITY. Six mounts of 100 sit in front of
	# the hull and every round from every bearing meets one first, so a model that
	# priced the hull alone was 600 points short of the fight.
	var target: Dictionary = Lethality.target_from_enemy(config)
	_expect(float(target["hull"]) > config.hull,
			"and Layer 1 counts its MOUNTS as durability — %.0f points, not %.0f"
			% [target["hull"], config.hull])


func _check_the_config() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	# TWO SHELLS, and the count is the design (A.q10). One rotating shell can be
	# beaten from a standing start — you park in its slot's path and fire every
	# time it comes round — which is exactly the orbit this type exists to refuse.
	_expect(config.shield_outer_gaps > 0 and config.shield_inner_gaps > 0,
			"the screen has TWO shells (%d and %d slots), because one can be timed from a single slot"
			% [config.shield_outer_gaps, config.shield_inner_gaps])
	# COUNTER-ROTATING, and at different magnitudes. Equal-and-opposite rates make
	# the joint opening appear at a FIXED set of bearings, which is a camping spot
	# by construction; the same sign makes the two shells drift together slowly
	# and hands a matched pilot an enormous window.
	_expect(config.shield_outer_rate_deg_s * config.shield_inner_rate_deg_s < 0.0,
			"and they turn OPPOSITE ways (%+.0f and %+.0f deg/s)"
			% [config.shield_outer_rate_deg_s, config.shield_inner_rate_deg_s])
	_expect(not is_equal_approx(absf(config.shield_outer_rate_deg_s),
			absf(config.shield_inner_rate_deg_s)),
			"at different rates, so their alignments do not land on a fixed set of bearings")
	for label: String in ["outer", "inner"]:
		var gaps: int = config.shield_outer_gaps if label == "outer" \
				else config.shield_inner_gaps
		var gap_deg: float = config.shield_outer_gap_deg if label == "outer" \
				else config.shield_inner_gap_deg
		_expect(gap_deg * float(gaps) < 360.0,
				"the %s shell is armour rather than a ring of holes (%d x %.0f = %.0f of 360 deg open)"
				% [label, gaps, gap_deg, gap_deg * float(gaps)])
	_expect(config.stern_vent_arc_deg > 0.0
			and config.stern_vent_open_s > 0.0
			and config.stern_vent_cycle_s > config.stern_vent_open_s,
			"it carries a stern vent that OPENS AND SHUTS (%.0f deg, %.1f s of every %.1f s)"
			% [config.stern_vent_arc_deg, config.stern_vent_open_s,
			config.stern_vent_cycle_s])
	# A PERMANENTLY EXPOSED STERN IS A CAMPING SPOT, and it would make the whole
	# rotation decoration. The user's call was a window; this is that call, held.
	_expect(config.stern_vent_open_s / config.stern_vent_cycle_s < 0.5,
			"and it is shut most of the time (%.0f%% open), so the stern is a window rather than an address"
			% (100.0 * config.stern_vent_open_s / config.stern_vent_cycle_s))
	_expect(config.mount_count >= 3,
			"it carries %d mounts, so there is no bearing without a gun on it"
			% config.mount_count)
	_expect(config.mount_hull > 0.0 and config.mount_hull < config.hull * 0.5,
			"a mount is cheap next to the body — %.0f against %.0f — so stripping one is a reward, not a second boss"
			% [config.mount_hull, config.hull])
	var aegis: EnemyConfig = load("res://resources/default_enemy_aegis.tres")
	# THE CONTROL for the whole design, and it says more than it used to. The two
	# shielded types no longer even share a mechanism: the aegis's screen is a
	# POOL you spend, gated on weapon choice; the phalanx's is a BARRIER you time,
	# which is why its pool is zero. Without this, "make the phalanx's shield
	# rotate" could be satisfied by making every shield rotate, quietly deleting
	# v1.25's weapon-choice gate.
	_expect(aegis.shield_outer_gaps == 0 and aegis.shield_inner_gaps == 0,
			"while the aegis's screen stays all-round, so the two are countered on different axes")
	_expect(aegis.shield_break_threshold > 0.0 and aegis.shield_max > 0.0,
			"the aegis gates on WEAPON CHOICE with a pool to spend (%.0f points over a %.0f threshold)"
			% [aegis.shield_max, aegis.shield_break_threshold])
	_expect(is_zero_approx(config.shield_max),
			"and the phalanx keeps NO pool (%.0f), because a barrier that could be emptied would stop being a barrier"
			% config.shield_max)


## ---------- A.q10 claim 1: the screen is a PATTERN, not a facing ----------

## It turns on its own, with nothing shooting it and nobody in front of it. A
## screen that never changed on a bearing would be a wall; the old arc's whole
## counterplay was that it MOVED, and the replacement has to keep that without
## anybody having to provoke it.
func _check_the_pattern_turns() -> void:
	_build(_config())
	# A BEAM bearing, not astern: the stern has a designed hole in it, so watching
	# it would count the vent's cycle as the shells turning.
	var bearing := Vector3(1.0, 0.0, 0.0)
	var flips: int = 0
	var was: bool = _phalanx.screen_blocks(bearing)
	var dt: float = 1.0 / TICK_HZ
	for i: int in int(30.0 * TICK_HZ):
		_hold_player_at(bearing)
		_advance(dt)
		var now: bool = _phalanx.screen_blocks(bearing)
		if now != was:
			flips += 1
		was = now
	_expect(flips >= 6,
			"the screen opens and shuts on a fixed bearing all by itself — %d changes in 30 s"
			% flips)
	_teardown()


## THE REGRESSION TEST FOR THE THING THAT WAS DELETED (A.q10). The screen used to
## steer for the threat it could see. That worked, read as broken twice, and was
## replaced — so the replacement has to be provably INDEPENDENT of where the
## attacker stands, or the two mechanics end up living side by side and the
## rotation becomes decoration on a tracker.
##
## Two runs, one variable, and the variable is the only thing the old mechanic
## looked at: the same body from the same seed, with the stand-in parked on
## opposite sides, sampled along a THIRD bearing that is neither of them. The two
## timelines have to be identical tick for tick.
func _check_the_pattern_ignores_the_attacker() -> void:
	var here: String = _timeline(Vector3(0.0, 0.0, 1.0))
	var there: String = _timeline(Vector3(0.0, 0.0, -1.0))
	_expect(here == there,
			"the pattern is the same whoever is standing where — %d samples identical from both sides"
			% here.length())
	# And it must not be a trivially constant string, or "identical" is worth
	# nothing: a screen welded shut passes any comparison of two welded screens.
	# THIS GUARD IS NOT DECORATION — it is what caught the tracking mutation when
	# the equality above did not. Watching ONE bearing, a re-added tracker left it
	# blocked in both runs, so two all-blocked timelines compared equal and the
	# headline assertion passed on a body that had exactly the defect it exists to
	# refuse. The sweep below is the real fix; this stayed as the second line.
	_expect(here.contains("0") and here.contains("1"),
			"and the timeline it agrees on actually varies (%s...)" % here.substr(0, 24))


## The blocked/open history of the WHOLE SCREEN, as a string of 0s and 1s, with
## the stand-in parked at `stand_at` throughout.
##
## EIGHT BEARINGS PER SAMPLE, not one. A single watched bearing can be blocked
## under both the real mechanic and a tracker, in which case the comparison is
## between two constant strings and proves nothing. Sweeping the circle makes the
## sample a fingerprint of the pattern's POSITION, which is the thing a tracker
## would move and the rotation would not.
const TIMELINE_BEARINGS: int = 8


func _timeline(stand_at: Vector3) -> String:
	_build(_config())
	var out: String = ""
	var dt: float = 1.0 / TICK_HZ
	var stride: int = int(TICK_HZ * 0.1)
	for i: int in int(20.0 * TICK_HZ):
		_hold_player_at(stand_at)
		_advance(dt)
		if i % stride != 0:
			continue
		for b: int in TIMELINE_BEARINGS:
			var angle: float = TAU * float(b) / float(TIMELINE_BEARINGS)
			out += "1" if _phalanx.screen_blocks(
					Vector3(sin(angle), 0.0, cos(angle))) else "0"
	_teardown()
	return out


## ---------- A.q10 claim 2: one slot is not an answer (P4.2) ----------

## THE ASSERTION THE TYPE'S ROLE STANDS ON, and the one that had to be designed
## rather than hoped for. P4.2 gives this type the job of punishing the
## peel-and-kill orbit, and the tracking arc did it by chasing you. A rotating
## screen has to do it some other way or the type quietly changes role.
##
## Two shells at incommensurate rates are that other way: a pilot camped on one
## bearing waits on BOTH patterns aligning, while a pilot who flies with one
## shell sits inside its slot and only has to time the other. Measured on the
## real body rather than argued: camp about 17% of the time open, fly with a
## shell about 42%.
##
## WOULD THIS PASS IF THE FEATURE WERE DELETED? No, and that is the point. Delete
## the inner shell and the camper's fraction jumps to the outer shell's own duty
## — 38% — which fails the ceiling below by a wide margin. The single-shell case
## is the mutation this stage exists to catch.
const CAMP_OPEN_CEILING: float = 0.25
const READING_ADVANTAGE: float = 1.6


func _check_one_slot_is_not_an_answer() -> void:
	# THE VENT IS OFF FOR THIS PAIR, and the first version of this stage is why.
	# It camped the pilot on bearing (0,0,1) — which is dead astern, the one
	# bearing with a designed hole in it — and read 34% open instead of 17%,
	# nearly failing the type's own role assertion by measuring the weak point.
	# The claim here is about the SHELL PATTERN; the vent is asserted on its own
	# below, including the guard that it does not turn the stern into the best
	# camp on the body.
	var camped: float = _open_fraction(0.0, false, false, PI * 0.5)
	var config: EnemyConfig = _config()
	var flown: float = _open_fraction(config.shield_outer_rate_deg_s, true, false, 0.0)
	_expect(camped < CAMP_OPEN_CEILING,
			"camping on one bearing leaves the screen shut most of the time (%.0f%% open)"
			% (100.0 * camped))
	_expect(flown > camped * READING_ADVANTAGE,
			"while flying WITH a shell is worth %.1fx as much damage (%.0f%% against %.0f%%)"
			% [flown / maxf(camped, 0.001), 100.0 * flown, 100.0 * camped])
	# AND THE WEAK POINT MUST NOT UNDO THAT, which is the objection the stern vent
	# was designed against: *"a permanently exposed stern is a camping spot, and it
	# would make the rotating screen decoration."* The answer was a window, and
	# this is the arithmetic of that answer — camping astern with the vent cycling
	# has to stay worse than reading the pattern and flying it.
	var stern_camp: float = _open_fraction(0.0, false, true, 0.0)
	var flown_live: float = _open_fraction(config.shield_outer_rate_deg_s,
			true, true, 0.0)
	_expect(stern_camp < flown_live,
			"and camping ASTERN on the vent is still worse than flying the pattern (%.0f%% against %.0f%%)"
			% [100.0 * stern_camp, 100.0 * flown_live])


## Fraction of a 90 s pass on which the screen is OPEN along the pilot's own
## bearing, orbiting at `rate_deg_s` from `start_angle`. `lock_to_outer` starts
## the pilot dead centre in an outer slot, which is what a pilot who has read the
## pattern does — averaging over random start phases instead would be measuring a
## coin flip the player never has to take. `with_vent` decides whether the stern
## aperture is in play, because it answers a different question from the shells.
func _open_fraction(rate_deg_s: float, lock_to_outer: bool, with_vent: bool,
		start_angle: float) -> float:
	var total: float = 0.0
	var seeds: Array[int] = [0, 1, 2, 3]
	for seed_value: int in seeds:
		var config: EnemyConfig = _config()
		if not with_vent:
			config = config.duplicate() as EnemyConfig
			config.stern_vent_arc_deg = 0.0
		_build(config, seed_value)
		var dt: float = 1.0 / TICK_HZ
		var angle: float = _phalanx.ring_phase(0) if lock_to_outer else start_angle
		var open_ticks: int = 0
		var steps: int = int(90.0 * TICK_HZ)
		for i: int in steps:
			angle += deg_to_rad(rate_deg_s) * dt
			var bearing := Vector3(sin(angle), 0.0, cos(angle))
			_hold_player_at(bearing)
			_advance(dt)
			if not _phalanx.screen_blocks(bearing):
				open_ticks += 1
		total += float(open_ticks) / float(steps)
		_teardown()
	return total / float(seeds.size())


## ---------- A.q10 claim 3: and it must still be BEATABLE ----------

## THE ASSERTION THAT KEEPS THE TYPE KILLABLE, and it flies the real geometry
## rather than reasoning about it — because beatability is a property of the gap
## widths and the rates TOGETHER. Its predecessor learned that the hard way: a
## 250 degree arc opens promptly at 28 deg/s and never opens at all at 45, and no
## assertion on either number alone could tell those apart.
##
## Here the failure with the same shape is a shell that does not turn. Every
## static configuration passes "the slots are wide enough" and "there are two
## shells", and leaves bearings that are shut forever. So this walks TWELVE
## bearings and asserts the WORST of them still gets a window worth shooting
## through, inside a bounded wait.
const BEARINGS_WALKED: int = 12
const WINDOW_FLOOR_S: float = 0.6
const WAIT_CEILING_S: float = 15.0


func _check_every_bearing_opens() -> void:
	_build(_config())
	var dt: float = 1.0 / TICK_HZ
	var best_window: Array[float] = []
	var worst_wait: Array[float] = []
	for i: int in BEARINGS_WALKED:
		best_window.append(0.0)
		worst_wait.append(0.0)
	var current: Array[float] = best_window.duplicate()
	var waiting: Array[float] = best_window.duplicate()
	for step: int in int(40.0 * TICK_HZ):
		_hold_player_at(Vector3(0.0, 0.0, 1.0))
		_advance(dt)
		for i: int in BEARINGS_WALKED:
			var angle: float = TAU * float(i) / float(BEARINGS_WALKED)
			var bearing := Vector3(sin(angle), 0.0, cos(angle))
			if _phalanx.screen_blocks(bearing):
				current[i] = 0.0
				waiting[i] += dt
				worst_wait[i] = maxf(worst_wait[i], waiting[i])
			else:
				current[i] += dt
				waiting[i] = 0.0
				best_window[i] = maxf(best_window[i], current[i])
	var tightest: float = INF
	var longest_wait: float = 0.0
	for i: int in BEARINGS_WALKED:
		tightest = minf(tightest, best_window[i])
		longest_wait = maxf(longest_wait, worst_wait[i])
	_expect(tightest > WINDOW_FLOOR_S,
			"every one of %d bearings gets a firing window — the tightest is %.2f s, which is a burst rather than a flicker"
			% [BEARINGS_WALKED, tightest])
	_expect(longest_wait < WAIT_CEILING_S,
			"and none of them waits longer than %.1f s for one, so no bearing is a wall"
			% longest_wait)
	_teardown()


## ---------- A.q10 claim 4: the stern vent ----------

## THE WEAK POINT, held by the two-run shape. Same body, same plate, same round;
## the only difference is whether the window is open.
##
## The load-bearing assertion is not "it takes damage" — a shut vent takes damage
## too, into a mount, like any other bearing. It is that an OPEN vent puts the
## round on the HULL, past the screen and past the whole battery. That bypass is
## the entire reward for being astern at the right moment with a steady gun, and
## it is what a permanently-open or never-open vent would break.
func _check_the_stern_vent() -> void:
	var open_hit: Dictionary = _shoot_the_vent(true)
	var shut_hit: Dictionary = _shoot_the_vent(false)
	_expect(open_hit["hull_lost"] > 0.0,
			"a round on the plate while the vent is OPEN reaches the hull (%.0f points)"
			% open_hit["hull_lost"])
	_expect(open_hit["mounts_lost"] == 0,
			"past the whole battery rather than into it (%d mounts stripped)"
			% open_hit["mounts_lost"])
	_expect(is_zero_approx(float(shut_hit["hull_lost"])),
			"the SAME round on a shut vent does not (%.0f points to the hull)"
			% shut_hit["hull_lost"])
	# AND THE APERTURE IS REAL. The vent's window is cut through both shells while
	# it lasts, which is what makes the picture and the rule the same thing — and
	# without it, being astern during the window would still be gated by the
	# pattern and the weak point would be worth almost nothing.
	_expect(bool(open_hit["astern_open"]),
			"and the screen itself opens astern while the window lasts")
	_expect(not bool(shut_hit["astern_open"])
			or bool(shut_hit["astern_open_by_slot"]),
			"while a shut vent leaves the stern to the ordinary pattern")


## One round onto the vent plate, waited until the window is in the wanted state.
func _shoot_the_vent(want_open: bool) -> Dictionary:
	_build(_config())
	var dt: float = 1.0 / TICK_HZ
	# Stand astern, which is where a pilot using this has to be.
	var astern: Vector3 = _phalanx.global_basis.z
	var waited: float = 0.0
	# SETTLE INTO THE STATE rather than firing on the tick it changes: the vent's
	# own clock and the shells' are independent, and a round fired on the opening
	# tick measures a boundary rather than the mechanic.
	while waited < 30.0:
		_hold_player_at(astern)
		_advance(dt)
		waited += dt
		if _phalanx.vent_open() == want_open and _phalanx.vent_charge() > 0.15:
			break
	var health: Node = _phalanx.get_node("Health")
	var hull_before: float = float(health.get(&"current"))
	var mounts_before: int = _phalanx.mounts_alive()
	# Straight at the plate, which is how a round actually arrives: the vent is a
	# physics body, so only rounds that HIT it get this path.
	_phalanx.get_node("SternVent").call("take_hit", 40.0)
	var result: Dictionary = {
		"hull_lost": hull_before - float(health.get(&"current")),
		"mounts_lost": mounts_before - _phalanx.mounts_alive(),
		"astern_open": not _phalanx.screen_blocks(astern),
		# A shut vent can still sit under an ordinary slot; that is not a failure,
		# it is the pattern doing its job, so the assertion has to allow it.
		"astern_open_by_slot": not _phalanx.vent_open(),
	}
	_teardown()
	return result


## ---------- the mounts die one at a time, and stop shooting ----------

func _check_mounts_die_one_at_a_time() -> void:
	var config: EnemyConfig = _config()
	_build(config)
	_expect(_phalanx.mounts_alive() == config.mount_count,
			"it arrives with all %d mounts" % config.mount_count)
	# Park where the screen is OPEN before firing, or the rounds are refused and
	# nothing below means anything. With the arc this was "stand behind it"; with
	# a pattern it is "wait for your slot", which is the mechanic in one line.
	var bearing: Vector3 = _wait_for_an_opening()
	var scored: Array[float] = []
	_phalanx.mount_destroyed.connect(func(points: float) -> void:
			scored.append(points))
	_phalanx.take_hit(config.mount_hull)
	_expect(_phalanx.mounts_alive() == config.mount_count - 1,
			"one mount's worth of damage takes exactly ONE mount off (%d left)"
			% _phalanx.mounts_alive())
	_expect(scored.size() == 1 and scored[0] > 0.0,
			"and it scores, so stripping guns is progress rather than a chore (%.0f points)"
			% (scored[0] if scored.size() > 0 else 0.0))
	# AND SOMETHING HAS TO BE LISTENING, which the assertion above does not check.
	# It was written first, it passed from the day it was written, and the signal
	# had NO connection anywhere in the game — so six mounts were worth nothing to
	# the player while this check reported that stripping guns scores.
	#
	# An assertion about a SIGNAL is not an assertion about an OUTCOME. Both
	# spawners are read as source here rather than flown, because the two of them
	# are the only paths a Phalanx can reach a player through, and a structural
	# assertion is the cheapest thing that could have caught it.
	for spawner: String in ["res://scripts/combat/wave_director.gd",
			"res://scripts/sortie/sortie_runner.gd"]:
		var source: String = FileAccess.get_file_as_string(spawner)
		_expect(source.contains("mount_destroyed"),
				"and %s connects it, so the points reach the player"
				% spawner.get_file())
		# NOT through the kill counter: six mounts are not six kills, and in a
		# sortie that number is priced into the war's dent per type.
		_expect(not source.contains("mount_destroyed\", _on_points_scored"),
				"without booking a KILL for it in %s — you damaged it, you did not destroy a unit"
				% spawner.get_file())
	var hull_before: float = float(_phalanx.get_node("Health").get(&"current"))
	# A SECOND volley through the same opening must find the NEXT mount, not the
	# hull: `_mount_facing` skipping dead mounts is what makes stripping the guns
	# a sequence rather than an instant hole.
	if not _phalanx.screen_blocks(bearing):
		_phalanx.take_hit(config.mount_hull)
		_expect(_phalanx.mounts_alive() == config.mount_count - 2,
				"the next volley through the same opening finds the NEXT mount (%d left)"
				% _phalanx.mounts_alive())
		_expect(is_equal_approx(float(_phalanx.get_node("Health").get(&"current")),
				hull_before),
				"and the hull is untouched while a gun still covers that side")
	_teardown()


## Steps the body until the screen is open along the stand-in's bearing, and
## returns that bearing. Fails loudly rather than silently shooting a wall.
func _wait_for_an_opening() -> Vector3:
	var bearing := Vector3(1.0, 0.0, 0.0)
	var dt: float = 1.0 / TICK_HZ
	var waited: float = 0.0
	while waited < 30.0:
		_hold_player_at(bearing)
		_advance(dt)
		waited += dt
		if not _phalanx.screen_blocks(bearing):
			return bearing
	_expect(false, "an opening appeared on the test bearing inside 30 s")
	return bearing


## ---------- falx bug four, held for this type ----------

## A7 says it HOLDS GROUND and does not chase. That is a design claim and also
## the bug that broke the falx twice: a body with no leash flies out of the
## level, and the harness cannot tell that apart from a tough enemy.
func _check_it_holds_station() -> void:
	var config: EnemyConfig = _config()
	_build(config)
	# A player a long way off: a chaser would set out after them.
	_player.global_position = PHALANX_AT + Vector3(200.0, 0.0, 0.0)
	_advance(6.0)
	var drift: float = _phalanx.global_position.distance_to(PHALANX_AT)
	_expect(drift < Phalanx.STATION_DRIFT_M + 6.0,
			"it HOLDS ITS GROUND rather than chasing — %.1f m from its station after 6 s"
			% drift)
	_teardown()
	# AND IT DOES NOT PUSH ITSELF OFF ITS OWN KEEL, which is a different failure
	# and a real one: the stern vent is a second physics body bolted to this one,
	# overlapping the hull's own shape, so `move_and_slide` depenetrated against
	# its own child and slid the fortress away at its full 5 m/s. Measured at
	# 49.6 m in 5 seconds before `add_collision_exception_with`, and it looked
	# exactly like an AI bug from the results.
	#
	# The stage above cannot see it: with the player 200 m away the body is
	# ALLOWED to drift 14 m, so the honest test is the one case where it is
	# allowed to drift nothing at all — a player parked exactly on its standoff.
	_build(config)
	_player.global_position = PHALANX_AT + Vector3(0.0, 0.0, config.preferred_range)
	_advance(6.0)
	var slide: Vector3 = _phalanx.global_position - PHALANX_AT
	slide.y = 0.0
	_expect(slide.length() < 0.5,
			"and it does not slide against its own vent collider — %.2f m horizontally in 6 s at its standoff"
			% slide.length())
	_teardown()


## ---------- rig ----------

func _config() -> EnemyConfig:
	return load("res://resources/default_enemy_phalanx.tres") as EnemyConfig


## Keeps the stand-in on `bearing` at a fixed range, so the body's own station
## keeping never changes the geometry a screen measurement is taken at.
func _hold_player_at(bearing: Vector3) -> void:
	_player.global_position = _phalanx.global_position \
			+ bearing.normalized() * SAMPLE_RANGE_M


func _build(config: EnemyConfig, seed_value: int = 0) -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_player = Node3D.new()
	_player.add_to_group(&"player")
	_player.set_script(load("res://scripts/tests/_lance_dummy.gd"))
	_arena.add_child(_player)
	_player.position = PLAYER_AT
	_phalanx = (load("res://scenes/combat/phalanx.tscn") as PackedScene)\
			.instantiate() as Phalanx
	_phalanx.enemy_config = config
	_phalanx.ai_seed = seed_value
	_phalanx.position = PHALANX_AT
	_arena.add_child(_phalanx)
	# The engine must NOT also be stepping it: `_advance` drives the body by hand
	# so the timeline under test is the check's rather than the scheduler's, and
	# two sources of ticks would make every measurement below depend on how many
	# frames happened to elapse.
	_phalanx.set_physics_process(false)
	# One step so the body has resolved its state and built its mounts and shells
	# before anything is asserted about them.
	_advance(1.0 / TICK_HZ)


## Steps the body by hand rather than awaiting frames, so the whole check is
## synchronous and deterministic. `_physics_process` is the entire behaviour.
func _advance(seconds: float) -> void:
	var dt: float = 1.0 / TICK_HZ
	var steps: int = maxi(int(seconds * TICK_HZ), 1)
	for i: int in steps:
		if not is_instance_valid(_phalanx):
			return
		_phalanx._physics_process(dt)


func _teardown() -> void:
	if _arena != null:
		_arena.free()
	_arena = null
	_phalanx = null
	_player = null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[phalanx_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[phalanx_check]  FAIL  %s" % message)


func _report() -> void:
	if _failures == 0:
		print("[phalanx_check] PASS")
	else:
		print("[phalanx_check] FAIL - %d check(s)" % _failures)
	quit(0 if _failures == 0 else 1)
