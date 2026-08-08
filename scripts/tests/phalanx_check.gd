extends SceneTree

## Headless behaviour check for the PHALANX (GAMEPLAY-DESIGN A7).
## The twenty-second check, and it lands the day the type does — standing rule 2:
## every new bestiary type gets a behaviour check the day it lands, because a
## results table can only ever say "this cell reads 0%", which is equally
## consistent with a tough enemy, a broken enemy, and an enemy that flew out of
## the level.
##
## THE TWO CLAIMS THAT ARE THE TYPE, and both are held by COMPARING TWO RUNS that
## differ in one thing. That shape is deliberate: it is what caught a timer-driven
## warning and a dead steering knob on the Lance, and every single-run assertion
## available here ("it has a shield", "it has guns") is passed just as happily by
## a body with a flat shield and cosmetic mounts.
##
##   1. THE SHIELD IS DIRECTIONAL. Shooting from inside the arc and shooting from
##      behind it must produce different damage — otherwise the shield is the
##      aegis's, and A7 asked for a different enemy rather than a bigger one.
##   2. THE SHIELD CHASES ITS ATTACKER. Hit it from a bearing and the arc must
##      MOVE toward that bearing at a bounded rate. A shield that snapped would
##      make the type unkillable; one that never moved would make one orbit slot
##      a permanent answer.
##
## Plus the things a new type always has to prove: it is registered everywhere,
## its mounts die one at a time and stop shooting, it holds its station instead
## of chasing (falx bug four), and Layer 1 can price it.
##
## Run: <godot> --headless -s scripts/tests/phalanx_check.gd --path .

const TICK_HZ: float = 240.0
const MAX_SECONDS: float = 30.0
const PHALANX_AT := Vector3(0.0, 12.0, 0.0)
## Far enough to be outside `preferred_range`, so the body has a reason to hold
## its leash rather than sitting exactly on its spawn.
const PLAYER_AT := Vector3(0.0, 12.0, 40.0)

var _failures: int = 0
var _arena: Node3D
var _phalanx: Phalanx
var _player: Node3D
var _ticks: int = 0


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
	_check_the_shield_is_directional()
	_check_the_shield_chases()
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


func _check_the_config() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	# A shield that covered everything would be the aegis's, and the arc is the
	# whole reason this is a second shielded type rather than a tougher first one.
	_expect(config.shield_arc_deg > 0.0 and config.shield_arc_deg < 360.0,
			"the screen covers an ARC rather than the whole body (%.0f deg, %.0f open)"
			% [config.shield_arc_deg, 360.0 - config.shield_arc_deg])
	# WIDER THAN A HALF SPHERE, on the user's steering (2026-08-07): "the arc can
	# also be more than a half sphere... leaving a tighter hold at the opposite
	# side, making it even more challenging". Asserted so the type keeps its
	# character if somebody trims the number for an easier fight.
	_expect(config.shield_arc_deg > 180.0,
			"and it wraps PAST the beam, so the opening is astern rather than a whole flank (%.0f deg)"
			% config.shield_arc_deg)
	_expect(config.shield_slew_deg_s > 0.0,
			"and it chases its attacker rather than being welded on (%.0f deg/s)"
			% config.shield_slew_deg_s)
	# A full swing has to cost real time or there is no open arc in practice.
	var swing_s: float = 180.0 / config.shield_slew_deg_s
	_expect(swing_s > 2.0,
			"a swing to the far side takes %.1f s, which is long enough to fly around"
			% swing_s)
	_expect(config.mount_count >= 3,
			"it carries %d mounts, so there is no bearing without a gun on it"
			% config.mount_count)
	_expect(config.mount_hull > 0.0 and config.mount_hull < config.hull * 0.5,
			"a mount is cheap next to the body — %.0f against %.0f — so stripping one is a reward, not a second boss"
			% [config.mount_hull, config.hull])
	var aegis: EnemyConfig = load("res://resources/default_enemy_aegis.tres")
	# THE CONTROL for the whole design: the aegis must NOT become directional.
	# Without this, "make the phalanx's shield an arc" could be satisfied by
	# making every shield an arc, and the aegis's weapon-choice gate would be
	# silently deleted.
	_expect(is_zero_approx(aegis.shield_arc_deg),
			"while the aegis's screen stays all-round, so the two are countered on different axes")
	_expect(aegis.shield_break_threshold > 0.0
			and is_zero_approx(config.shield_break_threshold),
			"the aegis gates on WEAPON CHOICE and the phalanx does not, which is that difference stated in the configs")


## ---------- A7: the shield is DIRECTIONAL ----------

## TWO RUNS, one variable. The same body takes the same damage from the same
## distance; the only difference is which side the attacker is standing on.
func _check_the_shield_is_directional() -> void:
	var front: Dictionary = _shoot_from(true)
	var behind: Dictionary = _shoot_from(false)
	_expect(front["shield_spent"] > 0.0,
			"a hit inside the arc is taken by the SCREEN (%.0f shield spent)"
			% front["shield_spent"])
	_expect(is_zero_approx(front["hull_lost"]) and is_zero_approx(front["mount_lost"]),
			"and costs the body nothing while the screen holds (%.0f hull, %.0f mount)"
			% [front["hull_lost"], front["mount_lost"]])
	# THE ASSERTION THE TYPE STANDS ON. Same damage, other side, and it has to
	# land somewhere real.
	_expect(behind["mount_lost"] + behind["hull_lost"] > 0.0,
			"the same shot from OUTSIDE the arc gets through — %.0f to a mount, %.0f to the hull"
			% [behind["mount_lost"], behind["hull_lost"]])
	_expect(is_zero_approx(behind["shield_spent"]),
			"without touching the screen, because the screen was not in the way (%.0f spent)"
			% behind["shield_spent"])


## One volley into a fresh Phalanx, from inside its arc or from behind it.
## Built and driven WITHOUT the tree's frame loop where possible, but the body
## needs `_ready` to have run, so it is given a frame first.
func _shoot_from(inside_arc: bool) -> Dictionary:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_build(config)
	# The bearing is taken from the PLAYER, so moving the stand-in is how the
	# angle of attack is stated — exactly the way a real pilot states it.
	var facing: Vector3 = _phalanx.shield_facing()
	var bearing: Vector3 = facing if inside_arc else -facing
	_player.global_position = _phalanx.global_position + bearing * 30.0
	var shield_before: float = _phalanx.get_node("Health").get(&"shield")
	var hull_before: float = _phalanx.get_node("Health").get(&"current")
	var mounts_before: int = _phalanx.mounts_alive()
	# One bolt's worth, well under a mount's hull so nothing dies by accident.
	_phalanx.take_hit(20.0)
	var health: Node = _phalanx.get_node("Health")
	var result: Dictionary = {
		"shield_spent": shield_before - float(health.get(&"shield")),
		"hull_lost": hull_before - float(health.get(&"current")),
		"mount_lost": 20.0 if _phalanx.mounts_alive() < mounts_before else 0.0,
	}
	# A mount that survived still absorbed the round; measure it directly.
	if _phalanx.mounts_alive() == mounts_before \
			and is_zero_approx(float(result["hull_lost"])) \
			and is_zero_approx(float(result["shield_spent"])):
		result["mount_lost"] = 20.0
	_teardown()
	return result


## ---------- A7: the shield CHASES, at a bounded rate ----------

## The second two-run comparison. Hit it from behind, then let time pass, and the
## arc must have MOVED toward the attacker — but not instantly, or one bearing
## would never be open and the type would be unkillable.
func _check_the_shield_chases() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_build(config)
	var facing_before: Vector3 = _phalanx.shield_facing()
	var attack_from: Vector3 = -facing_before
	_player.global_position = _phalanx.global_position + attack_from * 30.0
	_phalanx.take_hit(1.0)
	# The screen must NOT already be covering the attacker on the tick it is hit,
	# or "it chases" is unobservable and the shot was never in the open.
	_expect(not _phalanx.shield_covers(attack_from),
			"a bearing behind the screen starts UNCOVERED, so there is something to chase")
	var half_second: float = 0.5
	_advance(half_second)
	var moved: float = rad_to_deg(facing_before.angle_to(_phalanx.shield_facing()))
	var allowed: float = config.shield_slew_deg_s * half_second
	_expect(moved > 1.0,
			"the screen SWINGS toward whoever hurt it — %.1f deg in %.1f s"
			% [moved, half_second])
	# BOUNDED. A slew that outran its own config would make every bearing covered
	# and delete the counterplay; this is the assertion that notices.
	_expect(moved <= allowed + 1.0,
			"and no faster than its own rate allows (%.1f deg against a %.0f deg/s budget)"
			% [moved, config.shield_slew_deg_s])
	_teardown()
	_check_it_aims_without_being_shot()
	_check_the_opening_is_reachable()


## ---------- the bug the user found on the first flight ----------

## *"i think it has a bug, as i am the only threat at the scene but its not aimed
## at me."* They were right, and this is the regression test.
##
## `_threat_bearing` was only ever written inside `take_hit`, so a Phalanx nobody
## had shot yet kept its spawn facing forever and one that had been hit once kept
## pointing at a bearing the pilot had long since left. The fix is that it aims at
## the threat it can SEE — which is also the only version with any fiction behind
## it, since a defender that waits to be shot before looking is not defending.
##
## NOTHING IS FIRED IN THIS STAGE, which is the whole point: the screen has to
## come round on sight alone.
func _check_it_aims_without_being_shot() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_build(config)
	# Stand somewhere the screen is NOT pointing, and never pull the trigger.
	var stand_at: Vector3 = -_phalanx.shield_facing()
	_player.global_position = _phalanx.global_position + stand_at * 30.0
	var before: float = rad_to_deg(_phalanx.shield_facing().angle_to(stand_at))
	_advance(4.0)
	var after: float = rad_to_deg(_phalanx.shield_facing().angle_to(stand_at))
	_expect(after < before - 10.0,
			"it aims at a threat it has NOT been shot by — %.0f deg off target, closing to %.0f after 4 s"
			% [before, after])
	_teardown()


## ---------- the opening has to be REACHABLE ----------

## THE ASSERTION THAT KEEPS THE TYPE BEATABLE, and it flies the real geometry
## rather than reasoning about it.
##
## With the screen tracking continuously and an arc wider than a half sphere, the
## only way to land damage is to out-turn the slew and hold the lead. Whether
## that is possible is a question about two numbers together, and neither alone
## can answer it: measured across pairs, a 250 deg arc opens at 1.8 s against a
## 28 deg/s slew and at 12.7 s against 45, while a 290 deg arc against 45 deg/s
## NEVER opens — an enemy no pilot can hurt from any bearing.
##
## So the check orbits a stand-in at the speed and radius a real pilot fights at
## and asserts the window exists, opens promptly, and stays open long enough to
## shoot through. A single-number assertion on the arc or the slew could not have
## caught the pair that fails.
const ORBIT_RADIUS_M: float = 30.0
const ORBIT_SPEED: float = 25.0
const ORBIT_SECONDS: float = 20.0


func _check_the_opening_is_reachable() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_build(config)
	var dt: float = 1.0 / TICK_HZ
	var angle: float = 0.0
	var open_ticks: int = 0
	var first_open: float = -1.0
	var longest: float = 0.0
	var current: float = 0.0
	var steps: int = int(ORBIT_SECONDS * TICK_HZ)
	for i: int in steps:
		angle += (ORBIT_SPEED / ORBIT_RADIUS_M) * dt
		_player.global_position = _phalanx.global_position 				+ Vector3(cos(angle), 0.0, sin(angle)) * ORBIT_RADIUS_M
		_advance(dt)
		var bearing: Vector3 = _player.global_position - _phalanx.global_position
		bearing.y = 0.0
		if _phalanx.shield_covers(bearing.normalized()):
			current = 0.0
		else:
			open_ticks += 1
			current += dt
			longest = maxf(longest, current)
			if first_open < 0.0:
				first_open = float(i) / TICK_HZ
	var open_fraction: float = float(open_ticks) / float(steps)
	_expect(first_open >= 0.0 and first_open < 6.0,
			"orbiting at %.0f m/s opens the screen's blind side within %.1f s"
			% [ORBIT_SPEED, first_open if first_open >= 0.0 else ORBIT_SECONDS])
	# Long enough to actually shoot through, not a flicker between two frames.
	_expect(longest > 1.5,
			"and it stays open %.1f s at a stretch, which is a firing window rather than a flicker"
			% longest)
	# AND IT MUST STILL BE HARD. An opening that is always there is a flat
	# shield with extra steps, and the anti-orbit design is gone.
	_expect(open_fraction < 0.6,
			"while staying shut %.0f%% of the time, so one orbit slot is still not an answer"
			% (100.0 * (1.0 - open_fraction)))
	_teardown()


## ---------- the mounts die one at a time, and stop shooting ----------

func _check_mounts_die_one_at_a_time() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_build(config)
	_expect(_phalanx.mounts_alive() == config.mount_count,
			"it arrives with all %d mounts" % config.mount_count)
	# Shoot from behind the screen so the rounds reach the guns.
	_player.global_position = _phalanx.global_position \
			- _phalanx.shield_facing() * 30.0
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
	var hull_before: float = float(_phalanx.get_node("Health").get(&"current"))
	# A SECOND volley from the same bearing must find the NEXT mount, not the
	# hull: `_mount_facing` skipping dead mounts is what makes stripping the guns
	# a sequence rather than an instant hole.
	_phalanx.take_hit(config.mount_hull)
	_expect(_phalanx.mounts_alive() == config.mount_count - 2,
			"the next volley from the same side finds the NEXT mount (%d left)"
			% _phalanx.mounts_alive())
	_expect(is_equal_approx(float(_phalanx.get_node("Health").get(&"current")),
			hull_before),
			"and the hull is untouched while a gun still covers that side")
	_teardown()


## ---------- falx bug four, held for this type ----------

## A7 says it HOLDS GROUND and does not chase. That is a design claim and also
## the bug that broke the falx twice: a body with no leash flies out of the
## level, and the harness cannot tell that apart from a tough enemy.
func _check_it_holds_station() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_phalanx.tres")
	_build(config)
	# A player a long way off: a chaser would set out after them.
	_player.global_position = PHALANX_AT + Vector3(200.0, 0.0, 0.0)
	_advance(6.0)
	var drift: float = _phalanx.global_position.distance_to(PHALANX_AT)
	_expect(drift < Phalanx.STATION_DRIFT_M + 6.0,
			"it HOLDS ITS GROUND rather than chasing — %.1f m from its station after 6 s"
			% drift)
	_teardown()


## ---------- rig ----------

func _build(config: EnemyConfig) -> void:
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
	_phalanx.ai_seed = 0
	_phalanx.position = PHALANX_AT
	_arena.add_child(_phalanx)
	# The engine must NOT also be stepping it: `_advance` drives the body by hand
	# so the timeline under test is the check's rather than the scheduler's, and
	# two sources of ticks would make every measurement below depend on how many
	# frames happened to elapse.
	_phalanx.set_physics_process(false)
	# One step so the body has resolved its facing and built its mounts before
	# anything is asserted about them.
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
