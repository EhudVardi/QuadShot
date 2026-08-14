extends SceneTree

## THE FEASIBILITY BENCH (GAMEPLAY-DESIGN Iteration 16 / L13 phase 0.1).
##
## The user's question, verbatim: *"can we meter the capabilities we have with
## our env' and engine, to search for different limits that our new scaled world
## presents. so yes, technically, if possible, ~10 kestrels level frames can hurt
## a roc level frame."* The entire size-class roster in L11 is designed on the
## assumption that the answer is yes, so this runs before anything downstream.
##
## IT ANSWERS TWO SEPARATE THINGS AND MUST NEVER CONFLATE THEM.
##
##  A. ENGINE LOAD — how many active units can the scene hold while a 240 Hz tick
##     still fits in its budget? Swept, so the WALL gets a number rather than a
##     shrug. See MEASURING LOAD below: the obvious instrument does not work.
##  B. COMBAT VIABILITY — can N small units meaningfully hurt one heavy frame?
##     Reported as time-to-kill, damage rate and connect rate, per frame, so the
##     size axis is visible rather than asserted.
##
## THREE THINGS THIS BENCH DELIBERATELY DOES NOT DO, each for a stated reason:
##
##  1. **It does not measure the heavy frame shooting BACK.** `ReferencePilot` is
##     v7 and was tuned to Kestrel agility; L6 puts "teach the pilot to fly a big
##     frame" in phase 2 precisely because until then "the Roc lost" is equally
##     consistent with a weak airframe and a pilot that flew into the ground.
##     Measuring the outgoing half here would publish that confound as a number.
##     The INCOMING half needs no pilot at all, which is why it can run today.
##  2. **The target does not evade.** It holds the shipped autopilot hover
##     (`FlightController.autopilot`), so what is measured is the SWARM'S ability
##     to deliver damage — an upper bound on the threat, with the pilot's
##     contribution held at zero. Anything a pilot does can only subtract.
##  3. **Headless means no rendering**, so the load figures are the FLOOR of the
##     real per-tick cost. A rendered frame adds draw calls on top of every
##     number in table A. Drop `--headless` to see those; the physics numbers do
##     not move (BenchView's scenery carries no collider).
##
## MEASURING LOAD, AND WHY THE OBVIOUS INSTRUMENT IS A LIE.
##
## The first version of this file timed wall-clock between physics ticks. It read
## **4.169 ms at every unit count**, which is 1/240 s to four digits — because
## Godot PACES physics to real time. With headroom the engine simply waits, so
## wall-clock per tick measures the clock, not the work, and a sweep of it is a
## flat line that looks like a beautifully optimised game.
##
## `Performance.TIME_PHYSICS_PROCESS` is not the fix either. Probed against
## script-free rigid bodies it does include the physics server's step (0.12 ms at
## 0 bodies, 22 ms at 1600) — but at 1600 bodies it claims 22 ms per tick while
## the simulation is demonstrably holding real time at 4.17 ms, so it is off by
## something like the sub-step count and cannot be read as a per-tick cost.
##
## **What works is to ASK FOR MORE TICKS THAN THE CLOCK WANTS.** Raise
## `Engine.physics_ticks_per_second` far above 240 and the pacing has nothing to
## wait for; the engine then delivers as many ticks per real second as the machine
## can compute, and that number IS the tick capacity. Headroom is capacity / 240.
## Verified against script-free bodies, where it produces a curve the pinned
## instrument could not see at all: 200 bodies -> 21096 Hz, 800 -> 1067 Hz,
## 3200 -> 197 Hz, i.e. a wall between 800 and 3200 that agrees with the
## independent real-time measurement (1600 bodies held 240 Hz exactly).
##
## THE ONE DISTORTION IT INTRODUCES, STATED: inside the probe window a tick
## advances 1/PROBE_HZ of a second instead of 1/240, so anything that counts in
## SECONDS (fire cooldowns, projectile lifetimes) slows down relative to ticks.
## The per-tick COST is unaffected — the same bodies, scripts and line-of-sight
## raycasts run — but the window is deliberately short and taken after a warm-up,
## so the population it measures is the steady-state fight's. The distortion-free
## half is reported beside it: whether the cell held a true 240 Hz during warm-up,
## which needs no trick and is the claim that actually matters.
##
## Run:   <godot> --headless -s scripts/tests/swarm_bench.gd --path .
## WATCH: <godot> -s scripts/tests/swarm_bench.gd --path .
## Filter a single cell (a LOOK, never a board):
##        <godot> -s scripts/tests/swarm_bench.gd --path . -- "kill roc 20"

## --- A. Engine load -----------------------------------------------------------
## Swept up to a count nothing in the game will ever spawn on purpose, because
## the point is to find the wall rather than to confirm the current content fits.
const LOAD_COUNTS: Array[int] = [5, 10, 20, 40, 80, 160, 320]
## The heavy frame, so the load cells carry the largest collider in the roster.
const LOAD_FRAME: String = Frames.ROC
## Long enough for a 45 m ingress at 14 m/s to become a steady-state orbit, so
## the measured window is a FIGHT rather than an approach. The last second of it
## is the distortion-free "did this hold a true 240 Hz" sample.
const LOAD_WARMUP_S: float = 4.0
const LOAD_REALTIME_S: float = 1.5
## The demanded tick rate for the capacity probe (see MEASURING LOAD). It is a
## CEILING as well as a demand: a cell that meets it in full is reported as "at
## least" that much headroom, never as a measurement of how much more it had.
const PROBE_HZ: int = 20000
## Ticks measured at PROBE_HZ. Short on purpose — long enough to average out
## scheduler noise, short enough that the second-counting distortion cannot
## change the population being weighed.
const PROBE_TICKS: int = 3000
## The first cell of any run pays for shader compilation, resource loading and a
## cold instruction cache, and at small N that overhead is most of the reading —
## the first sweep put N=5 at 3671 Hz and N=10 at 8843, which is a warm-up
## artifact wearing a measurement's clothes. So the first cell is thrown away.
const DISCARD_FIRST_CELL: bool = true

## --- B. Combat viability ------------------------------------------------------
const KILL_FRAMES: Array[String] = [Frames.KESTREL, Frames.CONDOR, Frames.ROC]
const KILL_COUNTS: Array[int] = [5, 10, 20]
const KILL_CAP_S: float = 45.0

## The small unit doing the hurting. The raider is the shipped Kestrel-class
## attacker (0.5 m body, hull 40, 8 damage at 1.5/s, 3 deg of jitter) and is what
## "~10 kestrels level frames" means in content that exists today.
const RAIDER_SCENE: String = "res://scenes/combat/enemy_drone.tscn"
const RAIDER_CONFIG: String = "res://resources/default_enemy_raider.tres"

## High enough that nothing in the arena is near the ground, and the arena has no
## ground collider anyway — a projectile that misses flies its whole lifetime,
## which is the worst case for the pool and therefore the honest one.
const ARENA_ALTITUDE: float = 60.0
## Inside the raider's 60 m sight range, outside its 18 m orbit, so every unit
## has to fly an ingress before it shoots.
const SPAWN_RADIUS: float = 45.0
const IMMORTAL_HULL: float = 1.0e9

## Half the projectile's cross-section (its box is 0.06 x 0.06 x 0.5). It counts
## toward the geometric hit prediction because a round grazing the hull still
## connects, and at Kestrel scale it is a third of the target's own radius.
const ROUND_HALF_M: float = 0.03

enum { BUILD, RUN, RECORD }


## The projectile pool, instrumented. Two numbers no other instrument in this
## project can see: how many rounds were actually FIRED, and how many were
## DROPPED because the fixed pool was empty.
##
## The second is the whole reason this exists. `ProjectilePool.fire` returns
## silently when the pool is exhausted (its header says so: "exhaustion drops
## shots instead of allocating"), so a swarm past the pool's capacity keeps
## pulling triggers into a void and the fight simply gets quieter with no error
## anywhere. That is an engine limit wearing balance's clothes, and it is exactly
## the class of thing L13 phase 0 exists to find.
class CountingPool extends ProjectilePool:
	var fired: int = 0
	var dropped: int = 0

	func fire(origin: Vector3, velocity: Vector3, damage: float,
			team: StringName, exclude: Array[RID], gravity_scale: float,
			lifetime: float) -> void:
		if live_count() >= POOL_SIZE:
			dropped += 1
			return
		fired += 1
		super.fire(origin, velocity, damage, team, exclude, gravity_scale,
				lifetime)


var _cells: Array[Dictionary] = []
var _filtered: bool = false
var _results: Array[Dictionary] = []
var _failures: PackedStringArray = []
var _watching: bool = BenchView.watching()

var _pps: float
## What one physics tick is actually allowed to cost, in milliseconds.
var _budget_ms: float

var _cell_i: int = 0
var _phase: int = BUILD
var _ticks: int = 0

# Live cell.
var _arena: Node3D
var _drone: FlightController
var _health: Health
var _pool: CountingPool
var _raiders: Array[Node3D] = []
var _player_max: float = 100.0

# Load-cell timing.
var _window_start_usec: int = 0
var _realtime_hz: float = 0.0
var _live_projectiles_max: int = 0
var _collision_pairs_sum: float = 0.0
var _pairs_samples: int = 0

# Kill-cell tally.
var _hits: int = 0
var _first_hit_tick: int = -1
var _death_tick: int = -1


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_budget_ms = 1000.0 / _pps
	_build_cells()
	print("[swarm] feasibility bench — %d cells, %.0f Hz tick (%.3f ms budget), display %s"
			% [_cells.size(), _pps, _budget_ms, DisplayServer.get_name()])
	if not _watching:
		print("[swarm] headless: no rendering, so load figures are the FLOOR of the real per-tick cost.")
	BenchView.setup("swarm")
	physics_frame.connect(_on_physics_frame)


## Both sweeps, flattened, plus the optional name filter. A filtered run is a
## LOOK — it skips every assert, because the asserts address cells by name and a
## narrowed sweep would fail them for absence rather than for anything being
## wrong. Same discipline as the delivery bench and the matchup harness.
func _build_cells() -> void:
	var all: Array[Dictionary] = []
	if DISCARD_FIRST_CELL:
		all.append({"mode": "load", "frame": LOAD_FRAME, "count": LOAD_COUNTS[0],
				"discard": true, "name": "load warm-up (discarded)"})
	for count: int in LOAD_COUNTS:
		all.append({"mode": "load", "frame": LOAD_FRAME, "count": count,
				"name": "load %s %d" % [LOAD_FRAME, count]})
	for frame: String in KILL_FRAMES:
		for count: int in KILL_COUNTS:
			all.append({"mode": "kill", "frame": frame, "count": count,
					"name": "kill %s %d" % [frame, count]})
	var filter: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.strip_edges() != "":
			filter = argument.strip_edges().to_lower()
			break
	for cell: Dictionary in all:
		if filter == "" or String(cell["name"]).to_lower().contains(filter):
			_cells.append(cell)
	_filtered = _cells.size() != all.size()
	if _filtered:
		print("[swarm] FILTERED to %d of %d cells matching '%s' — this run is a LOOK, not a board; asserts SKIPPED."
				% [_cells.size(), all.size(), filter])
	if _cells.is_empty():
		print("[swarm] FAIL: filter '%s' matched no cells." % filter)
		quit(1)


func _on_physics_frame() -> void:
	match _phase:
		BUILD:
			_build_cell()
			_phase = RUN
		RUN:
			_run_tick()
		RECORD:
			_teardown()
			_cell_i += 1
			if _cell_i >= _cells.size():
				_report()
			else:
				_phase = BUILD


# --- building -----------------------------------------------------------------

func _build_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	var count: int = int(cell["count"])
	_arena = Node3D.new()
	root.add_child(_arena)
	if _watching:
		BenchView.build_scenery(_arena)

	_pool = CountingPool.new()
	_arena.add_child(_pool)

	_drone = Frames.build(String(cell["frame"]))
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ARENA_ALTITUDE, 0.0)
	_health = _drone.get_node("Health") as Health
	if cell["mode"] == "load":
		# A load cell must hold its unit count for the whole window. A player who
		# dies stops being engageable (EnemyDrone._can_engage reads `armed` and
		# `visible`), and the fight — the thing being weighed — evaporates
		# mid-measurement, so the tail of the sweep would read as cheap because
		# nothing was happening.
		_health.max_health = IMMORTAL_HULL
		_health.revive()
	_player_max = _health.max_health
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())
	# The shipped position hold (pause mode's autopilot): level-and-brake plus
	# hover collective. Not evasion, on purpose — see the header's point 2.
	_drone.autopilot = true
	_health.struck.connect(func(_amount: float) -> void: _hits += 1)
	_health.died.connect(func() -> void: _death_tick = _ticks)

	var scene: PackedScene = load(RAIDER_SCENE) as PackedScene
	_raiders.clear()
	for i: int in count:
		var raider: Node3D = scene.instantiate() as Node3D
		# Determinism (P4.8): the seed must be set before the node enters the
		# tree, and every body must differ from every other or N raiders fly one
		# trajectory in N-plicate and the sweep measures a queue instead of a
		# swarm.
		raider.set(&"ai_seed", i)
		raider.position = _spawn_point(i, count)
		_arena.add_child(raider)
		_raiders.append(raider)

	_ticks = 0
	_hits = 0
	_first_hit_tick = -1
	_death_tick = -1
	_realtime_hz = 0.0
	_live_projectiles_max = 0
	_collision_pairs_sum = 0.0
	_pairs_samples = 0
	_window_start_usec = 0
	if _watching:
		BenchView.follow(_drone)
		print("[swarm] --- %s ---" % cell["name"])


## A shell around the target rather than a ring. A ring puts every unit on one
## bearing band, which both under-counts the collision work and lets the whole
## swarm share one line of sight; a shell is what a swarm converging from all
## sides actually looks like, and it is the harder case for the broadphase.
##
## Golden-angle azimuth with quasi-random radius and altitude offsets, so no two
## bodies start inside each other even at N = 320 (which a naive even ring would
## do at 0.9 m spacing).
func _spawn_point(index: int, count: int) -> Vector3:
	var azimuth: float = float(index) * 2.39996323
	var radius: float = SPAWN_RADIUS * (0.75 + 0.5 * fmod(float(index) * 0.618034, 1.0))
	var lift: float = (fmod(float(index) * 0.381966, 1.0) - 0.5) * 24.0
	return Vector3(cos(azimuth) * radius,
			maxf(ARENA_ALTITUDE + lift, 6.0),
			sin(azimuth) * radius)


# --- running ------------------------------------------------------------------

func _run_tick() -> void:
	var now: int = Time.get_ticks_usec()
	_ticks += 1
	if _first_hit_tick < 0 and _hits > 0:
		_first_hit_tick = _ticks

	var cell: Dictionary = _cells[_cell_i]
	if cell["mode"] == "load":
		_run_load_tick(now)
		return

	if _death_tick >= 0 or _ticks >= int(KILL_CAP_S * _pps):
		_record_kill()


## Three stages, in order: settle at the game's real tick rate, sample whether
## that rate actually held, then lift the pacing and read the capacity.
func _run_load_tick(now: int) -> void:
	var realtime_start: int = int((LOAD_WARMUP_S - LOAD_REALTIME_S) * _pps)
	var realtime_end: int = int(LOAD_WARMUP_S * _pps)
	if _ticks < realtime_start:
		return
	if _ticks == realtime_start:
		_window_start_usec = now
		return
	if _ticks <= realtime_end:
		# Population statistics belong to THIS stage, because it is the one
		# running at the game's own tick rate — the probe stage's slowed clock
		# would under-count rounds in flight.
		_collision_pairs_sum += Performance.get_monitor(
				Performance.PHYSICS_3D_COLLISION_PAIRS)
		_pairs_samples += 1
		_live_projectiles_max = maxi(_live_projectiles_max, _pool.live_count())
		if _ticks == realtime_end:
			# Ticks delivered per REAL second at the demanded 240. Below 240 the
			# machine is already failing to keep up, and no probe is needed to
			# say so.
			_realtime_hz = float(realtime_end - realtime_start) \
					/ (float(now - _window_start_usec) / 1000000.0)
			Engine.max_physics_steps_per_frame = 512
			Engine.physics_ticks_per_second = PROBE_HZ
			_window_start_usec = now
		return
	if _ticks >= realtime_end + PROBE_TICKS:
		_record_load(now)


func _record_load(now: int) -> void:
	var cell: Dictionary = _cells[_cell_i]
	var seconds: float = float(now - _window_start_usec) / 1000000.0
	var capacity_hz: float = float(PROBE_TICKS) / maxf(seconds, 0.000001)
	# Back to the game's tick rate before the next cell builds anything, or the
	# following cell's warm-up would run at 20 kHz and its drones would never
	# spool their motors.
	Engine.physics_ticks_per_second = int(_pps)
	Engine.max_physics_steps_per_frame = 8
	var alive: int = 0
	for raider: Node3D in _raiders:
		if is_instance_valid(raider):
			alive += 1
	if cell.get("discard", false):
		_phase = RECORD
		return
	_results.append({
		"name": cell["name"],
		"mode": "load",
		"count": int(cell["count"]),
		"alive": alive,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"active_bodies": Performance.get_monitor(
				Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"pairs": _collision_pairs_sum / float(maxi(_pairs_samples, 1)),
		"realtime_hz": _realtime_hz,
		"capacity_hz": capacity_hz,
		"ms_per_tick": 1000.0 / capacity_hz,
		"probe_capped": capacity_hz >= float(PROBE_HZ) * 0.95,
		"draw_calls": Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"live_projectiles": _live_projectiles_max,
		"fired": _pool.fired,
		"dropped": _pool.dropped,
	})
	_phase = RECORD


func _record_kill() -> void:
	var cell: Dictionary = _cells[_cell_i]
	var killed: bool = _death_tick >= 0
	var end_tick: int = _death_tick if killed else _ticks
	var under_fire: float = 0.0
	if _first_hit_tick >= 0:
		under_fire = float(end_tick - _first_hit_tick) / _pps
	var damage: float = _player_max - _health.current
	var alive: int = 0
	for raider: Node3D in _raiders:
		if is_instance_valid(raider):
			alive += 1
	_results.append({
		"name": cell["name"],
		"mode": "kill",
		"frame": String(cell["frame"]),
		"count": int(cell["count"]),
		"alive": alive,
		"killed": killed,
		"ttk": float(end_tick) / _pps,
		"under_fire": under_fire,
		"first_hit": float(maxi(_first_hit_tick, 0)) / _pps,
		"damage": damage,
		"hull": _player_max,
		"hits": _hits,
		"fired": _pool.fired,
		"dropped": _pool.dropped,
	})
	_phase = RECORD


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null
	_health = null
	_pool = null
	_raiders.clear()


# --- reporting ----------------------------------------------------------------

func _report() -> void:
	_report_load()
	_report_kill()
	if _filtered:
		print("[swarm] FILTERED LOOK — asserts skipped, no verdict. Run without a filter for a board.")
		quit(0)
		return
	_check()
	if _failures.is_empty():
		print("[swarm] PASS")
		quit(0)
	else:
		for failure: String in _failures:
			print("[swarm] FAIL: %s" % failure)
		print("[swarm] FAIL")
		quit(1)


func _report_load() -> void:
	var rows: Array[Dictionary] = _rows("load")
	if rows.is_empty():
		return
	print("")
	print("[swarm] ==== A. ENGINE LOAD — one %s + N raiders ====" % LOAD_FRAME)
	print("[swarm] 'held Hz' is measured at the game's own %.0f Hz and is distortion-free:"
			% _pps)
	print("[swarm] below %.0f the machine is already losing. 'capacity' lifts the pacing and"
			% _pps)
	print("[swarm] reads how many ticks/s this scene can actually supply; 'headroom' is that")
	print("[swarm] over %.0f. A capacity at the %d Hz probe ceiling reads as '>='."
			% [_pps, PROBE_HZ])
	print("[swarm] %5s %6s %7s %7s %8s %9s %9s %10s %9s"
			% ["N", "nodes", "bodies", "pairs", "live-rnd", "dropped%",
			"held Hz", "capacity", "headroom"])
	for row: Dictionary in rows:
		var fired: int = int(row["fired"])
		var dropped: int = int(row["dropped"])
		var drop_pct: float = 100.0 * float(dropped) \
				/ float(maxi(fired + dropped, 1))
		var capped: String = ">=" if row["probe_capped"] else "  "
		print("[swarm] %5d %6d %7.0f %7.0f %8d %8.1f%% %9.1f %s%8.0f %s%7.1fx"
				% [int(row["count"]), int(row["nodes"]),
				row["active_bodies"], row["pairs"],
				int(row["live_projectiles"]), drop_pct,
				row["realtime_hz"], capped, row["capacity_hz"],
				capped, float(row["capacity_hz"]) / _pps])
	var wall: String = "not reached in this sweep (max N = %d, still %.1fx headroom)" \
			% [int(rows[-1]["count"]), float(rows[-1]["capacity_hz"]) / _pps]
	for row: Dictionary in rows:
		if float(row["capacity_hz"]) < _pps:
			wall = "N = %d (capacity %.0f Hz, %.2fx — the tick no longer fits)" \
					% [int(row["count"]), float(row["capacity_hz"]),
					float(row["capacity_hz"]) / _pps]
			break
	print("[swarm] CPU WALL: %s" % wall)
	var margin: String = "none of these cells lost real time"
	for row: Dictionary in rows:
		if float(row["realtime_hz"]) < _pps * 0.98:
			margin = "N = %d already ran at %.0f Hz instead of %.0f" \
					% [int(row["count"]), float(row["realtime_hz"]), _pps]
			break
	print("[swarm] AT THE GAME'S OWN TICK RATE: %s" % margin)
	var pool_wall: String = "not reached"
	for row: Dictionary in rows:
		if int(row["dropped"]) > 0:
			pool_wall = "N = %d (%d of %d rounds dropped)" % [int(row["count"]),
					int(row["dropped"]), int(row["dropped"]) + int(row["fired"])]
			break
	print("[swarm] PROJECTILE-POOL WALL (%d rounds, shared by everything that shoots): %s"
			% [ProjectilePool.POOL_SIZE, pool_wall])
	if not _watching:
		print("[swarm] draw calls: 0 (headless). Re-run without --headless for the render cost.")
	else:
		print("[swarm] draw calls in the last frame of each cell: %s"
				% ", ".join(rows.map(func(r: Dictionary) -> String:
						return "%d:%d" % [int(r["count"]), int(r["draw_calls"])])))


func _report_kill() -> void:
	var rows: Array[Dictionary] = _rows("kill")
	if rows.is_empty():
		return
	print("")
	print("[swarm] ==== B. COMBAT VIABILITY — can N raiders hurt one frame? ====")
	print("[swarm] The target holds a hover and does NOT evade, and does not shoot back")
	print("[swarm] (see the header): this is the swarm's ceiling, not a duel.")
	print("[swarm] 'cone' is the GEOMETRIC prediction — the share of a raider's 3 deg jitter")
	print("[swarm] cone this frame's cross-section fills at its 18 m orbit, arithmetic only.")
	print("[swarm] %8s %4s %9s %10s %8s %9s %6s %7s %8s %6s"
			% ["frame", "N", "killed", "under fire", "dmg/s", "dmg/s/unit",
			"hits", "fired", "connect", "cone"])
	for row: Dictionary in rows:
		var under_fire: float = float(row["under_fire"])
		var dps: float = float(row["damage"]) / maxf(under_fire, 1.0 / _pps)
		var connect: float = float(row["hits"]) / float(maxi(int(row["fired"]), 1))
		print("[swarm] %8s %4d %9s %9.1fs %8.1f %9.1f %6d %7d %7.1f%% %5.1f%%"
				% [row["frame"], int(row["count"]),
				"yes" if row["killed"] else "SURVIVED", under_fire, dps,
				dps / float(int(row["count"])),
				int(row["hits"]), int(row["fired"]), connect * 100.0,
				_cone_fill(String(row["frame"])) * 100.0])
	print("[swarm] 'under fire' is measured from the FIRST hit, so the ingress is excluded;")
	print("[swarm] every cell also spent ~%.1f s closing from %.0f m first."
			% [_mean_first_hit(rows), SPAWN_RADIUS])
	print("[swarm] READ 'connect' AT THE SMALLEST N. Rounds still in flight when the target")
	print("[swarm] dies count as fired and never as hits, so a fast kill deflates the rate;")
	print("[swarm] the long fights at N=%d are the honest sample." % KILL_COUNTS[0])
	print("[swarm] READ 'dmg/s/unit' FOR THE SWARM QUESTION: if it falls as N rises, the")
	print("[swarm] swarm is getting in its own way and more bodies buy less than they cost.")
	print("[swarm] THE CONE COLUMN IS AN ORBIT-ONLY PREDICTION and is expected to sit ABOVE")
	print("[swarm] the measured rate: a raider opens fire the moment it has line of sight at")
	print("[swarm] %.0f m, where the same cone is %.1fx wider, and those long shots are"
			% [SPAWN_RADIUS, SPAWN_RADIUS / 19.8])
	print("[swarm] counted. The gap is the instrument's output — it names the ingress, the")
	print("[swarm] rounds in flight at death, and the swarm blocking its own line of sight.")


## What fraction of a raider's jitter cone this frame's frontal cross-section
## covers, at the raider's preferred orbit range. Arithmetic only — the Layer-1
## style prediction that table B's measured connect rate is checked against.
##
## `EnemyDrone._jitter` deflects by `tan(aim_jitter_deg) * randf()` on a random
## azimuth, so the miss point at range r is UNIFORM IN RADIUS on [0, r*tan(j)]
## and uniform in azimuth — not uniform in area. Two consequences, and both are
## why this is worth computing rather than eyeballing:
##
##  - The chance of connecting is LINEAR in the target's size, not quadratic. A
##    frame ten times wider is ten times easier to hit, not a hundred.
##  - The shape matters, not just the area. For a fixed azimuth the round lands
##    inside if its radius is under the distance from the centre to the hull's
##    edge in that direction, so the answer is the mean of `min(1, R(theta)/C)`
##    over a full turn. An airframe is a WIDE, FLAT box (`body_m` across,
##    `body_m * 0.2857` tall), so it fills the cone completely across and barely
##    at all vertically. Reducing it to a disc of equal area — the first version
##    of this function — predicted 99% for the Roc against a measured 52%,
##    because it silently traded the height it does not have for width it cannot
##    use.
func _cone_fill(frame_id: String) -> float:
	var config: FlightConfig = Frames.config(frame_id).flight_config
	var enemy: EnemyConfig = load(RAIDER_CONFIG) as EnemyConfig
	# The collider FlightController._apply_frame_geometry builds, plus the round's
	# own half-width: a shot grazing the hull still connects, and at Kestrel scale
	# that is a third of the target's own half-height.
	var half_w: float = config.body_m * 0.5 + ROUND_HALF_M
	var half_h: float = config.body_m * FlightController.BODY_HEIGHT_RATIO * 0.5 \
			+ ROUND_HALF_M
	# THE TRUE STANDOFF, not `preferred_range`. `EnemyDrone._orbit_point` holds
	# the preferred range RADIALLY and then adds a tangential slide and 2 m of
	# lift, so the actual shooting distance is the diagonal of the three — 19.8 m
	# against a nominal 18. A 10% error in range is a 10% error in the cone, and
	# reading the enemy's own geometry costs one line.
	var standoff: float = Vector3(enemy.preferred_range,
			2.0, EnemyDrone.ORBIT_TANGENT_BIAS).length()
	var cone: float = standoff * tan(deg_to_rad(enemy.aim_jitter_deg))
	var samples: int = 256
	var total: float = 0.0
	for i: int in samples:
		var theta: float = TAU * (float(i) + 0.5) / float(samples)
		var reach: float = minf(half_w / maxf(absf(cos(theta)), 0.000001),
				half_h / maxf(absf(sin(theta)), 0.000001))
		total += minf(reach / maxf(cone, 0.000001), 1.0)
	return total / float(samples)


func _mean_first_hit(rows: Array[Dictionary]) -> float:
	var total: float = 0.0
	for row: Dictionary in rows:
		total += float(row["first_hit"])
	return total / float(maxi(rows.size(), 1))


func _rows(mode: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _results:
		if row["mode"] == mode:
			out.append(row)
	return out


## THE ANTI-DELETION ASSERTS. Every one of these exists because the failure it
## refuses looks exactly like a pass in the table above.
##
## "Would this still pass if the feature were deleted?" A load bench reporting a
## comfortable 0.2 ms/tick because nothing spawned, or because everything
## despawned before the window, is the exact shape this project has been bitten
## by — and it is indistinguishable from a genuinely cheap simulation unless
## somebody asserts that the units are there AND fighting.
func _check() -> void:
	for row: Dictionary in _rows("load"):
		if int(row["alive"]) != int(row["count"]):
			_failures.append("%s: %d of %d raiders survived the window — the load cell measured fewer bodies than it says"
					% [row["name"], int(row["alive"]), int(row["count"])])
		if int(row["fired"]) <= 0:
			_failures.append("%s: nobody fired a round — the cell measured %d idle bodies, not a fight"
					% [row["name"], int(row["count"])])
		if row["active_bodies"] < float(row["count"]):
			_failures.append("%s: physics reports %.0f active bodies for %d raiders + 1 drone — bodies are asleep and the cost is not being paid"
					% [row["name"], row["active_bodies"], int(row["count"])])
	# The load sweep must actually SWEEP: if the largest cell costs the same as
	# the smallest, the counts are not reaching the simulation and the whole
	# table is a constant wearing a gradient's clothes.
	#
	# THIS IS THE ASSERT THAT CAUGHT THE FIRST INSTRUMENT. Wall-clock per tick
	# read 4.169 ms at every N, which this sentence refuses — and refusing it is
	# what sent the measurement back to be rebuilt instead of published.
	var load_rows: Array[Dictionary] = _rows("load")
	if load_rows.size() >= 2:
		var cheapest: float = float(load_rows[0]["ms_per_tick"])
		var dearest: float = float(load_rows[-1]["ms_per_tick"])
		if dearest <= cheapest * 1.5:
			_failures.append("load sweep is flat: N=%d costs %.4f ms/tick and N=%d costs %.4f — a %dx unit count that does not cost more means either the units are not in the simulation or the instrument is measuring the clock"
					% [int(load_rows[0]["count"]), cheapest,
					int(load_rows[-1]["count"]), dearest,
					int(load_rows[-1]["count"]) / maxi(int(load_rows[0]["count"]), 1)])

	# THE BORING FAILURE, and the one the harness historically cannot see: nobody
	# can hurt anybody. A cell where the swarm lands nothing reads as "the frame
	# is tough" and is really "the fight never happened".
	for row: Dictionary in _rows("kill"):
		if int(row["fired"]) <= 0:
			_failures.append("%s: the swarm fired nothing in %.0f s — stalled, not survived"
					% [row["name"], KILL_CAP_S])
		elif int(row["hits"]) <= 0:
			_failures.append("%s: %d rounds fired and NOTHING connected — this cell is a stall, and a stall reads identically to a tough frame"
					% [row["name"], int(row["fired"])])
	# The question the user actually asked. Ten small units against the heavy
	# frame is the roster's founding assumption, so it fails the board rather
	# than printing quietly.
	for row: Dictionary in _rows("kill"):
		if String(row["frame"]) == Frames.ROC and int(row["count"]) == 10:
			if not row["killed"]:
				_failures.append("L.q2's premise is FALSE as measured: 10 raiders could not kill a stationary Roc inside %.0f s (%.0f of %.0f hull taken) — the size-class roster is designed on this being possible"
						% [KILL_CAP_S, float(row["damage"]),
						float(row["hull"])])
