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
## oversight: no dares, no draft. This scene exists to answer one question - does
## a sortie_spec become a fight a human can fly - and everything else is
## downstream of the answer. Node selection is the war room's (C7); THE INGRESS
## IS BUILT (A6, `_place_at_ingress` below), which is what the two paragraphs
## below were written in anticipation of.
##
## `spec["pads"]` IS spent (W.q4, decided 2026-08-01) - the runner lays them, the
## repair gate comes first, and `sortie_check` asserts the count. This paragraph
## said otherwise for one commit, which is the same shape as a stale RED board:
## a comment that teaches the next reader a shipped feature is missing.
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
##
## THE INGRESS PAID THAT FORWARD RATHER THAN RE-OPENING IT (A6). A spawn 140-195 m
## out is the exact case the anchoring was worried about, and it needed no new
## number: the ingress band is chosen to sit inside `signal_warn_m` with room to
## drift, and `sortie_check` asserts the two against each other so a later tuning
## pass cannot separate them silently. The leash keeps its shipped radii.

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
const WAR_ROOM_SCENE: String = "res://scenes/war_room.tscn"
## Long enough to read the last kill feed line, short enough not to be a wait.
const RETURN_DELAY_S: float = 3.0

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
## The video feed's two wounds, exactly as `main.gd` keeps them: a decaying
## SPIKE from each hit, and permanent transmitter DAMAGE until a pad patches it.
var _video_glitch_spike: float = 0.0
var _video_damage: float = 0.0


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	_read_command_line()
	_compose()
	_runner.center = WaveDirector.ARENA_CENTER
	_place_at_ingress()
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
	_update_video_feed(_delta)


## ---------- the sortie ----------

func _read_command_line() -> void:
	# A launch from the war room outranks the command line, because the room is
	# the campaign and the flags are a repro tool.
	if WarLaunch.from_room:
		theater_seed = WarLaunch.theater_seed
		node_id = WarLaunch.node_id
		persist = WarLaunch.persist
		return
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
	if _state.is_empty():
		# Only reachable when a save is unreadable AND could not be moved aside.
		# Flying nothing beats overwriting a campaign we could not read.
		push_error("[war] no war state - refusing to start a sortie over an unreadable save")
		persist = false
		return
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
	if chosen.is_empty() and node_id >= 0:
		# AN EXPLICIT --node IS A REQUEST, NOT A HINT. Quietly flying a different
		# node and printing its id in the briefing is how a measurement ends up
		# attributed to the wrong target; the pilot reads "node 8" in their own
		# command line and "node 3" three lines later, if they look at all.
		var ready: PackedStringArray = []
		for node: Dictionary in _state["nodes"]:
			if SortieComposer.is_slice_ready(
					SortieComposer.compose(node, _state, _config)):
				ready.append(str(int(node["id"])))
		push_error("[sortie] node %d is not slice-ready for seed %d - refusing to fly a different one. Slice-ready nodes: %s"
				% [node_id, theater_seed, ", ".join(ready)])
		print("[sortie] node %d is not slice-ready for seed %d." % [node_id, theater_seed])
		print("[sortie] slice-ready nodes this seed: %s" % ", ".join(ready))
	elif chosen.is_empty():
		# No node was asked for, so "just show me one" is the whole request.
		for node: Dictionary in _state["nodes"]:
			var spec: Dictionary = SortieComposer.compose(node, _state, _config)
			if SortieComposer.is_slice_ready(spec):
				chosen = spec
				break
	_spec = chosen
	_print_briefing()


## THE INGRESS (Iteration 14 / A6, W.q7). The drone is taken off the scene's
## spawn pad and put down outside the target area, on the bearing the spec
## carries, facing what it came to hit — BEFORE the pilot arms, so the first
## thing they ever see of a sortie is the target area from the outside.
##
## This is what the scene header used to call a deliberate absence. It was: the
## pilot started in the middle of the rings, which is why a garrison could be
## fully placed and still engage nobody, and why v2.12 needed a clamp to
## compensate. The clamp is gone with it.
##
## The pad follows the drone, so the ingress reads as a forward position rather
## than as a quad abandoned in a field. Null-guarded because a scene is allowed
## to not have one.
func _place_at_ingress() -> void:
	if _spec.is_empty():
		return
	var at: Transform3D = SortieRunner.ingress_transform(_spec, _runner.center)
	_drone.place_at(at)
	var pad: Node3D = get_node_or_null("Greybox/SpawnPad")
	if pad != null:
		pad.global_position = Vector3(at.origin.x, pad.global_position.y, at.origin.z)


## `bearing_deg` as a direction you can fly rather than a number you have to
## convert. The ingress bearing is where YOU are relative to the target, so "from
## the SE" is the phrasing that matches it.
func _compass(bearing_deg: float) -> String:
	const POINTS: PackedStringArray = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return POINTS[int(round(fposmod(bearing_deg, 360.0) / 45.0)) % 8]


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
	# The approach (P2.4 / A6). `ingress_m` is printed in the composer's own
	# fiction units NEXT TO the metres the arena actually gives you, because the
	# two differ on purpose (SortieRunner's ingress header) and a briefing that
	# showed only one of them would make the other look like a bug.
	#
	# `corridors` and `cover` are printed and NOT yet flown: a corridor is a lane
	# through terrain, and the greybox has no terrain past the arena. They are
	# here so the number a biome generator will eventually have to honour is
	# visible now rather than discovered later.
	var approach: Dictionary = _spec["approach"]
	print("[sortie]   ingress: %d m from the %s (bearing %d), %d corridor(s), cover %.2f%s"
			% [int(round(SortieRunner.ingress_range(_spec))),
			_compass(float(approach["bearing_deg"])), int(approach["bearing_deg"]),
			int(approach["corridors"]), float(approach["cover"]),
			"  [spec says %d m of open ground]" % int(approach["ingress_m"])])
	# The pad count is the pilot's single most important planning fact, and it is
	# derived rather than authored: a heavily garrisoned node earns zero, which
	# is P2.6's difficulty knob showing its working.
	var pads: int = int(_spec["pads"])
	print("[sortie]   pads: %s" % ("NONE - no repair, no resupply" if pads == 0
			else "%d (repair first, then resupply)" % pads))
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
	_wire_pads()


## A repair gate fixes the motors itself; the HUD has to be told, or a pilot who
## just got their engines back has no way to know it worked.
##
## Read off `runner.pads` rather than off `SceneTree.node_added`. The hook version
## ran a GDScript callback for EVERY node added anywhere in the tree - every
## impact spark, every explosion, every spawned enemy, for the whole sortie - to
## catch the one or two gates that `start()` had already put in a public array
## synchronously.
func _wire_pads() -> void:
	for pad: Node3D in _runner.pads:
		if pad is RepairGate:
			(pad as RepairGate).repaired.connect(_on_repaired)


## A repair gate patches the airframe, and the transmitter is part of it (D5,
## v1.41) — so the feed clears with the motors rather than carrying a wound the
## pad just paid for.
func _on_repaired() -> void:
	_video_damage = 0.0
	_video_glitch_spike = 0.0
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_hud.flash_engines_restored()
	_hud.add_kill_feed("ENGINES RESTORED")


func _on_egress_opened() -> void:
	_hud.add_kill_feed("EGRESS - fly clear of the target area")


## THE LOOP HOME (W7), now with two legs (Iteration 13, C7).
##
## LAUNCHED FROM THE WAR ROOM: the result is handed back and the ROOM applies it,
## ticks and saves, because P1.8's sequence puts the tick where the map is.
##
## BOOTED DIRECTLY: this scene resolves the war itself, exactly as it did before
## the room existed. That leg is TESTING.md's repro command and it must not rot,
## which is why `war_room_check` exercises both and not just the new one.
func _on_sortie_finished(result: Dictionary) -> void:
	print("[sortie] FINISHED  %s  objective %d/%d  egressed=%s"
			% [result["outcome"], int(result["objectives_destroyed"]),
			int(result["objective_assets"]), result["egressed"]])
	print("[sortie]   kills %s" % result["kills"])

	WarLaunch.result = result
	WarLaunch.flew = true
	if WarLaunch.from_room:
		_hud.add_kill_feed("RETURNING TO THE WAR ROOM")
		get_tree().create_timer(RETURN_DELAY_S).timeout.connect(_return_to_room)
		return
	_resolve_standalone(result)


func _resolve_standalone(result: Dictionary) -> void:
	var debrief: Dictionary = WarDebrief.resolve(_state, _config, result)
	if debrief.is_empty():
		return
	for line: String in WarDebrief.lines(debrief):
		print("[war] %s" % line)
	if persist and WarSave.save(_state):
		print("[war] saved %s" % WarSave.PATH)

	var summary: Dictionary = debrief["summary"]
	var feed: String = "CAPTURED" if bool(summary["captured"]) \
			else "dented the node by %.1f" % float(summary["dent"])
	_hud.add_kill_feed("SORTIE %s - %s" % [String(result["outcome"]).to_upper(), feed])


func _return_to_room() -> void:
	get_tree().change_scene_to_file(WAR_ROOM_SCENE)


func _on_enemy_destroyed(points: float) -> void:
	score += int(points)
	_hud.set_score(score)
	_hud.add_kill_feed("+%d" % int(points))


## ---------- the pilot ----------

func _on_player_damaged(amount: float, remaining: float) -> void:
	_drone.apply_hit_to_motors(amount)
	var dc: DamageConfig = _drone.damage_config
	if dc != null and dc.severity > 0.0:
		var bite: float = clampf(amount / maxf(_drone_health.max_health, 1.0) * 4.0,
				0.0, 1.0)
		var spike: float = dc.video_glitch_on_hit * dc.severity * (0.7 + 0.6 * bite)
		_video_glitch_spike = clampf(maxf(_video_glitch_spike, spike), 0.0, 1.0)
		_video_damage = clampf(_video_damage
				+ amount / maxf(_drone_health.max_health, 1.0)
				* dc.video_damage_scale * dc.severity, 0.0, 1.0)
	_hud.set_health(remaining, _drone_health.max_health)
	_hud.flash_damage(&"all")


## THE FEED, WHICH THIS SCENE HAS NEVER HAD (reported by the user flying a
## campaign: *"the screamers... the vtx does not get distorted"*).
##
## `main.gd` has run this since v1.41 and `sortie.gd` was written without it, so
## a composed sortie has been silently missing BOTH halves of D6: battle damage
## never degraded the picture, and a screamer's jam — which the missile lock and
## the gun director were obeying the whole time — had no way to announce itself.
## The EW was working and invisible, which is the worst combination available:
## the pilot experiences an unexplained failure to lock and concludes the feature
## is broken.
##
## The jam is a FLOOR rather than an addition, like the other two sources:
## whichever failure is worst right now is the one you are looking at (D6 —
## EW and battle damage are one mechanism on screen).
##
## Duplicated from `main.gd` rather than extracted, deliberately and with a debt
## recorded: the extraction wants doing when the third consumer arrives, and
## doing it right now would mean refactoring the shipped arcade mode in the same
## change as a bug fix the user is waiting on.
func _update_video_feed(delta: float) -> void:
	var dc: DamageConfig = _drone.damage_config
	if dc == null:
		return
	_video_glitch_spike = maxf(_video_glitch_spike - dc.video_glitch_decay * delta, 0.0)
	var sustained: float = 0.0
	if _drone_health.alive and _video_damage > 0.0:
		sustained = dc.video_glitch_sustained * _video_damage
		if randf() < dc.video_flicker_rate * _video_damage * delta:
			var burst: float = dc.video_flicker_strength * _video_damage \
					* randf_range(0.6, 1.0)
			_video_glitch_spike = clampf(maxf(_video_glitch_spike, burst), 0.0, 1.0)
	var jam_wash: float = 0.0
	if _drone_health.alive:
		jam_wash = Jamming.level_at(_drone) * dc.jam_video_glitch
	_hud.set_video_glitch(maxf(maxf(_video_glitch_spike, sustained), jam_wash))


## DEATH ENDS THE SORTIE. There is no respawn, and its absence is the fix
## (P5.4, and the gap v2.02 deliberately left unplastered until there was a room
## to redeploy from).
##
## The arcade respawn this scene inherited from `main.gd` revived the pilot into
## a sortie that had ALREADY resolved and saved, where they could fly and kill
## indefinitely with nothing recorded — the war had heard the whole story and the
## pilot was still flying it. P5.4's answer was always "you redeploy fresh from
## Home Airbase", and Home Airbase now exists.
func _on_player_died() -> void:
	Effects.explosion(get_tree().root, _drone.global_position, 1.6)
	_drone.disarm()
	_drone.visible = false
	_drone.set_deferred(&"freeze", true)
	_hud.show_death(true)
	# P2.q4's no-wasted-sortie, and it only works because the runner can finish
	# on a death: the node keeps whatever you broke on the way down, and the
	# pilot comes off the roster (F1). `abort` emits `sortie_finished`, so the
	# result reaches the war down the same path a successful egress uses.
	_runner.abort("pilot down")
	if not WarLaunch.from_room:
		# Booted directly there is nowhere to redeploy TO, so the repro scene
		# returns to the menu rather than leaving a corpse on a resolved field.
		get_tree().create_timer(combat_config.respawn_delay).timeout.connect(
				func() -> void: get_tree().change_scene_to_file(MENU_SCENE))


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
		# Flying out of contact hands back NOTHING, which is P1.q4's "exit
		# without save" arriving by the honest route: the war reverts to its last
		# saved state because nothing was ever resolved into it.
		_hud.add_kill_feed("SIGNAL LOST - returning")
		print("[sortie] signal lost at %.0f m from the target area" % distance)
		get_tree().call_deferred(&"change_scene_to_file",
				WAR_ROOM_SCENE if WarLaunch.from_room else MENU_SCENE)
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


## The title card, which is now also the only navigation the pilot gets: the
## drone is pointed at the target, so "it is straight ahead, this far" is the
## whole brief. Deliberately not a HUD waypoint marker — finding the target area
## by looking at it is the first decision of P2.4's approach.
func _briefing_line() -> String:
	if _spec.is_empty():
		return "no flyable sortie for this seed"
	return "%s - %s - target %d m ahead - arm to begin" % [
			String(_spec["archetype"]).to_upper(), String(_spec["node_type"]),
			int(round(SortieRunner.ingress_range(_spec)))]
