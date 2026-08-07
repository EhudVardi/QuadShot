extends SceneTree

## Headless behaviour check for the LANCE (Iteration 14 / A5, A.q5, A.q6).
## The twenty-first check, and it lands the day the type does — standing rule 2:
## *every new bestiary type gets a behaviour check the day it lands*, because a
## results table can only ever say "this cell reads 0%", which is equally
## consistent with a tough enemy, a broken enemy, and an enemy that flew out of
## the level. Four separate Falx bugs looked identical from the results table,
## and one of them was invisible to every test because it only happened before
## the player armed.
##
## Six things it holds, each of which is a decision somebody made:
##
##   1. A5 — it TELEGRAPHS. There is a measurable stretch where it has chosen and
##      has not yet moved, and that window is the whole type.
##   2. A5 — the run is COMMITTED: it flies at where you WERE, so a player who
##      moves after the commit does not get followed.
##   3. A5 — it spends itself on arrival, exactly once, and says so.
##   4. A5 — killing it during the telegraph costs you NO blast. That is the
##      reward the window exists to offer.
##   5. Falx bug four, held for this type: with no player on the field it stays
##      put instead of flying over the horizon.
##   6. A.q6 — it targets the player, and the seam that will one day rank targets
##      is a single function. Asserted so that when the ranking layer lands,
##      whoever moves it is told where the placeholder was.
##   7. A.q8 — the proximity WARNING rises as the danger does. A headless check
##      cannot hear a sound, so it holds the scalar the sound is made of
##      (`warning_level()`) and compares two runs that differ only in how close
##      the thing got. A cue driven by a timer, a phase flag or a constant passes
##      every single-run assertion and fails that comparison.
##
## Run: <godot> --headless -s scripts/tests/lance_check.gd --path .

const TICK_HZ: float = 240.0
const MAX_SECONDS: float = 60.0
## Where the stand-in player sits. Far enough that the Lance has to close, seek,
## and set up before it can commit.
const PLAYER_AT := Vector3(0.0, 14.0, 0.0)
const LANCE_AT := Vector3(0.0, 14.0, 70.0)

var _failures: int = 0
var _arena: Node3D
var _lance: Lance
var _player: Node3D
var _ticks: int = 0
var _stage: int = 0
var _detonated: int = 0
var _blast_taken: float = 0.0
## Ticks the body spent nearly stationary while a player was in sight — the
## telegraph, measured rather than asserted from the constant.
var _still_ticks: int = 0
var _seen_moving: bool = false
## Telegraph state last tick, so the true -> false EDGE can be detected.
var _was_telegraphing: bool = false
var _committed_at: Vector3 = Vector3.INF
var _drift_after_commit: float = 0.0
var _start_distance: float = 0.0
## A.q8's warning, sampled per tick. `_warn_before` is the loudest it ever got
## while the type was still harmless; `_warn_peak` the loudest overall; `_warn_last`
## the value on the final tick before it spent itself, which is what ties the cue
## to the fuse.
var _warn_before: float = 0.0
## Latched once the body has been seen telegraphing, so "was it silent while it
## was harmless" is decided from the outside rather than from the feature's own
## phase enum. Independent of `_was_telegraphing`, which the run stage needs for
## its EDGE and must not have moved under it.
var _warn_seen_telegraph: bool = false
var _warn_at_lock: float = 0.0
var _warn_peak: float = 0.0
var _warn_last: float = 0.0
## Stage 0's peak, kept across the rebuild so stage 2 can be compared against it.
var _wide_warn_peak: float = -1.0
## A.q9's steering, stages 3 and 4. `_steer_override` is forced onto the config
## the stage builds; `_closest` is the nearest the body got to the dodged player
## during its run, which is the number the whole feature is judged on.
var _steer_override: float = -1.0
var _closest: float = INF
var _rail_closest: float = -1.0


func _initialize() -> void:
	_check_registration()
	_check_the_seam()
	_check_the_fuse()
	_check_the_warning_wiring()
	if _failures > 0:
		_report()
		return
	_stage = 0
	_build(true)
	physics_frame.connect(_on_physics_frame)


## ---------- standing rule 4: a new type joins every list the same day ----------

func _check_registration() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_lance.tres")
	_expect(config != null and config.type_id == &"lance",
			"the lance has a config and it names itself")
	_expect(WarManifest.ROSTER.has(&"lance"),
			"the war knows it exists (WarManifest.ROSTER)")
	_expect(WaveDirector.ROSTER.has(&"lance"),
			"the arcade run can spawn it (WaveDirector.ROSTER)")
	# A type in the ROSTER that no wave ever spends its budget on is a type the
	# player never meets, which is the same as not having built it.
	var planned: bool = false
	for sortie: Array in WaveDirector.PLAN:
		for wave: Dictionary in sortie:
			if wave.has(&"lance"):
				planned = true
	_expect(planned, "and some wave actually calls for one (WaveDirector.PLAN)")
	var doctrine: int = 0
	for node_type: StringName in WarManifest.DOCTRINE:
		if WarManifest.DOCTRINE[node_type].has(&"lance"):
			doctrine += 1
	_expect(doctrine > 0,
			"the campaign garrisons it somewhere (%d node types)" % doctrine)
	# It kills by CONTACT, so it must carry a blast rather than a gun. Both halves
	# matter: a Lance with a gun would be a different enemy.
	_expect(config.bomb_damage > 0.0 and config.bomb_radius > 0.0,
			"it carries a blast (%.0f damage, %.0f m)"
			% [config.bomb_damage, config.bomb_radius])
	_expect(is_zero_approx(config.damage) and is_zero_approx(config.fire_rate),
			"and no gun, so Layer 1 prices it as contact rather than as a cadence")
	# AND LAYER 3a HAS TO AGREE, which it did not until this assertion existed.
	# `Lethality.incoming` branched on `damage <= 0` and reported mode `none` —
	# "carries no weapon against the player" — for a body that spends 55 damage on
	# arrival. The harness printed that sentence under all three Lance rows for a
	# whole run before anyone read it.
	#
	# The original version of this check asserted the CONFIG (no gun, has a blast)
	# and never asked what the MODEL made of it, which is the difference between
	# checking your inputs and checking your instrument.
	var kestrel: FrameConfig = Frames.config(Frames.KESTREL)
	var incoming: Dictionary = Lethality.incoming(config, kestrel)
	_expect(incoming["mode"] == &"contact",
			"and Layer 3a prices it as a CONTACT threat, not as harmless (mode `%s`)"
			% incoming["mode"])
	_expect(float(incoming["hull_fraction"]) > 0.0,
			"so it costs a Kestrel real hull — %.0f%% of it in one blast"
			% (float(incoming["hull_fraction"]) * 100.0))
	# The aegis is the CONTROL, and it must stay `none`: it carries ordnance aimed
	# at your GROUND rather than at you, which the war prices instead. Without
	# this, "make the Lance contact" could be done by making every blast type
	# contact, and the aegis's v1.72 finding would be silently overwritten.
	var aegis: EnemyConfig = load("res://resources/default_enemy_aegis.tres")
	_expect(Lethality.incoming(aegis, kestrel)["mode"] == &"none",
			"while the aegis stays `none`, because it spends its bombs on your ground")
	# P4.2 calls it cheap and expendable - the type a losing enemy fields MORE of.
	var raider: EnemyConfig = load("res://resources/default_enemy_raider.tres")
	_expect(config.strength_cost < raider.strength_cost * 2.5,
			"it is CHEAP so a pressured node can field several (%.1f vs a raider's %.1f)"
			% [config.strength_cost, raider.strength_cost])
	# The pair that IS the type: fastest in the roster, worst turn in the roster.
	var falx: EnemyConfig = load("res://resources/default_enemy_falx.tres")
	_expect(config.speed > falx.speed,
			"it is the fastest thing in the roster (%.0f vs the falx's %.0f)"
			% [config.speed, falx.speed])
	_expect(config.accel < falx.accel,
			"and the least agile, which is what makes the commitment physical rather than scripted (%.0f vs %.0f)"
			% [config.accel, falx.accel])


## ---------- A.q6: the placeholder, asserted as a placeholder ----------

## THE TARGET-RANKING LAYER DOES NOT EXIST, and the user chose to ship without
## it. This asserts the shape of the shortcut rather than the shortcut itself, so
## that the day somebody builds the ranking they are told where it plugs in and
## the day somebody deletes the seam this check complains.
func _check_the_seam() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/combat/lance.gd")
	_expect(source.contains("func _find_player()"),
			"target selection is ONE function, so the ranking layer replaces one thing")
	_expect(source.count("get_first_node_in_group(&\"player\")") == 1,
			"and it hard-codes the player in exactly one place (A.q6's placeholder)")
	_expect(source.contains("A.q6"),
			"and the file says out loud that this is a placeholder, not a design")


## ---------- the proximity fuse (2026-08-06, flown) ----------

## THE COUNTERPLAY IS A DISTANCE, NOT A BINARY. The user flew the first version
## and found that *"if i fly towards it and side step slightly, it just passes me
## and explode in the original location"* — so a committed run could be beaten by
## a metre, which made "commit to a point in space" mean "commit to missing".
##
## Asserted as ARITHMETIC here and as a flown pass below, because the two can
## disagree: the ordering of the three radii is a design claim, and whether a
## near miss actually trips the fuse is a behaviour claim.
func _check_the_fuse() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_lance.tres")
	_expect(config.blast_fuse_radius > 0.0,
			"the Lance carries a proximity fuse (%.0f m)" % config.blast_fuse_radius)
	# The fuse must be WIDER than the blast, or there is no graze band at all and
	# the dodge goes back to being an edge: in one metre you are unhurt, in the
	# next you take the full 55.
	_expect(config.blast_fuse_radius > config.bomb_radius,
			"and it is wider than the blast, so a near miss GRAZES instead of missing (%.0f m fuse vs %.0f m blast)"
			% [config.blast_fuse_radius, config.bomb_radius])
	# And it must not be so wide that dodging is pointless. A run the player
	# cannot get outside of is a run with no counterplay, which is the opposite
	# failure and just as bad.
	_expect(config.blast_fuse_radius < config.preferred_range * 0.5,
			"while still being dodgeable — the fuse is well inside the setup range (%.0f m vs %.0f m)"
			% [config.blast_fuse_radius, config.preferred_range])


## ---------- A.q8: the warning, wired ----------

## THE PARTS THAT MAKE A SOUND, asserted separately from the scalar that drives
## it, because they fail in different ways. The flight stages below prove the
## scalar rises with the danger — but a scalar with no emitter attached is a
## silent feature that passes every behaviour test in this file.
##
## The attenuation assertion is the one worth spelling out. 3D rolloff and the
## fuse's envelope are two different curves, so leaving the default model on would
## quietly re-introduce a second loudness curve that disagrees with the mechanic —
## which is the exact trap the screamer's `JamTone` carries a paragraph about. It
## is set to DISABLED in the scene and `lance.gd` drives `volume_db` itself.
func _check_the_warning_wiring() -> void:
	var stream: AudioStreamWAV = SoundBank.make_warning_loop()
	_expect(stream != null and stream.data.size() > 0,
			"the bank makes a warning stream (%d bytes)"
			% (0 if stream == null else stream.data.size()))
	_expect(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"and it LOOPS, so the warning is continuous rather than another one-shot")
	var scene := (load("res://scenes/combat/lance.tscn") as PackedScene).instantiate()
	var emitter := scene.get_node_or_null(^"Warning") as AudioStreamPlayer3D
	_expect(emitter != null, "the Lance carries a warning emitter")
	if emitter != null:
		_expect(emitter.attenuation_model
				== AudioStreamPlayer3D.ATTENUATION_DISABLED,
				"with 3D rolloff DISABLED, so the fuse is the only loudness curve in play")
	scene.free()


## ---------- the flight ----------

func _build(with_player: bool) -> void:
	if _arena != null:
		_arena.free()
	_ticks = 0
	_still_ticks = 0
	_seen_moving = false
	_was_telegraphing = false
	_detonated = 0
	_blast_taken = 0.0
	_committed_at = Vector3.INF
	_drift_after_commit = 0.0
	_warn_before = 0.0
	_warn_seen_telegraph = false
	_warn_at_lock = 0.0
	_warn_peak = 0.0
	_warn_last = 0.0
	_closest = INF
	_arena = Node3D.new()
	root.add_child(_arena)
	if with_player:
		_player = _make_player()
		_arena.add_child(_player)
		_player.position = PLAYER_AT
	else:
		_player = null
	_lance = (load("res://scenes/combat/lance.tscn") as PackedScene).instantiate() as Lance
	var config: EnemyConfig = load("res://resources/default_enemy_lance.tres")
	if _steer_override >= 0.0:
		# Duplicated, never mutated in place — the .tres is a shared instance and
		# every other stage in this file reads the same object.
		config = config.duplicate() as EnemyConfig
		config.run_steer_deg_s = _steer_override
	_lance.enemy_config = config
	_lance.ai_seed = 0
	_lance.position = LANCE_AT
	_arena.add_child(_lance)
	_lance.detonated.connect(func() -> void: _detonated += 1)
	_start_distance = LANCE_AT.distance_to(PLAYER_AT)


## A stand-in player: the `player` group, a `team`, and a `take_hit` that records
## what the blast did. Deliberately NOT a real drone — this check is about the
## Lance's behaviour, and a flight model in the loop would make a failure
## ambiguous between the two.
func _make_player() -> Node3D:
	var body := Node3D.new()
	body.add_to_group(&"player")
	body.set_script(load("res://scripts/tests/_lance_dummy.gd"))
	return body


func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks > int(MAX_SECONDS * TICK_HZ):
		_expect(false, "the lance resolved inside %.0f s (stage %d)"
				% [MAX_SECONDS, _stage])
		_report()
		return
	if _stage == 0:
		_watch_the_run()
	elif _stage == 2:
		_watch_the_near_miss()
	elif _stage == 3 or _stage == 4:
		_watch_the_steering()
	else:
		_watch_without_a_player()


## THE TELEGRAPH EDGE IS THE ONLY HONEST TRIGGER, and getting it wrong made this
## whole stage measure nothing. The first version dodged when the body exceeded
## 12 m/s — but SEEK closes at 17 m/s, so the player teleported at 1.5 s while
## the Lance was still 60 m away and had locked nothing. It then simply
## re-acquired the moved player and hit them, and the "it is COMMITTED" assertion
## passed anyway, on a distance that had nothing to do with commitment.
##
## `telegraphing()` going true -> false IS the lock: that transition is the tick
## the run's aim point is captured. Dodging on that edge is the only test that
## can tell a committed run from a homing one.
func _watch_the_run() -> void:
	if not is_instance_valid(_lance):
		_verify_the_run()
		return
	var telegraphing: bool = _lance.telegraphing()
	# Sampled BEFORE the dodge below, so the lock value is the real range at the
	# moment of commitment rather than the teleported one.
	_sample_warning(telegraphing)
	# Only the FIRST wind-up counts toward the measured telegraph; a later one
	# would inflate it.
	if telegraphing and not _seen_moving:
		_still_ticks += 1
	var locked_now: bool = _was_telegraphing and not telegraphing
	_was_telegraphing = telegraphing
	if locked_now and not _seen_moving:
		_seen_moving = true
		_warn_at_lock = _lance.warning_level()
		_committed_at = _lance.global_position
		# Dodge 40 m, on the tick it committed. A homing enemy would close on the
		# new position; a committed one flies past where the player used to be.
		_player.global_position = PLAYER_AT + Vector3(40.0, 0.0, 0.0)
	if _seen_moving and _player != null and is_instance_valid(_player):
		var range_m: float = _lance.global_position.distance_to(
				_player.global_position)
		_drift_after_commit = maxf(_drift_after_commit, range_m)
		_closest = minf(_closest, range_m)


## One tick of A.q8's readout. `harmless` is true whenever the body has not yet
## reached its first wind-up, which is the stretch the warning must be silent
## through — asserted from the OUTSIDE (has it ever telegraphed) rather than from
## the phase, so the check does not depend on the same enum the feature does.
func _sample_warning(telegraphing: bool) -> void:
	var level: float = _lance.warning_level()
	if telegraphing:
		_warn_seen_telegraph = true
	elif not _warn_seen_telegraph:
		_warn_before = maxf(_warn_before, level)
	_warn_peak = maxf(_warn_peak, level)
	# The LAST value before it spends itself. Kept rather than peaked, because the
	# claim being tested is about the tick the warhead goes off.
	if level > 0.0:
		_warn_last = level


func _verify_the_run() -> void:
	var still_s: float = float(_still_ticks) / TICK_HZ
	_expect(_seen_moving, "it commits to a run and accelerates")
	_expect(still_s > Lance.ALIGN_SECONDS * 0.8,
			"and it TELEGRAPHS first - %.2f s of committed, visible alignment before it moves (design asks %.2f s)"
			% [still_s, Lance.ALIGN_SECONDS])
	_expect(_detonated == 1,
			"it spends itself exactly once, so a wave holding it can clear (%d)"
			% _detonated)
	# THE COMMITMENT ASSERTION, and it is measured on CLOSEST APPROACH because the
	# measure it used until 2026-08-07 could not fail.
	#
	# It used to assert `_drift_after_commit > 20`, a MAXIMUM distance — and the
	# maximum is reached on the very tick of the teleport, before the body has
	# moved at all. Measured across steering rates 0, 6, 12, 20 and 45 deg/s, that
	# number came back as **56.09 m every single time**, identical to two decimals,
	# because it was reporting the length of the dodge rather than anything the
	# Lance did. A perfectly homing enemy passed it. That is the seventh unfailable
	# check found on this project and the first that was inherited rather than
	# freshly written — v2.26 fixed this stage's TRIGGER and left its MEASURE.
	#
	# Closest approach is the honest number: it is exactly what "did it follow me"
	# means. The threshold is set DELIBERATELY rather than to whatever passes —
	# against the same 40 m break, rail and shipped read 40.1 m and 34.3 m, while
	# 12 deg/s reads 19.5 m and 20 deg/s gets inside the fuse at 7.0 m. So 25 m
	# says: *a 40 m committed break must leave at least 25 m of it intact*, which
	# is a real ceiling on A.q9's knob rather than a formality.
	_expect(_closest > 25.0,
			"the run is COMMITTED - a 40 m break left %.1f m of clearance, so it flew at where the player WAS"
			% _closest)
	# THE WIDE-MISS CONTROL. The player was moved 40 m, which is far outside the
	# 11 m fuse, so this run must have cost them NOTHING. Without this the
	# proximity test below could be satisfied by a fuse that always fires.
	# THE WIDE-MISS CONTROL, and it is the partner to the near-miss stage below.
	# A Lance spends itself at its aim point whether or not anyone is there, so a
	# 40 m dodge is one run and one blast, 40 m away. Without this, the proximity
	# fuse could be satisfied by a fuse that simply always fires.
	_expect(_player_taken() == 0.0,
			"and it cost the player NOTHING — a 40 m dodge is a clean miss (%.0f damage)"
			% _player_taken())
	# DELETED 2026-08-07: `_blast_taken > 0 or _drift_after_commit > 0`, asserting
	# "the run resolved rather than looping forever". `_drift_after_commit` is a
	# distance from a teleported player, so it is above zero on the first tick of
	# every possible run — the condition could not be false. The claim it was
	# reaching for is already held twice over: `_detonated == 1` above, and the
	# MAX_SECONDS timeout, which fails loudly and names the stage.
	_verify_the_warning_wide()
	_check_the_window()


## ---------- A.q8: the warning, on a run that MISSED ----------

## Half of the comparison. This run ends 40 m from the player, so it is the
## control: the warning has to be silent while the thing is harmless, audible the
## moment it locks, and it must NEVER reach maximum, because maximum means "inside
## the fuse" and this run was nowhere near.
func _verify_the_warning_wide() -> void:
	_wide_warn_peak = _warn_peak
	_expect(is_zero_approx(_warn_before),
			"the warning is SILENT while the Lance is still harmless (%.2f in SEEK)"
			% _warn_before)
	_expect(_warn_at_lock > 0.0,
			"and it opens on the LOCK rather than on contact (%.2f at commit)"
			% _warn_at_lock)
	# The one-shot `charge` already says "it has chosen". If the loop arrived at
	# full strength there would be nothing left for the run to escalate into, which
	# is the whole complaint A.q8 was opened about.
	_expect(_warn_at_lock < 0.5,
			"quietly, so the RUN has somewhere to escalate to (%.2f of 1.00)"
			% _warn_at_lock)
	_expect(_warn_peak < 0.99,
			"and a run that misses by 40 m never reaches maximum — maximum means INSIDE the fuse (%.2f)"
			% _warn_peak)


## ---------- A5: killing it during the telegraph costs you nothing ----------

## The reward the window exists to offer, asserted rather than assumed: a Lance
## destroyed before it commits must NOT blast. If it did, the telegraph would be
## a countdown you cannot defuse, which is a different (and worse) enemy.
func _check_the_window() -> void:
	_arena.free()
	_arena = Node3D.new()
	root.add_child(_arena)
	var dummy: Node3D = _make_player()
	_arena.add_child(dummy)
	dummy.position = PLAYER_AT
	var lance := (load("res://scenes/combat/lance.tscn") as PackedScene).instantiate() as Lance
	lance.enemy_config = load("res://resources/default_enemy_lance.tres")
	lance.ai_seed = 0
	# Right on top of the player, so a blast could not possibly be missed.
	lance.position = PLAYER_AT + Vector3(0.0, 0.0, 3.0)
	_arena.add_child(lance)
	lance.take_hit(100000.0)
	_expect(float(dummy.get(&"taken")) == 0.0,
			"a lance killed before it commits does NOT blast (took %.0f)"
			% float(dummy.get(&"taken")))
	_arena.free()
	_arena = null
	_stage = 2
	_build(true)


## Damage the stand-in player has absorbed, or 0 if it is gone.
func _player_taken() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	return float(_player.get(&"taken"))


## ---------- stage 2: the NEAR miss has to hurt ----------

## The partner to the wide-miss control. The player side-steps only 6 m at the
## moment of commitment — inside the 11 m fuse and outside the 7 m blast — so the
## run misses them by a body length and the fuse has to notice. Before the fuse
## existed this cost the player exactly nothing, which is the report this stage
## was written from.
func _watch_the_near_miss() -> void:
	if not is_instance_valid(_lance):
		_verify_the_near_miss()
		return
	_sample_warning(_lance.telegraphing())
	if _lance.velocity.length() > 12.0 and _player != null 			and is_instance_valid(_player) 			and _player.global_position.distance_to(PLAYER_AT) < 0.01:
		# Dodge, but only just.
		_player.global_position = PLAYER_AT + Vector3(6.0, 0.0, 0.0)
		_seen_moving = true
	if _seen_moving and _player_taken() > 0.0:
		_verify_the_near_miss()


func _verify_the_near_miss() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_lance.tres")
	var taken: float = _player_taken()
	_expect(taken > 0.0,
			"a 6 m side-step is INSIDE the %.0f m fuse, so the run still catches them (%.0f damage)"
			% [config.blast_fuse_radius, taken])
	# And the falloff has to be doing its job: a graze at the edge of the blast
	# must cost less than a direct hit, or the fuse just widened the kill radius.
	_expect(taken < config.bomb_damage,
			"and it GRAZES rather than landing whole — %.0f of a possible %.0f"
			% [taken, config.bomb_damage])
	_verify_the_warning_close()
	_arena.free()
	_arena = null
	# On to A.q9: the same commitment on a rail, then with the shipped steering.
	_stage = 3
	_steer_override = 0.0
	_build(true)


## ---------- A.q8: the warning, on a run that CONNECTED ----------

## THE OTHER HALF OF THE COMPARISON, and the assertion this whole feature stands
## on. Stage 0 and this stage differ in exactly one thing — 40 m of dodge against
## 6 m — so if the warning is louder here it is because the danger was closer, and
## there is no other explanation available.
##
## That comparison is the reason the check is built as two runs rather than one.
## Every single-run assertion (it opens, it rises, it stops) is passed just as
## happily by a cue driven off a TIMER, off the phase, or off a constant. Only
## running the same commitment against two different outcomes can tell the
## difference, and A.q8's whole request was for a cue that tracks danger rather
## than announcing an event.
func _verify_the_warning_close() -> void:
	if _wide_warn_peak < 0.0:
		_expect(false, "the wide-miss run recorded a warning peak to compare against")
		return
	_expect(_warn_peak > _wide_warn_peak + 0.25,
			"the warning RISES with the danger — %.2f on a 6 m pass against %.2f on a 40 m miss, same commitment"
			% [_warn_peak, _wide_warn_peak])
	# Maximum has one meaning and the fuse owns it. This ties the cue to the
	# mechanic rather than to a distance somebody picked for the sound: the run
	# that tripped the fuse is the run that reached 1.00.
	_expect(_warn_peak >= 0.99,
			"and it is at MAXIMUM on the tick the fuse fires, so full alarm means inside the envelope (%.2f)"
			% _warn_peak)


## ---------- A.q9: the run steers, and the steering is BOUNDED ----------

## THE KNOB WALKS BACK PART OF THE TYPE'S FOUNDING RULE, so the check has to hold
## both ends of the trade rather than just "the feature is on".
##
## P4.2 gives the Lance the web role *"aimed at where you are, so being somewhere
## else is the answer"*. The user asked for a correction anyway — *"maybe we can
## allow it to steer slightly toward the target to make it even more dangerous and
## interesting"* — and the honest form is a maximum course-change RATE, because a
## rate cap punishes a small dodge while leaving a real break effective. A blend
## toward the player would defeat both equally, which is a homing missile.
##
## Two runs, the shape A.q8's stage established: the SAME commitment and the SAME
## dodge, once with the knob at 0 and once with the shipped value. The only
## difference between them is the knob, so the difference in closest approach is
## what the knob bought, in metres, and nothing else can be claiming credit.
##
## Stage 3 is the rail (knob 0) and stage 4 the shipped value.
const STEER_DODGE: float = 25.0


func _watch_the_steering() -> void:
	if not is_instance_valid(_lance):
		_verify_the_steering()
		return
	var telegraphing: bool = _lance.telegraphing()
	var locked_now: bool = _was_telegraphing and not telegraphing
	_was_telegraphing = telegraphing
	if locked_now and not _seen_moving:
		_seen_moving = true
		_player.global_position = PLAYER_AT + Vector3(STEER_DODGE, 0.0, 0.0)
	if not _seen_moving:
		return
	if telegraphing:
		# It missed and began a second wind-up: the run under test is over.
		_verify_the_steering()
		return
	_closest = minf(_closest,
			_lance.global_position.distance_to(_player.global_position))


func _verify_the_steering() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_lance.tres")
	if _stage == 3:
		_rail_closest = _closest
		# THE CONTROL. At 0 the type must be exactly what it was: a body that
		# flies at the point and does not follow. It should end roughly a full
		# dodge away, which is also what makes the comparison below meaningful.
		_expect(_closest > STEER_DODGE * 0.9,
				"with steering at 0 the run is a RAIL — closest approach %.1f m against a %.0f m dodge"
				% [_closest, STEER_DODGE])
		_arena.free()
		_arena = null
		_stage = 4
		_steer_override = -1.0
		_build(true)
		return
	var ate: float = _rail_closest - _closest
	_expect(config.run_steer_deg_s > 0.0,
			"the shipped Lance steers during its run (%.1f deg/s)"
			% config.run_steer_deg_s)
	# 1. IT DOES SOMETHING. Without this the knob could be dead code and every
	#    other assertion here would still pass.
	_expect(ate > 1.0,
			"and it EATS part of the dodge — closest %.1f m against the rail's %.1f m, so %.1f m of the break was taken"
			% [_closest, _rail_closest, ate])
	# 2. IT IS STILL BOUNDED, and this is the assertion P4.2 is standing behind.
	#    A 25 m committed break has to remain a clean escape: outside the fuse,
	#    therefore outside the blast, therefore free. If this ever fails, the type
	#    has stopped being dodgeable and the knob has gone too far.
	_expect(_closest > config.blast_fuse_radius,
			"while a real %.0f m break still WORKS — %.1f m is outside the %.0f m fuse, so it costs nothing"
			% [STEER_DODGE, _closest, config.blast_fuse_radius])
	# 3. And it must not have eaten most of the dodge, which is the difference
	#    between "it corrects" and "it homes". A rate cap spends a fixed budget of
	#    turn per second; a blend would close nearly all of this.
	_expect(ate < STEER_DODGE * 0.5,
			"and it is a CORRECTION rather than a homing run — %.1f m of %.0f taken, under half"
			% [ate, STEER_DODGE])
	_arena.free()
	_arena = null
	_stage = 1
	_steer_override = -1.0
	_build(false)


## ---------- falx bug four, held for this type ----------

func _watch_without_a_player() -> void:
	if not is_instance_valid(_lance):
		_expect(false, "a lance with nobody to hit stays on the field")
		_report()
		return
	if _ticks < int(6.0 * TICK_HZ):
		return
	var drift: float = _lance.global_position.distance_to(LANCE_AT)
	_expect(drift < 20.0,
			"with no player on the field it HOLDS STATION rather than flying off the map (%.1f m in 6 s)"
			% drift)
	_report()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[lance_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[lance_check]  FAIL  %s" % message)


func _report() -> void:
	if _failures == 0:
		print("[lance_check] PASS")
	else:
		print("[lance_check] FAIL - %d check(s)" % _failures)
	quit(0 if _failures == 0 else 1)
