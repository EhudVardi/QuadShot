extends SceneTree

## Layer 2 delivery benches (GAMEPLAY-DESIGN v1.23 Phase 3.5 step 3,
## BALANCE.md): the two factors of "can the shot actually land", each measured
## in the isolation that gives it meaning — plus, since v1.78, the same question
## asked in the other direction (Layer 3b, Iteration 9 / S3).
##
## AIM BENCH — agent vs STATIC target. The reference pilot flies the real
## drone against a target that cannot move, cannot shoot and cannot die, so
## hits-per-shot measures the AGENT alone: `aim_quality`, the per-agent
## delivery factor (and the axis the FCS gear ladder purchases). Pilot-
## version-dependent by definition, hence the pin in the header — and, since
## Phase 4b, FRAME-dependent too: the agent is a pilot flying an airframe, so
## these cells are keyed `<frame>:<weapon>`. That is the whole Layer 2 cost of
## the P3.4 frame axis; nothing else in this file grew.
##
## THESE CELLS FLY THE REPO'S NUMBERS. `Frames.build` turns off user:// config
## loading, because until Phase 4b the benches inherited whatever the human had
## tuned into their own override and every committed factor was a measurement of
## one machine. Turning it off moved `aim: kestrel/blaster` from 0.17 to 0.05 —
## the same pilot and the same weapon, flying the aircraft as it is committed
## rather than as it is tuned.
##
## EVASION BENCH — fixed PERFECT shooter vs the moving enemy flying its real
## AI. The shooter is the real drone frozen in place, its gun re-laid every
## tick onto the exact ballistic solution (lead + gravity drop) and firing at
## full cadence, so hits-per-shot measures the TARGET alone: `evasion`, the
## per-target delivery factor. A static-target control cell proves the
## bench's own solver first — if the perfect shooter cannot hit a stationary
## raider, the rig is broken and the run fails, before any mover is blamed
## for "evading".
##
## SPLASH — a THIRD delivery factor, and the flak column is why it exists. Aim
## belongs to the agent and evasion to the target, but "how many bodies does one
## arriving burst cover" belongs to neither: it is the weapon's geometry meeting
## the target's dispersion. So the flak cells report two numbers from one
## measurement — `bursts_connected / shots_fired` (arrival, comparable to every
## other weapon's rate) and `bodies_struck / bursts_connected` (splash) — and
## the prediction layer divides the pack bill by the second. For a weapon that
## damages one body per connect, splash is 1.0 and nothing changes.
##
## PLAYER-EVASION BENCH (Layer 3b, `kind: survive`) — the evasion bench with
## the arrow reversed: a fixed perfect-aim THREAT firing at the reference pilot
## while it flies the aim bench's own task. Output: hits-taken per shot-fired-at-
## you, per THREAT x FRAME. Frame-keyed, unlike its enemy-side twin, because
## nothing freezes the player — the frame is what the pilot is dodging in, and
## that is the axis the Atlas has never been legible on (S1).
##
## THE THREAT HAS NO BODY, and that is the isolation. It is a bare position that
## emits the threat type's real rounds (its damage, cadence, muzzle speed and
## lifetime) on an exact firing solution — so the pilot cannot acquire it, cannot
## shoot it, and cannot orbit it. The cell measures the pilot dodging fire and
## nothing else. A `frozen: true` control parks the drone in front of that
## shooter first: if a perfect solution cannot hit a stationary player, the rig
## is broken before any airframe is credited with "evading".
##
## Its second output is free and worth as much as the first: the pilot is flying
## the AIM task while it dodges, so the same cell reports hits-per-shot on the
## static target UNDER FIRE. Against the undisturbed aim cell that is the price
## of the jink, measured directly instead of inferred from duels (v1.77).
##
## OUT OF SCOPE, and newly conspicuous: the D2 damage model. `apply_hit_to_motors`
## is wired in main.gd alone, so no bench in this folder has ever flown a wounded
## quad — which cost nothing while the player was never shot at, and is a stated
## limit now that it is. Every Layer 3b number describes an undamaged airframe
## dodging; a frame whose motors fray under fire would do worse in the game than
## it reads here.
##
## CONTACT BENCH (`kind: contact`) — the gnat is not a cadence and cannot be
## measured as one. A body that arrives always stings (`_resolve_stings` spends
## it on contact), so there is no connect fraction to report; the delivery term
## is the arrival RATE. Layer 1's `incoming()` refuses to invent that number from
## a config and names a bench for it — this is that bench. The pilot's trigger is
## LOCKED in these cells: let the gun director shoot the cloud and the rig stops
## measuring arrival and starts refighting Flak x Gnats.
##
## What these numbers are NOT (BALANCE.md): win predictions. They multiply
## with Layer 1 lethality into the predicted product that the duel harness
## VALIDATES; divergence there names an un-modeled factor.
##
## Run:   <godot> --headless -s scripts/tests/delivery_bench.gd --path .
## WATCH: <godot> -s scripts/tests/delivery_bench.gd --path .   (tools/watch_delivery)
##
## Drop --headless and the cells render from the rig's own FPV camera. Worth
## doing before believing any factor: an aim cell shows you WHY 0.14 (is the
## pilot missing, or is it fighting the aircraft?), and an evasion cell shows
## you what the target is actually doing to break the solution.

const ALTITUDE: float = 14.0
const RANGE_M: float = 40.0
## Gnats hold station (pursuit zeroed) mid-envelope instead of closing to
## sting range — the boil is the dodge being measured, not the closure.
const GNAT_RANGE_M: float = 30.0
## Aegis crossing half-width: +/- this on x at RANGE_M, inside missile lock
## range at the edges (sqrt(30^2 + 40^2) = 50 < 60).
const AEGIS_CROSS_M: float = 30.0
## The aim bench mirrors the matchup harness's director setting — the human's
## own play setting, per the 2026-07-18 decision recorded there.
const DIRECTOR_MISS_M: float = 1.2
## Effectively-infinite hull for bodies that must survive the measurement.
const IMMORTAL_HULL: float = 1.0e9
## Routed targets (the aegis) TELEPORT back to their route start when the
## loop restarts, and a shot in the air at that moment is orphaned — a miss
## the target never earned. The shooter holds fire when the target is within
## this many seconds of its route end, sized to each weapon's engagement time.
const ROUTE_HOLD_BOLT_S: float = 1.0
const ROUTE_HOLD_MISSILE_S: float = 3.0
## Control-cell floor: below this the perfect shooter's own solver is broken.
const CONTROL_MIN_RATE: float = 0.9
## The Layer 3b threat STATION-KEEPS: it holds a stated range and bearing off the
## player every tick rather than sitting at an arena coordinate.
##
## MEASURED THE OTHER WAY FIRST, and the discarded attempt is the reason this is
## a constant. Parking the threat at a fixed point ~30 m from where the pilot
## works produced connect rates of 0.03-0.08 — which compose into a Kestrel
## surviving a raider for over four minutes, against duels that show it losing
## a fifth of its hull in ten seconds. That gap is not an un-modeled factor, it
## is a bench measuring the wrong thing: RANGE dominates everything else here
## (a linear lead against a quad under aim-driven lateral acceleration misses by
## roughly the flight time squared), so a rig that lets arena geometry pick the
## range is reporting the arena.
##
## Fixing the range makes the type axis mean what it should: two threat cells now
## differ by their WEAPON — damage, cadence, muzzle speed — and by nothing else.
## Where the type would choose to fight from is real, but it is a BEHAVIOR
## property and it belongs to the duel, not to a per-type delivery factor.
##
## 18 m is the roster's ranged standoff (the raider's own `preferred_range`) and
## sits beside this pilot's 16 m orbit, so the number describes the range the
## game's fights actually happen at.
const THREAT_RANGE_M: float = 18.0
## Abeam, slightly high and slightly behind: the incoming line and the aiming
## line must not be the same line, or one dodge serves both jobs and every frame
## reads better than it is.
const THREAT_BEARING: Vector3 = Vector3(0.88, 0.22, 0.42)
## The contact cloud spawns on the OPPOSITE flank, far enough out to have a real
## approach: a pack already on top of the pilot would report a spend rate with
## the transit — the thing a frame's speed actually changes — edited out.
const CONTACT_SPAWN: Vector3 = Vector3(-32.0, ALTITUDE, -30.0)
## Enemy bolts fly flat (both `enemy_drone._try_fire` and `turret._fire` pass
## gravity_scale 0.0), so the threat's solution carries no drop term. Named
## rather than inlined because if the bestiary ever gains a lobbed weapon, this
## is the line that has to stop being a constant.
const THREAT_GRAVITY: float = 0.0
## Contact cells need the cloud to arrive AND spend itself inside the window;
## below ~2 stings there is no interval to measure a rate from.
const CONTACT_MIN_STINGS: int = 3

const RAIDER_SCENE: String = "res://scenes/combat/enemy_drone.tscn"
const SWARM_SCENE: String = "res://scenes/combat/gnat_swarm.tscn"
const AEGIS_SCENE: String = "res://scenes/combat/aegis.tscn"
const TURRET_SCENE: String = "res://scenes/combat/turret.tscn"
const FALX_SCENE: String = "res://scenes/combat/falx.tscn"

## kind: aim (pilot flies) | evasion (frozen perfect shooter).
## target: static | raider | gnats | aegis. seconds: firing window.
## frame: which airframe flies the cell — AIM cells only. Evasion cells leave it
## unset because the shooter is frozen and its gun is laid by this bench, so the
## airframe cannot influence the shot (see BalancePrediction.aim_key).
const CELLS: Array[Dictionary] = [
	{"name": "aim: kestrel/blaster", "kind": "aim", "weapon": "blaster",
			"frame": Frames.KESTREL, "target": "static", "seconds": 20.0},
	{"name": "aim: kestrel/missile", "kind": "aim", "weapon": "missile",
			"frame": Frames.KESTREL, "target": "static", "seconds": 45.0},
	{"name": "evasion: blaster x static", "kind": "evasion",
			"weapon": "blaster", "target": "static", "seconds": 20.0,
			"control": true},
	{"name": "evasion: blaster x raider", "kind": "evasion",
			"weapon": "blaster", "target": "raider", "seconds": 20.0},
	# A turret cannot dodge at all, so this cell is both a real factor and a
	# second control: anything but ~1.0 means the bench, not the turret. That
	# claim went unenforced at first — the comment said "control" while the
	# flag was missing, so a regression dropping this to 0.5 would have passed
	# in silence. A control that does not guard is just a comment.
	{"name": "evasion: blaster x turret", "kind": "evasion",
			"weapon": "blaster", "target": "turret", "seconds": 20.0,
			"control": true},
	{"name": "evasion: blaster x gnats", "kind": "evasion",
			"weapon": "blaster", "target": "gnats", "seconds": 20.0},
	{"name": "evasion: blaster x aegis", "kind": "evasion",
			"weapon": "blaster", "target": "aegis", "seconds": 20.0},
	{"name": "evasion: missile x static", "kind": "evasion",
			"weapon": "missile", "target": "static", "seconds": 45.0,
			"control": true},
	{"name": "evasion: missile x raider", "kind": "evasion",
			"weapon": "missile", "target": "raider", "seconds": 45.0},
	{"name": "evasion: missile x gnats", "kind": "evasion",
			"weapon": "missile", "target": "gnats", "seconds": 45.0},
	{"name": "evasion: missile x aegis", "kind": "evasion",
			"weapon": "missile", "target": "aegis", "seconds": 45.0},
	# 40 s, not the blaster's 20. The pod's cycle is 4x slower AND its trigger is
	# conditional (no director), so a 20 s window yielded only ~36 shots, and the
	# cell measured 1.00 in one run and 0.92 in the next on nothing but
	# cross-process float variance moving three shells across the 6-degree cone
	# edge.
	#
	# The longer window HALVED that spread but did not remove it: three runs at
	# 40 s read 0.99 / 0.99 / 0.94. More time is not more independent samples
	# here — the pilot flies one quasi-periodic trajectory, so a longer window
	# mostly re-measures the same oscillation. Left as measured rather than
	# chased: the residual spread moves no band (this cell divides into
	# single-digit shot counts), and it sits inside the contract the harness
	# header already states — AI-level deterministic, not bit-exact, read
	# aggregate movement rather than single reps. Recorded so the next reader
	# does not mistake a 0.94/0.99 difference between runs for a balance change.
	#
	# The 0.99/0.99/0.94 spread above was measured on the human's tuned Kestrel,
	# before the benches were pinned to repo defaults. On the committed config it
	# reads 1.00 at a duty of 0.28 — fewer shells, all of them fused. Whether the
	# wobble is gone or merely hiding behind a smaller sample is not yet known;
	# re-check it before quoting this cell to a decimal place.
	{"name": "aim: kestrel/flak", "kind": "aim", "weapon": "flak",
			"frame": Frames.KESTREL, "target": "static", "seconds": 40.0},
	{"name": "evasion: flak x static", "kind": "evasion",
			"weapon": "flak", "target": "static", "seconds": 20.0,
			"control": true},
	{"name": "evasion: flak x raider", "kind": "evasion",
			"weapon": "flak", "target": "raider", "seconds": 20.0},
	{"name": "evasion: flak x turret", "kind": "evasion",
			"weapon": "flak", "target": "turret", "seconds": 20.0,
			"control": true},
	# THE CELL THE WHOLE COLUMN EXISTS FOR (P4.3 flak x gnat = `++`). The
	# blaster reads 0.12 here; if flak does not read dramatically better, the
	# gnat row has no answer and the paper band is a promise nothing keeps.
	{"name": "evasion: flak x gnats", "kind": "evasion",
			"weapon": "flak", "target": "gnats", "seconds": 20.0},
	{"name": "evasion: flak x aegis", "kind": "evasion",
			"weapon": "flak", "target": "aegis", "seconds": 20.0},
	# SPLASH vs a raider GROUP (v1.33). The flak column's splash was only ever
	# measured against the gnat cloud (3.42); raiders orbit far looser, so the
	# pack-bill divisor for the row the human actually praised ("really helps
	# destroy groups of raiders", v1.29) was an unmeasured 1.0. splash_only:
	# the single-raider cell above stays the evasion authority — this cell
	# exists for the one number only a group can produce, and writing its
	# arrival rate over the single cell's would conflate two different
	# measurements under one key.
	{"name": "splash: flak x raiders", "kind": "evasion",
			"weapon": "flak", "target": "raiderpack", "seconds": 20.0,
			"splash_only": true},
	# --- The Atlas's aim cells (Phase 4b, P3.4's frame axis). Three cells, not a
	# second matrix: the frame re-keys aim and touches nothing else, so this is
	# the ENTIRE Layer 2 cost of a new frame. Same windows as the Kestrel's, or
	# the two frames would be measured on different rulers — which is the mistake
	# the duty-cycle line exists to warn about, one axis over.
	{"name": "aim: atlas/blaster", "kind": "aim", "weapon": "blaster",
			"frame": Frames.ATLAS, "target": "static", "seconds": 20.0},
	{"name": "aim: atlas/missile", "kind": "aim", "weapon": "missile",
			"frame": Frames.ATLAS, "target": "static", "seconds": 45.0},
	{"name": "aim: atlas/flak", "kind": "aim", "weapon": "flak",
			"frame": Frames.ATLAS, "target": "static", "seconds": 40.0},
	# --- THE FALX's evasion row (M6a step 5, v1.80). The bestiary's first
	# non-orbiting flyer, so this is the first evasion cell measured against a
	# body that spends most of its life either committed to a straight line or
	# climbing away in one. Expect it to read HIGH (easy to hit per shot fired)
	# for exactly that reason — and expect the duels to disagree, because a
	# frozen shooter never has to solve the falx's real problem, which is that
	# it is only in your firing arc for about a second at a time. That gap is
	# the instrument working: `evasion` measures whether a shot connects, not
	# whether you got to take it.
	{"name": "evasion: blaster x falx", "kind": "evasion", "weapon": "blaster",
			"target": "falx", "seconds": 25.0},
	{"name": "evasion: missile x falx", "kind": "evasion", "weapon": "missile",
			"target": "falx", "seconds": 45.0},
	{"name": "evasion: flak x falx", "kind": "evasion", "weapon": "flak",
			"target": "falx", "seconds": 25.0},
	# --- LAYER 3b: the player as a target (Iteration 9 / S3). Six cells: one
	# control per frame, then each frame against each RANGED threat in the
	# roster. The aegis is absent on purpose and the absence is a measurement —
	# Layer 3a reports it `none` (no weapon at all), so a cell would fire nothing
	# and report a rate over zero shots. The gnat is absent for the opposite
	# reason: it has a weapon but no cadence, so it gets the contact cells below.
	#
	# THE CONTROL COMES FIRST in each frame's block, deliberately: it is the cell
	# that proves the threat solver before any airframe is credited with dodging
	# it, and a control printed after the thing it guards is a control nobody
	# reads in time.
	# EVERY CELL FORCES THE JINK STATE, and that is the difference between a
	# factor and a coin toss. The shipped gate is "I have been hit recently",
	# which is the right rule for a pilot and a ruinous one for a bench: what is
	# being measured (do rounds connect) decides the behaviour (am I jinking), so
	# an un-forced cell is a feedback loop. Measured on this rig, one unrelated
	# change between two runs: `kestrel x raider` settled at 25 hits / 0.87 duty
	# once and 4 hits / 0.23 duty the next — a 6x swing — while
	# `kestrel x turret` reproduced to the integer. Two of four cells moved.
	#
	# So each pair is measured TWICE, at both extremes, and neither number is a
	# blend: `[jink]` is the factor the model composes with (a pilot being shot at
	# has tripped the gate), `[steady]` is the datum it is worth against. Their
	# DIFFERENCE is what the jink actually buys — the question S3 asked, which the
	# gated cell could only answer by accident.
	{"name": "evade: kestrel x static", "kind": "survive", "threat": "raider",
			"frame": Frames.KESTREL, "weapon": "blaster", "target": "static",
			"seconds": 10.0, "frozen": true, "control": true},
	{"name": "evade: kestrel x raider [jink]", "kind": "survive",
			"threat": "raider", "frame": Frames.KESTREL, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "always"},
	{"name": "evade: kestrel x raider [steady]", "kind": "survive",
			"threat": "raider", "frame": Frames.KESTREL, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "never"},
	{"name": "evade: kestrel x turret [jink]", "kind": "survive",
			"threat": "turret", "frame": Frames.KESTREL, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "always"},
	{"name": "evade: kestrel x turret [steady]", "kind": "survive",
			"threat": "turret", "frame": Frames.KESTREL, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "never"},
	{"name": "evade: atlas x static", "kind": "survive", "threat": "raider",
			"frame": Frames.ATLAS, "weapon": "blaster", "target": "static",
			"seconds": 10.0, "frozen": true, "control": true},
	{"name": "evade: atlas x raider [jink]", "kind": "survive",
			"threat": "raider", "frame": Frames.ATLAS, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "always"},
	{"name": "evade: atlas x raider [steady]", "kind": "survive",
			"threat": "raider", "frame": Frames.ATLAS, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "never"},
	{"name": "evade: atlas x turret [jink]", "kind": "survive",
			"threat": "turret", "frame": Frames.ATLAS, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "always"},
	{"name": "evade: atlas x turret [steady]", "kind": "survive",
			"threat": "turret", "frame": Frames.ATLAS, "weapon": "blaster",
			"target": "static", "seconds": 25.0, "jink": "never"},
	# --- The CONTACT mode's delivery term (the promise Layer 3a's `incoming`
	# makes in code: "the arrival rate is a DELIVERY property, measured by a
	# bench, never read from a config"). 45 s because transit turned out to be
	# the long pole and to vary hugely by frame — a first pass measured 18.5 s of
	# chase before the Kestrel's first sting against 5.4 s for the Atlas, which is
	# the frame's speed showing up honestly but leaves a 30 s window with almost
	# no measurement in it.
	{"name": "contact: kestrel x gnats", "kind": "contact", "threat": "gnat",
			"frame": Frames.KESTREL, "weapon": "blaster", "target": "static",
			"seconds": 45.0, "jink": "always"},
	{"name": "contact: atlas x gnats", "kind": "contact", "threat": "gnat",
			"frame": Frames.ATLAS, "weapon": "blaster", "target": "static",
			"seconds": 45.0, "jink": "always"},
]

## Every roster config whose numbers can move a measured delivery factor —
## the stamp's input set. A new bestiary type belongs here the day it lands,
## or its stats can drift without invalidating the factors measured under them.
const ENEMIES_FOR_STAMP: Array[String] = [
	"res://resources/default_enemy_raider.tres",
	"res://resources/default_enemy_turret.tres",
	"res://resources/default_enemy_gnat.tres",
	"res://resources/default_enemy_aegis.tres",
	"res://resources/default_enemy_falx.tres",
]

## Bench target name -> EnemyConfig.type_id, so the artifact is keyed by the
## roster's own vocabulary rather than by this file's cell names. `static` is
## the bench's own control body, not a roster type, and is written to its own
## section instead of the evasion table.
const TYPE_IDS: Dictionary = {
	"raider": "raider", "turret": "turret", "gnats": "gnat", "aegis": "aegis",
	"raiderpack": "raider", "falx": "falx",
}

enum { BUILD, FIRE, GRACE, RECORD }

## The cells this run will actually fly — normally all of CELLS, but a WATCH
## filter can narrow it (see `_select_cells`).
var _cells: Array[Dictionary] = []
## True when the filter narrowed the list, which makes the run a LOOK rather
## than a MEASUREMENT (see `_write_factors`).
var _filtered: bool = false

var _pps: float
var _combat: CombatConfig
var _phase: int = BUILD
var _cell_i: int = 0
var _results: Array[Dictionary] = []
var _failures: PackedStringArray = []

# Live cell.
var _arena: Node3D
var _drone: FlightController
var _weapon: Weapon
var _missile: MissileSystem
var _flak: FlakPod
var _pilot: ReferencePilot
var _target: Node
var _enemy_config: EnemyConfig
var _connects: int = 0
var _ticks: int = 0
var _fire_ticks: int = 0
var _grace_ticks: int = 0
var _swarm_spawns: int = 0

# Layer 3b live cell: the bodiless threat shooting AT the pilot, and what it and
# the pilot did to each other.
var _pool: ProjectilePool
var _threat_config: EnemyConfig
var _threat_position: Vector3
var _threat_cooldown: float = 0.0
var _threat_shots: int = 0
## Rounds that reached the player (its own Health.struck) — the Layer 3b numerator
## and, in a contact cell, the sting count.
var _taken: int = 0
## Ticks the pilot spent evading, so the cell reports the DUTY of the evasion
## rather than implying it jinked throughout (the jink is hit-gated, so it cannot
## have been on before the first round landed).
var _jink_ticks: int = 0
## Contact timing: seconds to the first sting, and to the last.
var _first_sting_s: float = -1.0
var _last_sting_s: float = -1.0
## Bodies the threat's rounds pass straight through (see _threat_exclude).
var _threat_exclude_rids: Array[RID] = []


## Narrow the run to cells whose name contains a substring passed after `--`:
##
##   <godot> -s scripts/tests/delivery_bench.gd --path . -- evade
##
## THE POINT IS WATCHING. A full run is ~30 cells and the interesting ones are
## last, so "drop --headless and look at it" cost a quarter of an hour of staring
## before the cell you wanted appeared — which in practice means nobody looks.
## This project's founding tenet is that some things are only visible to eyes
## (BenchView's header says so); a filter is what makes that affordable.
##
## A FILTERED RUN NEVER WRITES THE ARTIFACT. A partial measurement overwriting
## the committed factor table would delete every cell it did not run, and the
## file gives no hint that it happened. Looking must not be able to damage the
## ruler.
func _select_cells() -> void:
	var filter: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.strip_edges() != "":
			filter = argument.strip_edges().to_lower()
			break
	for cell: Dictionary in CELLS:
		if filter == "" or String(cell["name"]).to_lower().contains(filter):
			_cells.append(cell)
	_filtered = _cells.size() != CELLS.size()
	if _filtered:
		print("[delivery] FILTERED to %d of %d cells matching '%s' — this run is a LOOK, not a measurement; %s will NOT be written."
				% [_cells.size(), CELLS.size(), filter,
				BalancePrediction.FACTORS_PATH])
	if _cells.is_empty():
		print("[delivery] FAIL: filter '%s' matched no cells." % filter)
		quit(1)


func _initialize() -> void:
	_select_cells()
	_pps = float(Engine.physics_ticks_per_second)
	_combat = load("res://resources/default_combat_config.tres") as CombatConfig
	print("[delivery] %d cells  (pilot v%d — aim and Layer 3b cells depend on it, evasion cells do not)"
			% [_cells.size(), ReferencePilot.PILOT_VERSION])
	BenchView.setup("delivery")
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	match _phase:
		BUILD:
			_build_cell()
			_phase = FIRE
		FIRE:
			_drive()
			_ticks += 1
			if _ticks >= _fire_ticks:
				_cease_fire()
				_phase = GRACE
		GRACE:
			# Shots already in the air still resolve; the pilot keeps flying
			# (a crashed rig would eat its own in-flight bolts' geometry), the
			# perfect shooter keeps tracking, but nobody pulls a trigger.
			_drive()
			# _drive() runs the PILOT on aim cells, and the pilot re-arms
			# `missile.fire_override` every tick — so ceasing fire once at the
			# start of GRACE does not hold. Late launches then cannot possibly
			# resolve inside the window and book as pure misses, biasing
			# aim:missile DOWN. Invisible today only because that cell reads
			# 1.00; it would quietly tax any harder aim-missile target.
			_cease_fire()
			_ticks += 1
			if _ticks >= _fire_ticks + _grace_ticks:
				_score_cell()
				_phase = RECORD
		RECORD:
			_teardown()
			_advance()


func _build_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	_arena = Node3D.new()
	root.add_child(_arena)
	BenchView.build_scenery(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)

	# Evasion cells freeze the shooter, so the airframe cannot reach the result;
	# they fly the Kestrel to have something concrete to freeze.
	_drone = Frames.build(String(cell.get("frame", Frames.KESTREL)))
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALTITUDE, 0.0)
	_drone.arm()
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod

	var kind: String = cell["kind"]
	var weapon_id: String = cell["weapon"]
	var is_missile: bool = weapon_id == "missile"
	if kind != "evasion":
		_drone.prime_motors(_drone.hover_throttle())
		# The gun director belongs to the CHIP GUN cell only. The missile has
		# its own launch logic and the flak pod has none by design, so arming it
		# anywhere else would put a second weapon in the cell (v1.25's lesson).
		_weapon.combat_config.fire_assist_miss_m = \
				DIRECTOR_MISS_M if weapon_id == "blaster" else 0.0
		_pilot = ReferencePilot.new()
		_pilot.drone = _drone
		_pilot.weapon = _weapon
		_pilot.missile = _missile
		_pilot.flak = _flak
		_pilot.weapon_id = weapon_id
		_pilot.cruise_altitude = ALTITUDE
		if is_missile:
			_missile.fire_override = true
		if kind != "aim":
			_build_threat(cell)
	else:
		# The fixed shooter: frozen in space, immortal (a raider shoots back
		# and gnats would otherwise win the bench by attrition), trigger held
		# down — the bench itself lays the gun each tick in _drive().
		_drone.freeze = true
		var drone_health: Health = _drone.get_node("Health") as Health
		drone_health.max_health = IMMORTAL_HULL
		drone_health.revive()
		_weapon.combat_config.fire_assist_miss_m = 0.0
		match weapon_id:
			"missile":
				_missile.fire_override = true
			"flak":
				_flak.fire_override = true
			_:
				_weapon.fire_override = true

	_target = _build_target(cell["target"])
	if _pilot != null:
		_pilot.target = _target as Node3D
	BenchView.follow(_drone)
	if BenchView.watching():
		print("[delivery] --- %s (%ds window) ---"
				% [cell["name"], int(float(cell["seconds"]))])
	_fire_ticks = int(float(cell["seconds"]) * _pps)
	# Let what is already flying land before scoring, so the last launch of
	# the window is not booked as a miss it never had time to disprove.
	var grace_s: float = _combat.projectile_lifetime
	match weapon_id:
		"missile":
			grace_s = _combat.missile_lifetime
		"flak":
			grace_s = _combat.flak_shell_lifetime
	_grace_ticks = int(grace_s * _pps)
	_ticks = 0
	_connects = 0
	_taken = 0
	_threat_shots = 0
	_threat_cooldown = 0.0
	_jink_ticks = 0
	_first_sting_s = -1.0
	_last_sting_s = -1.0
	_threat_exclude_rids = []


## The Layer 3b threat: a bodiless emitter of one enemy type's real rounds, and
## the player made immortal so the cell measures a RATE instead of a death.
##
## Immortality is the same choice every evasion target already gets, pointed the
## other way — and it is load-bearing rather than cosmetic. A Kestrel eats a
## perfect raider's 12 dps in 8 s, so a 25 s window would end with a corpse and a
## connect rate computed over whichever fraction of the window the pilot happened
## to survive. Frames with different hulls would then be measured over different
## windows, which is exactly the confound the frame axis exists to avoid.
##
## What immortality does NOT switch off is the jink: PILOT_VERSION 4 gates on
## hull DROPPING, not on hull being low, so a pilot with a billion hit points
## still notices the first round that lands and starts evading. That is why
## `armor` had to join the config stamp — a threat whose damage sits at or under
## the frame's armor produces no drop, hence no jink, hence a different
## measurement from a config edit the stamp used to be blind to.
func _build_threat(cell: Dictionary) -> void:
	_threat_config = load("res://resources/default_enemy_%s.tres"
			% String(cell["threat"])) as EnemyConfig
	_threat_position = _threat_station()
	var drone_health: Health = _drone.get_node("Health") as Health
	drone_health.max_health = IMMORTAL_HULL
	drone_health.revive()
	drone_health.struck.connect(_on_player_struck)
	if bool(cell.get("frozen", false)):
		# The control: a parked player. No pilot at all, rather than a pilot told
		# not to jink — a brain that is present but restrained is one flag away
		# from silently flying the cell it was meant to be the datum for.
		_drone.freeze = true
		_pilot = null
		_weapon.combat_config.fire_assist_miss_m = 0.0
		return
	# Break the feedback loop: the cell states the flight mode instead of letting
	# the incoming fire decide it (see ReferencePilot.Jink).
	match String(cell.get("jink", "")):
		"always":
			_pilot.jink_mode = ReferencePilot.Jink.ALWAYS
		"never":
			_pilot.jink_mode = ReferencePilot.Jink.NEVER
	if cell["kind"] == "contact":
		# The trigger is locked, not merely un-aimed. A gnat that drifts through
		# the gun director's arc would be shot down, and a cloud the pilot is
		# thinning is not a cloud whose arrival rate you are measuring.
		_weapon.combat_config.fire_assist_miss_m = 0.0
		_pilot.use_director = false
		_pilot.fire_range = 0.0
		var swarm: Node3D = (load(SWARM_SCENE) as PackedScene).instantiate() \
				as Node3D
		swarm.set(&"enemy_config", _threat_config)
		swarm.set(&"ai_seed", 0)
		swarm.position = CONTACT_SPAWN
		_arena.add_child(swarm)


## Every round that reached the player. In a ranged cell this is the Layer 3b
## numerator; in a contact cell it is a sting, and the two timestamps below are
## what turn a count into the arrival rate Layer 3a asks for.
func _on_player_struck(_amount: float) -> void:
	_taken += 1
	# Timestamps run through GRACE too — `_ticks` is monotonic across both
	# phases, and a cloud still spending itself when the window closes is
	# arriving, not missing.
	var now: float = float(_ticks) / _pps
	if _first_sting_s < 0.0:
		_first_sting_s = now
	_last_sting_s = now


## Build the cell's target. All single-body targets are immortal so one rig
## measures a rate instead of a kill; gnat bodies keep their real hull (one
## connect is one kill there, and the pack respawns when cleared — counting
## dead gnats IS counting connects, no surgery needed).
func _build_target(type: String) -> Node:
	match type:
		"static":
			_enemy_config = _immobilized_raider_config()
			return _spawn_raider(Vector3(0.0, ALTITUDE, -RANGE_M))
		"raider":
			_enemy_config = (load("res://resources/default_enemy_raider.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			return _spawn_raider(Vector3(0.0, ALTITUDE, -RANGE_M))
		"gnats":
			_enemy_config = (load("res://resources/default_enemy_gnat.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.swarm_pursuit_gain = 0.0
			_swarm_spawns = 0
			return _spawn_swarm()
		"turret":
			_enemy_config = (load("res://resources/default_enemy_turret.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			var turret: Node3D = (load(TURRET_SCENE) as PackedScene).instantiate() \
					as Node3D
			turret.set(&"enemy_config", _enemy_config)
			# Held at the shooter's altitude rather than on a floor the bench
			# does not build: what is measured is that it cannot dodge, and
			# height has no bearing on that.
			turret.position = Vector3(0.0, ALTITUDE, -RANGE_M)
			_arena.add_child(turret)
			_count_health_connects(turret.get_node("Health") as Health)
			return turret
		"falx":
			# Immortal like every other single-body evasion target, so the cell
			# measures a RATE rather than a kill. Seeded 0 for determinism; the
			# falx's only RNG is its setup-arc side and its aim jitter.
			_enemy_config = (load("res://resources/default_enemy_falx.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			var falx: Node3D = (load(FALX_SCENE) as PackedScene).instantiate() \
					as Node3D
			falx.set(&"enemy_config", _enemy_config)
			falx.set(&"ai_seed", 0)
			# Started out at its own setup distance rather than at RANGE_M: a
			# boom-and-zoom type spawned inside its break-off range would begin
			# mid-recovery and the cell would measure the wrong phase.
			falx.position = Vector3(0.0, ALTITUDE + 10.0, -70.0)
			_arena.add_child(falx)
			_count_health_connects(falx.get_node("Health") as Health)
			return falx
		"raiderpack":
			# The group the splash cell needs: three immortal raiders flying
			# their real AI at the frozen shooter. They orbit at their own
			# preferred_range, so splash is measured at the range raiders
			# actually fight, not at a staged distance.
			_enemy_config = (load("res://resources/default_enemy_raider.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			var pack: RaiderPack = (load("res://scenes/combat/raider_pack.tscn")
					as PackedScene).instantiate() as RaiderPack
			pack.enemy_config = _enemy_config
			pack.ai_seed = 0
			pack.position = Vector3(0.0, ALTITUDE, -RANGE_M)
			_arena.add_child(pack)
			for body: Node3D in pack.bodies:
				_count_health_connects(body.get_node("Health") as Health)
			return pack
		"aegis":
			_enemy_config = (load("res://resources/default_enemy_aegis.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			var aegis: Node3D = (load(AEGIS_SCENE) as PackedScene).instantiate() \
					as Node3D
			aegis.set(&"enemy_config", _enemy_config)
			aegis.set(&"loop_route", true)
			aegis.position = Vector3(-AEGIS_CROSS_M, ALTITUDE, -RANGE_M)
			aegis.set(&"route_end",
					Vector3(AEGIS_CROSS_M, ALTITUDE, -RANGE_M))
			_arena.add_child(aegis)
			_count_health_connects(aegis.get_node("Health") as Health)
			return aegis
	push_error("unknown target type " + type)
	return null


## A raider that cannot move, see, or die: the static control body, with the
## real raider's hitbox — the whole reason it is this scene and not a box.
func _immobilized_raider_config() -> EnemyConfig:
	var config: EnemyConfig = (load("res://resources/default_enemy_raider.tres")
			as EnemyConfig).duplicate() as EnemyConfig
	config.hull = IMMORTAL_HULL
	config.speed = 0.0
	config.accel = 0.0
	config.sight_range = 0.0
	return config


func _spawn_raider(at: Vector3) -> Node:
	var raider: Node3D = (load(RAIDER_SCENE) as PackedScene).instantiate() as Node3D
	raider.set(&"enemy_config", _enemy_config)
	raider.set(&"ai_seed", 0)
	raider.position = at
	_arena.add_child(raider)
	_count_health_connects(raider.get_node("Health") as Health)
	return raider


func _spawn_swarm() -> Node:
	var swarm: Node3D = (load(SWARM_SCENE) as PackedScene).instantiate() as Node3D
	swarm.set(&"enemy_config", _enemy_config)
	swarm.set(&"ai_seed", _swarm_spawns)
	_swarm_spawns += 1
	swarm.position = Vector3(0.0, ALTITUDE, -GNAT_RANGE_M)
	_arena.add_child(swarm)
	# One scored body = one connect (25 dmg vs 6 hull: every hit kills).
	swarm.connect(&"destroyed", func(_points: float) -> void: _connects += 1)
	# Cleared mid-window: hand the shooter a fresh pack to keep measuring.
	swarm.connect(&"cleared", func() -> void:
			if _phase == FIRE:
				_target = _spawn_swarm())
	return swarm


func _count_health_connects(health: Health) -> void:
	# A connect is a shot that ARRIVED, whatever happened next — absorbed,
	# shield-breaking, or wounding. Evasion is about arriving; lethality
	# (Layer 1) owns the rest. `struck` is the one signal that fires exactly
	# once per arrival.
	health.struck.connect(func(_amount: float) -> void: _connects += 1)


func _drive() -> void:
	var kind: String = _cells[_cell_i]["kind"]
	if kind != "evasion":
		if _pilot != null:
			_pilot.update(1.0 / _pps)
			if _pilot.jinking():
				_jink_ticks += 1
		# The threat's trigger is released at the end of FIRE, exactly like the
		# player-side triggers, and GRACE exists to let its last rounds arrive:
		# a shot fired on the final tick would otherwise book as a miss it never
		# had time to disprove.
		if kind == "survive" and _phase == FIRE:
			_fire_threat(1.0 / _pps)
		return
	# Perfect shooter: re-lay the gun (and the lock cone) onto the solution.
	var aim_at: Node3D = _live_target_body()
	if aim_at == null:
		return
	var gun_point: Vector3 = _ballistic_aim_point(aim_at,
			_combat.muzzle_speed, _combat.projectile_gravity_scale)
	if _weapon.global_position.distance_squared_to(gun_point) > 0.01:
		_weapon.look_at(gun_point)
	# The missile homes; the lock cone wants the TRUE bearing, not a lead.
	if _missile.global_position.distance_squared_to(
			aim_at.global_position) > 0.01:
		_missile.look_at(aim_at.global_position)
	# Flak flies its own, slower, droopier arc, so it gets its own solution.
	# Aimed at the BODY, not at a fuse standoff: the shell decides when to burst
	# and that decision is the weapon's, not the shooter's.
	var flak_point: Vector3 = _ballistic_aim_point(aim_at,
			_combat.flak_muzzle_speed, _combat.flak_shell_gravity_scale)
	if _flak.global_position.distance_squared_to(flak_point) > 0.01:
		_flak.look_at(flak_point)
	_hold_fire_near_route_end(aim_at)


## See ROUTE_HOLD_*: don't book teleport-orphaned shots as evasion.
func _hold_fire_near_route_end(aim_at: Node3D) -> void:
	if _phase != FIRE:
		return
	var route: Variant = _target.get(&"route_end")
	if route is not Vector3:
		return
	var eta: float = ((route as Vector3) - aim_at.global_position).length() \
			/ maxf(_enemy_config.speed, 0.1)
	match _cells[_cell_i]["weapon"]:
		"missile":
			_missile.fire_override = eta > ROUTE_HOLD_MISSILE_S
		"flak":
			_flak.fire_override = eta > ROUTE_HOLD_BOLT_S
		_:
			_weapon.fire_override = eta > ROUTE_HOLD_BOLT_S


func _live_target_body() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	if _target.has_method("nearest_body"):
		return _target.call("nearest_body", _drone.global_position) as Node3D
	return _target as Node3D


## The exact firing solution: iterate flight time against the target's linear
## prediction, then raise the aim by the round's own gravity drop. This is the
## bench's definition of "perfect aim" — anything the target does beyond
## flying straight is, by construction, evasion. Parameterized by muzzle speed
## and gravity scale so each weapon is measured against ITS OWN perfect shot,
## not the blaster's.
func _ballistic_aim_point(body: Node3D, muzzle_speed: float,
		gravity_scale: float) -> Vector3:
	return _solution_from(_weapon.global_position, body, muzzle_speed,
			gravity_scale)


## The same solver from an arbitrary muzzle, so Layer 3b's threat is laid by the
## exact code that lays the enemy-evasion bench's shooter. One definition of
## "perfect", used in both directions — otherwise the two halves of the model
## would be measured against two different ideas of a good shot.
func _solution_from(origin: Vector3, body: Node3D, muzzle_speed: float,
		gravity_scale: float) -> Vector3:
	var target_velocity: Vector3 = _velocity_of(body)
	var predicted: Vector3 = body.global_position
	var flight_time: float = 0.0
	for _i: int in 4:
		flight_time = (predicted - origin).length() / maxf(muzzle_speed, 1.0)
		predicted = body.global_position + target_velocity * flight_time
	var drop: float = float(ProjectSettings.get_setting(
			"physics/3d/default_gravity")) * gravity_scale
	return predicted + Vector3.UP * (0.5 * drop * flight_time * flight_time)


## Whatever this body calls its velocity. The bestiary flies CharacterBody3D
## (`velocity`); the player is a RigidBody3D (`linear_velocity`), and reading
## only the first would hand the Layer 3b threat a zero lead against the one
## target in the game that never stops moving — a "perfect" shooter that in fact
## aims where the player used to be, crediting every frame with an evasion it did
## not earn.
func _velocity_of(body: Node3D) -> Vector3:
	var rigid: Variant = body.get(&"linear_velocity")
	if rigid is Vector3:
		return rigid as Vector3
	var kinematic: Variant = body.get(&"velocity")
	if kinematic is Vector3:
		return kinematic as Vector3
	return Vector3.ZERO


## One tick of the bodiless threat: hold cadence, lay the exact solution, fire
## the type's own round. Deliberately NOT the enemy's own `_try_fire` — that path
## carries `aim_jitter_deg` and a tracking loop, which are the THREAT's
## marksmanship and belong to a factor nobody is measuring here (see
## BalancePrediction.survive, assumption 2). Mixing them in would repeat the
## Blaster x Raider mistake with the arrow reversed: a number that reads as the
## player's evasion while reporting the enemy's aim.
## The threat's muzzle for this tick — a stated range and bearing off the player
## (see THREAT_RANGE_M). Kept as a plain position rather than a node so the pilot
## cannot acquire it, orbit it or shoot it: the cell measures dodging, and a
## threat with a body is a second fight.
func _threat_station() -> Vector3:
	return _drone.global_position \
			+ THREAT_BEARING.normalized() * THREAT_RANGE_M


## THE PILOT MUST NOT BE ABLE TO HIDE BEHIND ITS OWN PRACTICE TARGET.
##
## `Projectile._resolve_hit` fizzles a round on ANY collider — a same-team body
## takes no damage but still stops the shot. The pilot's task target is an enemy
## body and the blaster path closes to nearly touching it (the pilot's own trace:
## 0.3 m), so for much of a cell the target sits on the line between the threat
## and the player. Every round it absorbs would have been scored as a miss the
## airframe never earned, and the contamination is largest exactly where the
## pilot spends most of its time.
##
## Excluding it is what `exclude` is for, and it is the same discipline as every
## other isolation in this file: the cell must measure the pilot dodging, not the
## scenery it happens to be standing behind. Built lazily because the threat is
## constructed before the target is.
func _threat_exclude() -> Array[RID]:
	if not _threat_exclude_rids.is_empty() or _target == null \
			or not is_instance_valid(_target):
		return _threat_exclude_rids
	if _target is CollisionObject3D:
		_threat_exclude_rids.append((_target as CollisionObject3D).get_rid())
	return _threat_exclude_rids


func _fire_threat(delta: float) -> void:
	_threat_position = _threat_station()
	_threat_cooldown -= delta
	if _threat_cooldown > 0.0 or _pool == null:
		return
	var muzzle: float = maxf(_threat_config.muzzle_speed, 1.0)
	var solution: Vector3 = _solution_from(_threat_position, _drone, muzzle,
			THREAT_GRAVITY)
	var direction: Vector3 = (solution - _threat_position).normalized()
	# Lifetime sized exactly as the shipped types size theirs, so a round that
	# expires short here would have expired short in the game too.
	var lifetime: float = _threat_config.sight_range / muzzle * 1.6
	# `ProjectilePool.fire` DROPS the shot when the pool is empty, and the count
	# below would book it as a miss. Left unguarded because the headroom is 5x —
	# the pilot's gun carries ~20 rounds in flight and this threat ~3, against a
	# pool of 128 — and a guard for a condition that cannot occur is a branch
	# nobody can ever test. If a future cell fires two threats at a higher
	# cadence, revisit this line first.
	_pool.fire(_threat_position + direction * 0.6, direction * muzzle,
			_threat_config.damage, &"enemy", _threat_exclude(), THREAT_GRAVITY,
			lifetime)
	_threat_shots += 1
	_threat_cooldown = 1.0 / maxf(_threat_config.fire_rate, 0.001)


func _cease_fire() -> void:
	_weapon.fire_override = false
	_missile.fire_override = false
	_flak.fire_override = false
	_weapon.combat_config.fire_assist_miss_m = 0.0


func _score_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	var kind: String = cell["kind"]
	if kind == "survive":
		_score_survive(cell)
		return
	if kind == "contact":
		_score_contact(cell)
		return
	var weapon_id: String = cell["weapon"]
	var shots: int = 0
	var connects: int = 0
	# Splash: bodies covered per ARRIVING burst. Exactly 1.0 for every weapon
	# that damages one body per connect, which is what makes it a free extension
	# rather than a new dimension (BALANCE.md, assumption 3b).
	var splash: float = 1.0
	match weapon_id:
		"missile":
			shots = _missile.launches
			connects = _connects
		"flak":
			# Counted weapon-side, because an area weapon needs the two numbers
			# separated: `bursts_connected` is arrival (comparable with every
			# other cell's rate) and `bodies_struck` is coverage.
			shots = _flak.shots_fired
			connects = _flak.bursts_connected
			if connects > 0:
				splash = float(_flak.bodies_struck) / float(connects)
			# CROSS-CHECK of two independent counters: the pod counts bodies as
			# it damages them, the TARGET counts arrivals through Health.struck /
			# the swarm's own kill signal. They must agree, and if they ever
			# stop, one of the two is lying about a number the whole flak column
			# is derived from.
			if _connects != _flak.bodies_struck:
				_failures.append("%s: target-side connects %d != pod-side bodies struck %d — the two counters disagree"
						% [cell["name"], _connects, _flak.bodies_struck])
		_:
			shots = _weapon.shots_fired
			connects = _connects
	var rate: float = float(connects) / float(shots) if shots > 0 else 0.0
	var duty: float = _duty_cycle(cell, shots)
	_results.append({"shots": shots, "connects": connects, "rate": rate,
			"splash": splash, "duty": duty})
	var splash_note: String = "  splash %.2f bodies/burst" % splash \
			if weapon_id == "flak" else ""
	print("[delivery] %-28s %4d shots, %4d connects  -> %.2f  (duty %.2f)%s"
			% [cell["name"], shots, connects, rate, duty, splash_note])
	if shots == 0:
		_failures.append("%s: fired nothing — rig broken" % cell["name"])
	elif cell.get("control", false) and rate < CONTROL_MIN_RATE:
		_failures.append("%s: control rate %.2f under %.2f — the perfect shooter cannot shoot; fix the bench before reading evasion"
				% [cell["name"], rate, CONTROL_MIN_RATE])


## LAYER 3b (`kind: survive`). The factor is `taken / fired_at_you` — the same
## connect-rate convention the enemy rows use, and stored the same way round:
## LOW IS EVASIVE. It reads backwards from the word "evasion" and always has;
## the compensation is that it multiplies straight into a hit rate on either
## side of the model instead of needing a `1 -` somewhere that nobody remembers.
##
## Three numbers accompany it, and each exists because leaving it out would let
## the headline be misread:
##  - JINK DUTY. Now a CHECK rather than a caveat: every cell forces its state,
##    so this must read 1.00 on a `[jink]` row and 0.00 on a `[steady]` one. Any
##    value in between means the force did not take and the cell is back to being
##    the feedback loop the forcing exists to break.
##  - AIM UNDER FIRE. The pilot is flying the aim bench's own task, so the same
##    cell reports what its gun did while dodging. Against the undisturbed aim
##    cell (kestrel/blaster 0.17) that difference is the PRICE of the jink,
##    measured rather than inferred from duels.
##  - HULL SPENT. Diagnostic only — the player is immortal here, so this is what
##    the rounds WOULD have cost a mortal frame over the window, and it is the
##    one number that shows armor working (a Kestrel and an Atlas can take the
##    same count of hits for very different damage).
func _score_survive(cell: Dictionary) -> void:
	var rate: float = float(_taken) / float(_threat_shots) \
			if _threat_shots > 0 else 0.0
	# Over the WHOLE measured window, firing plus grace — the pilot flies through
	# both and the rounds still in the air during grace are being dodged like any
	# other. Dividing by the firing window alone would let a long grace push the
	# duty of a fraction past 1.0.
	var duty: float = float(_jink_ticks) \
			/ float(maxi(_fire_ticks + _grace_ticks, 1))
	var gun_shots: int = _weapon.shots_fired
	var aim_under_fire: float = float(_connects) / float(gun_shots) \
			if gun_shots > 0 else 0.0
	var frame: FrameConfig = Frames.config(String(cell["frame"]))
	var per_hit: float = maxf(_threat_config.damage - frame.armor, 0.0)
	var hull_spent: float = per_hit * float(_taken) / maxf(frame.hull, 1.0)
	_results.append({"shots": _threat_shots, "connects": _taken, "rate": rate,
			"splash": 1.0, "duty": duty, "aim_under_fire": aim_under_fire,
			"hull_spent": hull_spent, "valid": _taken > 0})
	# The gun's shot count rides along with its rate, because the aim-under-fire
	# figure comes off a 25 s window at a ~0.3 duty: that is single-digit-to-tens
	# of shots, and a bare "0.30" from three hits in ten reads as a measurement
	# when it is a coin toss. Print the fraction and let the reader see the n.
	print("[delivery] %-28s %4d at you, %4d taken -> %.2f  (jink duty %.2f, aim under fire %d/%d = %.2f, hull %.0f%%)"
			% [cell["name"], _threat_shots, _taken, rate, duty, _connects,
			gun_shots, aim_under_fire, hull_spent * 100.0])
	if _threat_shots == 0:
		_failures.append("%s: the threat fired nothing — rig broken" % cell["name"])
	elif cell.get("control", false) and rate < CONTROL_MIN_RATE:
		_failures.append("%s: control rate %.2f under %.2f — a perfect solution cannot hit a PARKED player; fix the threat before reading any frame's evasion"
				% [cell["name"], rate, CONTROL_MIN_RATE])
	elif not cell.get("control", false):
		if _taken == 0:
			# ZERO HITS IS NOT A FACTOR OF 0.00, it is a cell with no measurement
			# in it — and 0.00 is the single most dangerous number this table can
			# carry, because it composes into "this frame is invulnerable to this
			# threat, forever". Whatever the cause (a geometry bug, or an airframe
			# thrown around so hard that a perfect solution cannot find it), the
			# bench must refuse rather than publish. `valid` below keeps it out of
			# the artifact as well as failing the run: a FAIL nobody reads still
			# leaves a poisoned file behind.
			_failures.append("%s: nothing landed in %d shots — no measurement in this cell, and 0.00 must never reach the factor table (see the gun figure: %d/%d)"
					% [cell["name"], _threat_shots, _connects, gun_shots])
		_flag_control_loss(cell, aim_under_fire, gun_shots)


## IS THIS FRAME EVADING, OR IS IT COMING APART? The two look identical in the
## headline number — both read as "hard to hit" — and they mean opposite things
## for the frame axis. One is the airframe's virtue; the other is the pilot's
## jink being too much aircraft for it.
##
## The cell already contains the discriminator, because the pilot is flying the
## AIM task while it dodges: **a frame that is evading keeps shooting.** Compare
## this cell's hits-per-shot against the same frame's undisturbed aim cell and
## the two cases separate cleanly — which is not a hypothetical, it is what the
## first measured run did (v1.78): the Kestrel held 0.17 against 0.17 while the
## Atlas fell from 0.19 to 0.00 across 47 shots in two cells.
##
## A WARNING, never a failure. The number is real and gets committed either way;
## what must not happen is a reader taking a collapsed cell for good news about
## an airframe. Tuning the jink until this stops printing would be tuning the
## ruler to flatter the thing it measures.
func _flag_control_loss(cell: Dictionary, aim_under_fire: float,
		gun_shots: int) -> void:
	var clean: float = _clean_aim_rate(String(cell["frame"]),
			String(cell["weapon"]))
	if clean <= 0.05 or gun_shots <= 0:
		return
	if aim_under_fire >= clean * 0.25:
		return
	print("[delivery] %-28s   ^ WARNING: gun collapsed under fire (%.2f vs %.2f clean) — a frame that is EVADING keeps shooting, so read this cell's low hit rate as possible LOSS OF CONTROL, not as durability"
			% ["", aim_under_fire, clean])


## This run's undisturbed aim rate for a frame+weapon, or -1.0 when the aim cell
## has not run yet. Addressed BY NAME through the cell list rather than by index,
## the same rule the harness's asserts follow — and read from THIS run rather
## than from the committed artifact, so the comparison cannot straddle two
## measurements.
func _clean_aim_rate(frame_id: String, weapon: String) -> float:
	for i: int in _results.size():
		var candidate: Dictionary = _cells[i]
		if candidate["kind"] == "aim" \
				and String(candidate.get("frame", "")) == frame_id \
				and String(candidate["weapon"]) == weapon:
			return float(_results[i]["rate"])
	return -1.0


## THE CONTACT MODE'S DELIVERY TERM (Layer 3a's named gap). Not a fraction: a
## gnat that arrives always stings, so there is nothing to miss with. What varies
## is WHEN — the cloud's approach against the frame's speed — so this cell reports
## a rate, in bodies per second, measured between the first sting and the last.
##
## Transit is reported separately and NOT folded in. Time-to-first-sting is a
## property of where this bench parked the cloud as much as of the frame, while
## the spend rate is a property of the pack meeting the aircraft; averaging one
## into the other would bake an arena constant into a roster number.
func _score_contact(cell: Dictionary) -> void:
	var span: float = maxf(_last_sting_s - _first_sting_s, 0.0)
	var rate: float = float(_taken - 1) / span if _taken >= 2 and span > 0.0 \
			else 0.0
	var transit: float = _first_sting_s if _first_sting_s >= 0.0 else -1.0
	var frame: FrameConfig = Frames.config(String(cell["frame"]))
	var per_hit: float = maxf(_threat_config.damage - frame.armor, 0.0)
	var hull_spent: float = per_hit * float(_taken) / maxf(frame.hull, 1.0)
	_results.append({"shots": int(_threat_config.pack_size), "connects": _taken,
			"rate": rate, "splash": 1.0, "duty": 0.0, "transit": transit,
			"hull_spent": hull_spent})
	print("[delivery] %-28s %2d of %d bodies stung in %.1fs -> %.2f stings/s  (transit %.1fs, hull %.0f%%)"
			% [cell["name"], _taken, int(_threat_config.pack_size), span, rate,
			transit, hull_spent * 100.0])
	if _taken < CONTACT_MIN_STINGS:
		_failures.append("%s: only %d stings landed (need %d) — the cloud never resolved inside the window, so there is no rate to read"
				% [cell["name"], _taken, CONTACT_MIN_STINGS])


## Shots taken as a fraction of shots the cadence ALLOWED in the window.
##
## Reported because the flak column made an old conflation visible: `aim` is
## hits-per-shot-FIRED, so it says nothing about how often a shot was taken, and
## the two aim cells do not pull their triggers the same way. The blaster's is
## pulled by the gun director, which fires on any arc solution and so takes many
## marginal shots (duty ~0.4, aim 0.17); the flak pod has no director, so the
## pilot only fires inside a 6-degree cone and nearly every shell fuses (duty
## ~0.7, aim 1.00). Reading 1.00 against 0.17 as "flak aims six times better"
## would be reading two different rulers — the same mistake, in a new column,
## that Blaster x Raider cost a whole phase.
##
## Deliberately NOT folded into the model. Prediction assumes shots arrive at
## the weapon's full cadence (assumption 2), so a duty under 1.0 is a standing
## OPTIMISM in every predicted ttk — pre-existing, not new, and it belongs in
## the report as a named factor rather than in a quiet correction coefficient.
func _duty_cycle(cell: Dictionary, shots: int) -> float:
	var cadence: float = 1.0 / maxf(_combat.fire_rate, 0.001)
	match String(cell["weapon"]):
		"missile":
			cadence = maxf(_combat.missile_cooldown, 0.001)
		"flak":
			cadence = 1.0 / maxf(_combat.flak_fire_rate, 0.001)
	var allowed: float = float(cell["seconds"]) / cadence
	return float(shots) / allowed if allowed > 0.0 else 0.0


func _teardown() -> void:
	_pilot = null
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null
	_weapon = null
	_missile = null
	_flak = null
	_target = null
	_enemy_config = null
	_pool = null
	_threat_config = null


func _advance() -> void:
	_cell_i += 1
	if _cell_i >= _cells.size():
		_report()
	else:
		_phase = BUILD


func _report() -> void:
	print("[delivery] ---- Layer 2 factors (pilot v%d) ----"
			% ReferencePilot.PILOT_VERSION)
	for i: int in _cells.size():
		var cell: Dictionary = _cells[i]
		if cell["kind"] == "contact":
			print("[delivery] %-28s %.2f stings/s  (transit %.1fs)"
					% [cell["name"], _results[i]["rate"],
					float(_results[i].get("transit", -1.0))])
			continue
		if cell["kind"] == "survive":
			print("[delivery] %-28s %.2f  (jink duty %.2f)"
					% [cell["name"], _results[i]["rate"], _results[i]["duty"]])
			continue
		var splash: float = float(_results[i]["splash"])
		print("[delivery] %-28s %.2f  (duty %.2f)%s" % [cell["name"],
				_results[i]["rate"], _results[i]["duty"],
				"   x %.2f bodies/burst" % splash if splash != 1.0 else ""])
	print("[delivery] duty = shots taken / shots the cadence allowed. Aim cells with")
	print("[delivery] different duty measured under different TRIGGER policies, so their")
	print("[delivery] hit rates are not directly comparable (see _duty_cycle).")
	print("[delivery] Layer 3b rows read the other way round: `at you / taken`, and their")
	print("[delivery] duty is the JINK's, not a trigger's. Contact rows are a RATE, not a")
	print("[delivery] fraction — a gnat that arrives always stings (see _score_contact).")
	_write_factors()
	if _failures.is_empty():
		print("[delivery] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[delivery] FAIL: %s" % f)
		print("[delivery] FAIL")
		quit(1)


## Leave the measured factors where the prediction layer can find them, as a
## COMMITTED artifact: the delivery table is the pinned pilot's ruler, so it
## belongs in the repo next to PILOT_VERSION, diffable, with the version it
## was measured under written inside it. A factors file whose pilot_version
## does not match the code is stale by construction and says so.
func _write_factors() -> void:
	if _filtered:
		# See _select_cells: a partial run would silently delete every factor it
		# did not measure, and the file would look complete afterwards.
		print("[delivery] filtered run — factors NOT written (nothing was overwritten).")
		return
	var aim: Dictionary = {}
	var evasion: Dictionary = {}
	var control: Dictionary = {}
	var splash: Dictionary = {}
	var player_evasion: Dictionary = {}
	var steady: Dictionary = {}
	var contact: Dictionary = {}
	for i: int in _cells.size():
		var cell: Dictionary = _cells[i]
		var rate: float = snappedf(float(_results[i]["rate"]), 0.01)
		var yield_per_burst: float = snappedf(float(_results[i]["splash"]), 0.01)
		var weapon: String = cell["weapon"]
		if cell["kind"] == "survive":
			# The control parks the player, so its rate describes the BENCH, not
			# a frame. It rides in the same `control` section the enemy-side
			# controls use rather than in the factor table, on the same rule:
			# a datum that proves the rig is not a measurement of the thing.
			var frame_id: String = String(cell["frame"])
			var key: String = BalancePrediction.player_evasion_key(
					String(cell["threat"]), frame_id)
			if not bool(_results[i].get("valid", true)):
				# The cell scored nothing and said so loudly (see _score_survive).
				# Omitting it leaves the model with no factor for this pair, which
				# blanks the survival line — the same honest degradation a missing
				# aim factor already gets. Writing 0.00 instead would publish
				# "invulnerable" as a measurement.
				continue
			if cell.get("control", false):
				control[BalancePrediction.player_evasion_key(
						"parked", frame_id)] = rate
			elif String(cell.get("jink", "")) == "never":
				# The datum, not the factor: what this frame eats flying straight.
				# Kept in its own table so nothing can compose with it by
				# accident — the model's pilot is always the jinking one.
				steady[key] = rate
			else:
				player_evasion[key] = rate
			continue
		if cell["kind"] == "contact":
			contact[BalancePrediction.contact_key(String(cell["threat"]),
					String(cell["frame"]))] = rate
			continue
		if cell["kind"] == "aim":
			aim[BalancePrediction.aim_key(String(cell["frame"]), weapon)] = rate
		elif cell.get("splash_only", false):
			# This cell contributes ONLY its splash yield; its arrival rate is
			# measured under different geometry (a converging group) than the
			# single-target evasion cell that owns the evasion key, and letting
			# it overwrite that key would mix two rulers under one name.
			if yield_per_burst != 1.0:
				splash[BalancePrediction.splash_key(weapon,
						TYPE_IDS[cell["target"]])] = yield_per_burst
		elif cell["target"] == "static":
			control[BalancePrediction.evasion_key(weapon, "static")] = rate
		else:
			var type_id: String = TYPE_IDS[cell["target"]]
			evasion[BalancePrediction.evasion_key(weapon, type_id)] = rate
			# Only written when it is not the identity, so the artifact stays a
			# record of what an AREA weapon does rather than a wall of 1.00s.
			if yield_per_burst != 1.0:
				splash[BalancePrediction.splash_key(weapon, type_id)] = \
						yield_per_burst
	# Stamped with BOTH rulers these factors were measured under: the pilot
	# that flew them and the config numbers they were flown against — weapons,
	# bestiary, and (since Phase 4b) the frames' own flight models, which were
	# always a delivery input and were never stamped. Either drifting makes the
	# file stale, and the reader refuses it rather than quoting measurements
	# taken under different physics.
	var enemies: Array[EnemyConfig] = []
	for path: String in ENEMIES_FOR_STAMP:
		enemies.append(load(path) as EnemyConfig)
	var payload: Dictionary = {
		"pilot_version": ReferencePilot.PILOT_VERSION,
		"config_stamp": BalancePrediction.config_stamp(_combat, enemies,
				Frames.all_configs()),
		"aim": aim,
		"evasion": evasion,
		"splash": splash,
		"control": control,
		# Layer 3b (v1.78). Same file, because it is the same kind of thing
		# measured by the same bench under the same two rulers — splitting it out
		# would have given the model two artifacts that can go stale
		# independently, which is how half a table gets quoted.
		"player_evasion": player_evasion,
		# The same pairs flown STRAIGHT. Never composed with — it is the datum
		# `player_evasion` is worth against, and the pair's difference is the
		# only honest statement of what the jink buys.
		"player_evasion_steady": steady,
		"contact_rate": contact,
	}
	DirAccess.make_dir_recursive_absolute(
			BalancePrediction.FACTORS_PATH.get_base_dir())
	var file: FileAccess = FileAccess.open(
			BalancePrediction.FACTORS_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("could not write %s" % BalancePrediction.FACTORS_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.close()
	print("[delivery] wrote %s" % BalancePrediction.FACTORS_PATH)
