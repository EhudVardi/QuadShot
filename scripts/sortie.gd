extends Node3D

## Scene orchestration for a COMPOSED SORTIE (Iteration 12, W.q1).
##
## A separate scene from `main.tscn` on purpose, and the reasoning is steered:
## main owns the M4 run's whole lifecycle (arm -> waves -> exit gate -> draft ->
## death ends the run) and a campaign sortie differs at every step of it.
## `dev_map` and `city_map` are the standing precedent for scenes that mirror
## main's wiring rather than extending it. The duplication below is knowingly
## accepted; the shared plumbing (HUD feed, cameras, damage feedback) wants
## extracting once it is real rather than anticipated.
##
## WHAT IS DELIBERATELY ABSENT, and each absence is a later phase rather than an
## oversight: no ingress (W.q7 and the leash fight below), no pads spent from
## `spec["pads"]` (W.q4), no dares, no draft, no node selection UI. This scene
## exists to answer one question - does a sortie_spec become a fight a human can
## fly - and everything else is downstream of the answer.
##
## THE SIGNAL LEASH IS ANCHORED, NOT DISABLED (W9.1). The conflict was found in
## the build rather than on paper: `main.gd` drops the FPV link past 300 m FROM
## THE WORLD ORIGIN and yanks the pilot back to the menu tower, while a Strike
## now ENDS by deliberately flying away from the objective. A leash that fires
## during a successful egress reads as the game punishing you for winning.
##
## The fix is one line of framing rather than a new number: **the leash measures
## from the thing you are supposed to be near, not from the origin.** Anchored
## at the sortie's centre, the shipped radii need no retuning at all — egress
## completes at 105 m, comfortably inside the 220 m warning. Measuring from the
## origin was always the accident; the greybox arena simply happened to sit
## near it.
##
## That reframing is what Iteration 11's transit gate needs too (its far end is
## "somewhere else", not "too far"), and it is the third feature to trip one
## rule. Worth applying to `main.gd` the day something moves its arena.

@export var combat_config: CombatConfig
@export var input_bindings: InputBindings

## Which theater to fly. Overridable from the command line so a specific sortie
## can be re-flown exactly: `-- --seed 4242 --node 3`.
@export var theater_seed: int = 4242
## -1 picks the first slice-ready node, which is what "just show me one" means.
@export var node_id: int = -1
## Resume `user://war.save` if there is one (W7). `-- --fresh` starts over, and
## it is opt-in rather than default because silently overwriting somebody's
## campaign is not a thing to do by accident.
@export var persist: bool = true

## The FPV link's range, measured from the sortie's centre (see the header).
## Same numbers main flies with, because anchoring them correctly is what makes
## them fit rather than retuning them.
@export var signal_warn_m: float = 220.0
## 0 disables the leash entirely.
@export var signal_lost_m: float = 300.0
const RANGE_WARN_PERIOD_S: float = 1.5
const MENU_SCENE: String = "res://scenes/menu_tower.tscn"

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _chase_camera: Camera3D = $ChaseCamera
@onready var _hud: GameHud = $Hud
@onready var _runner: SortieRunner = $SortieRunner
@onready var _missiles: MissileSystem = $Drone/FpvCamera/MissileSystem
@onready var _weapon: Weapon = $Drone/FpvCamera/Weapon
@onready var _flak: FlakPod = $Drone/FpvCamera/FlakPod

var score: int = 0

var _spec: Dictionary = {}
var _state: Dictionary = {}
var _config: WarConfig
var _started: bool = false
var _range_warn_timer: float = 0.0
var _signal_lost: bool = false


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	_read_command_line()
	_compose()
	_runner.center = WaveDirector.ARENA_CENTER
	_runner.announced.connect(_hud.add_kill_feed)
	_runner.enemy_destroyed.connect(_on_enemy_destroyed)
	_runner.egress_opened.connect(_on_egress_opened)
	_runner.sortie_finished.connect(_on_sortie_finished)
	_drone_health.damaged.connect(_on_player_damaged)
	_drone_health.died.connect(_on_player_died)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_hud.show_title(_briefing_line())


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"camera_toggle"):
		if _fpv_camera.current:
			_chase_camera.make_current()
		else:
			_fpv_camera.make_current()
	# Arming commits you to the sortie, exactly as it starts a run in main.
	if not _started and _drone.armed and _drone_health.alive:
		_start()
	_hud.set_heat(_weapon.heat_fraction(), _weapon.overheated)
	_hud.set_ammo(-1 if _flak.unlimited() else _flak.rounds,
			-1 if _missiles.unlimited() else _missiles.rounds)
	_update_lock_indicator()
	_update_reticle()
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])
	_update_signal_leash(_delta)


## ---------- the sortie ----------

func _read_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			theater_seed = int(args[i + 1])
		elif args[i] == "--node" and i + 1 < args.size():
			node_id = int(args[i + 1])
		elif args[i] == "--fresh":
			WarSave.clear()
		elif args[i] == "--no-persist":
			persist = false


## Two evaluations of one function (P2.1) exist; this scene flies TRUTH. The
## briefing half (`compose_briefing`, the manifest through intel fog) belongs to
## the command room, which does not exist yet.
func _compose() -> void:
	_config = WarConfig.new()
	# Resume the campaign if one exists, so consecutive sorties are a WAR and
	# not a series of unrelated levels. That is the whole of W7.
	_state = WarSave.load_or_new(_config, theater_seed) if persist \
			else TheaterGenerator.generate(_config, theater_seed)
	if persist and WarSave.exists():
		print("[war] resumed tick %d, %d pilots, %d sorties flown"
				% [int(_state["tick"]), int(_state["pilots"]), int(_state["sorties"])])
	var chosen: Dictionary = {}
	for node: Dictionary in _state["nodes"]:
		if node_id >= 0 and int(node["id"]) != node_id:
			continue
		var spec: Dictionary = SortieComposer.compose(node, _state, _config)
		if not SortieComposer.is_slice_ready(spec):
			continue
		chosen = spec
		break
	if chosen.is_empty():
		push_warning("[sortie] no slice-ready node matched; falling back to the first")
		for node: Dictionary in _state["nodes"]:
			var spec: Dictionary = SortieComposer.compose(node, _state, _config)
			if SortieComposer.is_slice_ready(spec):
				chosen = spec
				break
	_spec = chosen
	_print_briefing()


func _print_briefing() -> void:
	if _spec.is_empty():
		print("[sortie] the theater produced nothing this slice can build")
		return
	print("[sortie] seed %d, node %d (%s / %s, %s)"
			% [theater_seed, int(_spec["node_id"]), _spec["node_type"],
			_spec["biome"], _spec["weather"]])
	print("[sortie]   %s: %s%s" % [String(_spec["archetype"]).to_upper(),
			String(_spec["objective"]).replace("_", " "),
			"" if int(_spec["objective_assets"]) == 0
					else " x%d" % int(_spec["objective_assets"])])
	for layer: StringName in SortieComposer.LAYER_ORDER:
		var parts: PackedStringArray = []
		for unit: Dictionary in _spec["layers"][layer]:
			parts.append("%dx%s" % [int(unit["count"]), unit["type"]])
		if not parts.is_empty():
			print("[sortie]   %-6s %s" % [layer, " ".join(parts)])
	for trigger: Dictionary in _spec["triggers"]:
		var parts: PackedStringArray = []
		for unit: Dictionary in trigger["units"]:
			parts.append("%dx%s" % [int(unit["count"]), unit["type"]])
		print("[sortie]   reserve on %s after %.1fs: %s"
				% [trigger["on"], float(trigger["after_s"]), " ".join(parts)])
	print("[sortie]   the node is worth %.2f strength; capture=%s"
			% [SortieComposer.total_strength(_spec), _spec["capture"]])


func _start() -> void:
	if _spec.is_empty():
		return
	_started = true
	score = 0
	_hud.hide_title()
	_hud.set_score(0)
	_runner.start(_spec, _drone)


func _on_egress_opened() -> void:
	_hud.add_kill_feed("EGRESS - fly clear of the target area")


## THE LOOP HOME (W7). The result is priced back into the war, the war takes a
## turn, and the file is written. Before this, a sortie was a level.
func _on_sortie_finished(result: Dictionary) -> void:
	print("[sortie] FINISHED  %s  objective %d/%d  egressed=%s"
			% [result["outcome"], int(result["objectives_destroyed"]),
			int(result["objective_assets"]), result["egressed"]])
	print("[sortie]   kills %s" % result["kills"])

	var summary: Dictionary = WarSim.apply_sortie(_state, _config, result)
	if summary.is_empty():
		push_warning("[war] the node this sortie was composed from is gone")
		return
	print("[war] node %d (%s): garrison %.2f -> %.2f (dent %.2f)%s"
			% [int(summary["node_id"]), summary["node_type"],
			float(summary["garrison_before"]), float(summary["garrison_after"]),
			float(summary["dent"]),
			"  CAPTURED" if bool(summary["captured"])
					else ("  degraded" if bool(summary["degraded"]) else "")])

	# The war moves whether or not you did well. Passing no proxy skill means
	# the sim runs its own phases (production, supply, enemy operations,
	# weather, intel) WITHOUT inventing a second, abstract player sortie on top
	# of the real one you just flew - which would double-count you.
	WarSim.tick(_state, _config)
	print("[war] tick %d  pilots %d  %s"
			% [int(_state["tick"]), int(_state["pilots"]),
			"winner: %s" % _state["winner"] if _state["winner"] != &"" else "war continues"])
	if persist and WarSave.save(_state):
		print("[war] saved %s" % WarSave.PATH)

	var feed: String = "CAPTURED" if bool(summary["captured"]) \
			else "dented the node by %.1f" % float(summary["dent"])
	_hud.add_kill_feed("SORTIE %s - %s" % [String(result["outcome"]).to_upper(), feed])


func _on_enemy_destroyed(points: float) -> void:
	score += int(points)
	_hud.set_score(score)
	_hud.add_kill_feed("+%d" % int(points))


## ---------- the pilot ----------

func _on_player_damaged(amount: float, remaining: float) -> void:
	_drone.apply_hit_to_motors(amount)
	_hud.set_health(remaining, _drone_health.max_health)
	_hud.flash_damage(&"all")


func _on_player_died() -> void:
	Effects.explosion(get_tree().root, _drone.global_position, 1.6)
	_drone.disarm()
	_drone.visible = false
	_drone.set_deferred(&"freeze", true)
	_hud.show_death(true)
	# P2.q4's no-wasted-sortie, and it only works because the runner can finish
	# on a death: the node keeps whatever you broke on the way down, and the
	# pilot comes off the roster (F1).
	_runner.abort("pilot down")
	get_tree().create_timer(combat_config.respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	_drone.freeze = false
	_drone.reset_to_spawn()
	_drone_health.max_health = _drone.frame.hull
	_drone_health.revive()
	_drone.visible = true
	_hud.show_death(false)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_drone.repair_motors()


## The leash, measured from the sortie's CENTRE (see the header). An egress is
## leaving on purpose and must never trip it, so the distance that matters is
## "how far from the fight", not "how far from the origin".
func _update_signal_leash(delta: float) -> void:
	if _signal_lost or not _drone_health.alive or signal_lost_m <= 0.0:
		return
	var distance: float = _drone.global_position.distance_to(_runner.center)
	if distance <= signal_warn_m:
		_range_warn_timer = 0.0
		return
	if distance >= signal_lost_m:
		_signal_lost = true
		_hud.add_kill_feed("SIGNAL LOST - returning to menu")
		print("[sortie] signal lost at %.0f m from the target area" % distance)
		get_tree().call_deferred(&"change_scene_to_file", MENU_SCENE)
		return
	_range_warn_timer -= delta
	if _range_warn_timer <= 0.0:
		_range_warn_timer = RANGE_WARN_PERIOD_S
		_hud.add_kill_feed("SIGNAL WEAK - %d m - turn back" % int(distance))


func _update_reticle() -> void:
	var solution: Dictionary = ReticleSolver.solve(
			get_viewport().get_camera_3d(), _weapon, _drone, combat_config,
			_missiles, get_tree(), RunMods.current.lock_cone_mult)
	if solution.is_empty():
		_hud.clear_reticle()
		return
	_hud.update_reticle(solution["center"], solution["pipper"], solution["arc"],
			solution["ticks"], solution["lock_radius"], solution["hold_radius"],
			solution["lockable"])


func _update_lock_indicator() -> void:
	var target: Node3D = _missiles.target
	var camera: Camera3D = get_viewport().get_camera_3d()
	if target == null or not is_instance_valid(target) or camera == null \
			or camera.is_position_behind(target.global_position):
		_hud.update_lock(false)
		return
	_hud.update_lock(true, camera.unproject_position(target.global_position),
			_missiles.lock_progress, _missiles.is_locked(),
			_missiles.auto_hold_progress())


func _briefing_line() -> String:
	if _spec.is_empty():
		return "no flyable sortie for this seed"
	return "%s - %s - arm to begin" % [String(_spec["archetype"]).to_upper(),
			String(_spec["node_type"])]
