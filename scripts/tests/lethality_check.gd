extends SceneTree

## Planted-shot verification of the Layer 1 lethality calculator
## (GAMEPLAY-DESIGN v1.23 Phase 3.5 step 2, BALANCE.md).
##
## The calculator (scripts/balance/lethality.gd) REPLAYS Health.take in
## arithmetic; this bench makes sure the replay and the shipped code never
## drift apart. For every default enemy config x every player weapon it
## plants hits directly into a REAL Health node at the weapon's own cadence —
## no drone, no pilot, no projectiles, no aim, so nothing about delivery can
## leak in — and compares what actually happened (killed or not, hits to
## kill, time to kill) against the calculator's prediction.
##
## A mismatch means one of two things, both worth failing the run for: the
## calculator no longer mirrors health.gd (fix the calculator), or a damage-
## pipeline change landed without its arithmetic (fix the model — and reread
## BALANCE.md first).
##
## Run: <godot> --headless -s scripts/tests/lethality_check.gd --path .

const ENEMIES: Array[String] = [
	"res://resources/default_enemy_raider.tres",
	"res://resources/default_enemy_turret.tres",
	"res://resources/default_enemy_gnat.tres",
	"res://resources/default_enemy_aegis.tres",
]
## Sim cap per cell. A predicted-never cell must survive this long under
## sustained planted fire to count as verified-never; the longest predicted
## kill (missile x aegis, 6 s) fits several times over.
const MAX_SECONDS: float = 30.0
## Hit-count timing tolerance, physics ticks: the sim quantizes the cadence
## to the tick grid and regen order-of-operations within a tick can differ
## from the calculator's continuous credit by one tick either side.
const TTK_TOLERANCE_TICKS: int = 2

var _combat: CombatConfig
var _cells: Array[Dictionary] = []
var _cell_i: int = 0
var _failures: PackedStringArray = []

# Live cell state.
var _health: Health
var _ticks: int = 0
var _hit_interval_ticks: int = 0
var _damage: float = 0.0
var _hits_planted: int = 0
var _death_tick: int = -1
var _ticks_cap: int = 0


func _initialize() -> void:
	_combat = load("res://resources/default_combat_config.tres") as CombatConfig
	_ticks_cap = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	for enemy_path: String in ENEMIES:
		var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
		for weapon: String in Lethality.WEAPONS:
			_cells.append({"enemy": enemy, "weapon": weapon,
					"predicted": Lethality.versus(weapon, _combat, enemy)})
	print("[lethality] Layer 1 table (config arithmetic, %d cells):"
			% _cells.size())
	for cell: Dictionary in _cells:
		var p: Dictionary = cell["predicted"]
		var verdict: String = "NEVER (%s)" % p["why"] if not p["kills"] \
				else "%d hit%s, ttk %.1fs" % [p["shots"],
				"" if int(p["shots"]) == 1 else "s", p["ttk"]]
		print("[lethality]   %-8s x %-7s %s"
				% [cell["weapon"], (cell["enemy"] as EnemyConfig).type_id, verdict])
	_start_cell()
	physics_frame.connect(_on_physics_frame)


func _start_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	var enemy: EnemyConfig = cell["enemy"]
	_health = Health.new()
	_health.max_health = enemy.hull
	root.add_child(_health)
	_health.configure_shield(enemy)
	_health.died.connect(func() -> void: _death_tick = _ticks)
	var pps: float = float(Engine.physics_ticks_per_second)
	match cell["weapon"]:
		"blaster":
			_damage = _combat.projectile_damage
			_hit_interval_ticks = maxi(int(roundf(pps / _combat.fire_rate)), 1)
		"missile":
			_damage = _combat.missile_damage
			_hit_interval_ticks = maxi(
					int(roundf(pps * _combat.missile_cooldown)), 1)
	_ticks = 0
	_hits_planted = 0
	_death_tick = -1


func _on_physics_frame() -> void:
	if _health.alive and _ticks % _hit_interval_ticks == 0:
		_health.take(_damage)
		_hits_planted += 1
	_ticks += 1
	if _death_tick < 0 and _ticks < _ticks_cap:
		return
	_verify_cell()
	_health.queue_free()
	_cell_i += 1
	if _cell_i >= _cells.size():
		_report()
	else:
		_start_cell()


func _verify_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	var predicted: Dictionary = cell["predicted"]
	var label: String = "%s x %s" % [cell["weapon"],
			(cell["enemy"] as EnemyConfig).type_id]
	var killed: bool = _death_tick >= 0
	if killed != bool(predicted["kills"]):
		_failures.append("%s: predicted %s, planted shots %s (after %d hits)"
				% [label, "kill" if predicted["kills"] else "NEVER",
				"killed" if killed else "no kill", _hits_planted])
		return
	if not killed:
		print("[lethality]   verified %-18s never dies (%d hits absorbed)"
				% [label + ":", _hits_planted])
		return
	if _hits_planted != int(predicted["shots"]):
		_failures.append("%s: predicted %d hits, planted %d"
				% [label, predicted["shots"], _hits_planted])
		return
	var predicted_ticks: int = int(roundf(float(predicted["ttk"])
			* float(Engine.physics_ticks_per_second)))
	if absi(_death_tick - predicted_ticks) > TTK_TOLERANCE_TICKS:
		_failures.append("%s: predicted ttk %.2fs, planted death at %.2fs"
				% [label, predicted["ttk"],
				float(_death_tick) / float(Engine.physics_ticks_per_second)])
		return
	print("[lethality]   verified %-18s %d hits, death at %.1fs"
			% [label + ":", _hits_planted,
			float(_death_tick) / float(Engine.physics_ticks_per_second)])


func _report() -> void:
	if _failures.is_empty():
		print("[lethality] PASS — calculator matches Health.take on every cell")
		quit(0)
	else:
		for f: String in _failures:
			print("[lethality] FAIL: %s" % f)
		print("[lethality] FAIL")
		quit(1)
