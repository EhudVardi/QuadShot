extends Node3D

## THE HUMAN AIM DRILL (GAMEPLAY-DESIGN H.q4, built v1.36) — an INTERACTIVE
## bench, not a headless check: the human flies it, the instrument watches.
##
## It measures the human's `aim_quality` on the SAME ruler as the reference
## pilot's aim cells (delivery_bench.gd): the same static immortal raider with
## the real hitbox, the same 40 m spawn offset, the same per-weapon windows
## (blaster 20 s, missile 45 s, flak 40 s), the same definition — hits per
## shot FIRED, window opening at that weapon's first shot. Fly it with the
## config you actually fly; the artifact records what was flown.
##
## WHAT THE RESULT IS (H5, BALANCE.md): DEVIATION DATA. It is written to
## user://blackbox/aim_drill_<stamp>.json — never into
## balance/delivery_factors.json, never into the base table. It tells us how
## a human deviates from the pinned reference datum; the table keeps speaking
## with the bot's numbers until a human band is quoted BY NAME as a human's.
##
## Run: <godot> --path . scenes/aim_drill.tscn        (add `-- --frame atlas`
## to fly the drill on the Atlas; the artifact records the frame either way.)
##
## Protocol, as the HUD narrates it: arm, fire at the raider. Each weapon's
## window starts at its own first shot and its rate freezes at window end
## (plus a grace for shells already in the air — hold fire when told, or the
## stragglers you keep firing add noise). Every completed cell rewrites the
## artifact, so a partial drill still records what it measured.

const RANGE_M: float = 40.0
const TARGET_ALTITUDE: float = 14.0
## Per-weapon windows, seconds — the delivery bench's own, verbatim.
const WINDOWS: Dictionary = {"blaster": 20.0, "missile": 45.0, "flak": 40.0}

## Signal leash (B5, v1.40) — same contract as main.gd: stray past WARN and
## the HUD nags, past LOST and the menu tower catches you.
const RANGE_WARN_M: float = 220.0
const RANGE_LOST_M: float = 300.0
const RANGE_WARN_PERIOD_S: float = 1.5
const MENU_SCENE: String = "res://scenes/menu_tower.tscn"

@export var combat_config: CombatConfig
@export var input_bindings: InputBindings

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _weapon: Weapon = $Drone/FpvCamera/Weapon
@onready var _missiles: MissileSystem = $Drone/FpvCamera/MissileSystem
@onready var _flak: FlakPod = $Drone/FpvCamera/FlakPod
@onready var _hud: GameHud = $Hud

var _target: Node3D
## weapon -> {start: float, shots: int, connects: int, done: bool,
##            closing: bool, close_at: float}
var _cells: Dictionary = {}
var _clock: float = 0.0
var _artifact_path: String = ""
var _titled: bool = true
var _range_warn_timer: float = 0.0
var _signal_lost: bool = false


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	if input_bindings != null:
		if input_bindings.load_from_user():
			print("[config] loaded %s" % input_bindings.save_path())
		input_bindings.apply()
	# No run, no draft: multipliers at 1.0 so shot damages are the config's own
	# numbers — which is also what connect attribution (below) relies on.
	RunMods.reset()
	for weapon: String in WINDOWS:
		_cells[weapon] = {"start": -1.0, "shots": 0, "connects": 0,
				"done": false, "closing": false, "close_at": 0.0}
	_spawn_target()
	_artifact_path = "user://blackbox/aim_drill_%s.json" % _stamp()
	_drone_health.damaged.connect(func(_amount: float, remaining: float) -> void:
			_hud.set_health(remaining, _drone_health.max_health))
	_drone_health.died.connect(_on_died)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_hud.show_title("AIM DRILL — arm and fire at the raider. Each weapon: its window starts on its first shot.")
	# Attribution guard: connects are told apart by their damage numbers, so
	# two weapons tuned to the SAME damage would be indistinguishable here.
	var damages: Array[float] = [combat_config.projectile_damage,
			combat_config.missile_damage, combat_config.flak_damage]
	for i: int in damages.size():
		for j: int in range(i + 1, damages.size()):
			if is_equal_approx(damages[i], damages[j]):
				push_warning("[drill] two weapons share damage %.1f — their connects cannot be told apart; retune before trusting this drill" % damages[i])
	print("[drill] ready — artifact will land at %s" % _artifact_path)


## The reference bench's static body, exactly: the real raider scene, immortal,
## immobilized, blind (sight_range 0 = never engages) — the hitbox is the
## point, and it is the same hitbox the bot was measured against.
func _spawn_target() -> void:
	var config: EnemyConfig = (load("res://resources/default_enemy_raider.tres")
			as EnemyConfig).duplicate() as EnemyConfig
	config.hull = 1.0e9
	config.speed = 0.0
	config.accel = 0.0
	config.sight_range = 0.0
	_target = (load("res://scenes/combat/enemy_drone.tscn") as PackedScene) \
			.instantiate() as Node3D
	_target.set(&"enemy_config", config)
	_target.set(&"ai_seed", 0)
	_target.position = Vector3(0.0, TARGET_ALTITUDE, -RANGE_M)
	add_child(_target)
	(_target.get_node("Health") as Health).struck.connect(_on_target_struck)


## Connect attribution by damage number: 25 is a bolt, 60 a missile, 10 a
## flak fragment — read from the LIVE config so a tuned value still matches
## the shot it priced. The flak count is cross-checked against the pod's own
## counter at cell close (the delivery bench's two-counter discipline).
func _on_target_struck(amount: float) -> void:
	var weapon: String = ""
	if is_equal_approx(amount, combat_config.projectile_damage):
		weapon = "blaster"
	elif is_equal_approx(amount, combat_config.missile_damage):
		weapon = "missile"
	elif is_equal_approx(amount, combat_config.flak_damage):
		weapon = "flak"
	else:
		return
	var cell: Dictionary = _cells[weapon]
	if cell["done"] or cell["start"] < 0.0:
		return
	cell["connects"] = int(cell["connects"]) + 1


func _physics_process(delta: float) -> void:
	_clock += delta
	if _drone.armed and _titled:
		_hud.hide_title()
		_titled = false
	_update_cell("blaster", _weapon.shots_fired)
	_update_cell("missile", _missiles.launches)
	_update_cell("flak", _flak.shots_fired)


func _process(delta: float) -> void:
	_update_reticle()
	_update_lock()
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])
	_update_signal_leash(delta)


func _update_signal_leash(delta: float) -> void:
	if _signal_lost:
		return
	var distance: float = _drone.global_position.length()
	if distance <= RANGE_WARN_M:
		_range_warn_timer = 0.0
		return
	if distance >= RANGE_LOST_M:
		_signal_lost = true
		_hud.add_kill_feed("SIGNAL LOST — returning to menu")
		get_tree().call_deferred(&"change_scene_to_file", MENU_SCENE)
		return
	_range_warn_timer -= delta
	if _range_warn_timer <= 0.0:
		_range_warn_timer = RANGE_WARN_PERIOD_S
		_hud.add_kill_feed("SIGNAL WEAK — %d m — turn back" % int(distance))


func _update_cell(weapon: String, fired_total: int) -> void:
	var cell: Dictionary = _cells[weapon]
	if cell["done"]:
		return
	var window: float = float(WINDOWS[weapon])
	if cell["start"] < 0.0:
		if fired_total > 0:
			cell["start"] = _clock
			_hud.add_kill_feed("%s: %d s window running" % [weapon.to_upper(),
					int(window)])
			print("[drill] %s window open" % weapon)
		return
	if not cell["closing"]:
		# Shots freeze at window end; connects keep counting through a grace
		# sized to the round's own lifetime, so in-flight shells land honestly.
		cell["shots"] = fired_total
		if _clock >= float(cell["start"]) + window:
			cell["closing"] = true
			cell["close_at"] = _clock + _grace(weapon)
			_hud.add_kill_feed("%s window over — HOLD FIRE (counting stragglers)"
					% weapon.to_upper())
	elif _clock >= float(cell["close_at"]):
		cell["done"] = true
		_finish_cell(weapon)


func _grace(weapon: String) -> float:
	match weapon:
		"missile":
			return combat_config.missile_lifetime
		"flak":
			return combat_config.flak_shell_lifetime
	return combat_config.projectile_lifetime


func _finish_cell(weapon: String) -> void:
	var cell: Dictionary = _cells[weapon]
	var shots: int = int(cell["shots"])
	var connects: int = int(cell["connects"])
	if weapon == "flak" and connects != _flak.bursts_connected:
		# Not a failure out here in human-land (stray shots after HOLD FIRE can
		# land past the grace) — but say it, per the two-counter discipline.
		print("[drill] note: flak struck-count %d vs pod count %d — stragglers or a counter bug"
				% [connects, _flak.bursts_connected])
	var rate: float = float(connects) / float(shots) if shots > 0 else 0.0
	_hud.add_kill_feed("%s AIM: %.2f (%d/%d)" % [weapon.to_upper(), rate,
			connects, shots])
	print("[drill] %s: %d shots, %d connects -> %.2f" % [weapon, shots,
			connects, rate])
	_write_artifact()
	for other: String in _cells:
		if not _cells[other]["done"]:
			return
	_hud.show_title("DRILL COMPLETE — results in the console and %s"
			% _artifact_path)
	_titled = true
	print("[drill] complete: %s" % _artifact_path)


## Rewritten after EVERY completed cell: a partial drill still records what it
## measured. Labeled deviation data (H5) — this file never feeds the table.
func _write_artifact() -> void:
	var cells: Dictionary = {}
	for weapon: String in _cells:
		var cell: Dictionary = _cells[weapon]
		if not cell["done"]:
			continue
		var shots: int = int(cell["shots"])
		cells[weapon] = {"shots": shots, "connects": int(cell["connects"]),
				"rate": snappedf(float(cell["connects"]) / float(shots), 0.01) \
						if shots > 0 else 0.0,
				"window_s": WINDOWS[weapon]}
	var payload: Dictionary = {
		"pilot": "human (H5 deviation data — never merged into the base table)",
		"date": Time.get_datetime_string_from_system(),
		"frame": String(_drone.frame.frame_id),
		"fire_assist_miss_m": combat_config.fire_assist_miss_m,
		"reference": "delivery_bench aim cells, pilot v%d ruler"
				% ReferencePilot.PILOT_VERSION,
		"cells": cells,
	}
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("user://blackbox"))
	var file: FileAccess = FileAccess.open(_artifact_path, FileAccess.WRITE)
	if file == null:
		push_warning("[drill] cannot write %s" % _artifact_path)
		return
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.close()


func _on_died() -> void:
	_hud.add_kill_feed("down — respawning (windows keep running)")
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_drone.reset_to_spawn()
			_drone_health.revive()
			_hud.set_health(_drone_health.current, _drone_health.max_health))


func _stamp() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system(false)
	return "%04d%02d%02d_%02d%02d%02d" % [now["year"], now["month"], now["day"],
			now["hour"], now["minute"], now["second"]]


# --- HUD mirrors of main.gd's reticle/lock blocks, via the same shared
# solver, so the drill's pipper is the game's pipper by construction. ---

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


func _update_lock() -> void:
	var target: Node3D = _missiles.target
	var camera: Camera3D = get_viewport().get_camera_3d()
	if target == null or not is_instance_valid(target) or camera == null \
			or camera.is_position_behind(target.global_position):
		_hud.update_lock(false)
		return
	_hud.update_lock(true, camera.unproject_position(target.global_position),
			_missiles.lock_progress, _missiles.is_locked(),
			_missiles.auto_hold_progress())
