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
## ARMOR PROBES. Flat armor landed with the Atlas (P3.3), whose armor sits on
## the PLAYER's frame — and Layer 1 never models being shot at, so no roster row
## exercises the new branch: every bestiary type is still `armor = 0.0`. Checking
## the code against those zeros would verify nothing at all, so these synthetic
## configs drive the three cases deliberately. They are PROBES, not roster
## members: nothing balances off them, they exist so the calculator and
## health.gd cannot drift on a rule the roster does not use yet.
##
##   raider+armor6   — plating that chips: every weapon still kills, slower.
##   raider+armor10  — plating at the flak burst's damage: kill-or-never, the
##                     same verdict shape as the aegis's shield threshold.
##   aegis+armor36   — armor UNDER a shield, sized so a carry-through is exactly
##                     swallowed by the plating while the full hit is not. That
##                     is the one combination where verdicting "never" on the
##                     carried sliver instead of the weapon's own damage looks
##                     right and is wrong: the screen is down, and the next hit
##                     lands whole. It killed at 21 s while an earlier draft of
##                     the calculator called it unkillable.
const ARMOR_PROBES: Array[Dictionary] = [
	{"enemy": "res://resources/default_enemy_raider.tres", "armor": 6.0},
	{"enemy": "res://resources/default_enemy_raider.tres", "armor": 10.0},
	{"enemy": "res://resources/default_enemy_aegis.tres", "armor": 36.0},
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
		# A shielded type is TWO targets in sequence (v1.25 state split), and
		# a weapon's answer can invert between them, so each state gets its
		# own verified row rather than one averaged cell.
		if enemy.shield_max > 0.0:
			_add_cells(enemy, "shielded", enemy)
			_add_cells(Lethality.cracked_config(enemy), "cracked", enemy)
		else:
			_add_cells(enemy, "", enemy)
	for probe: Dictionary in ARMOR_PROBES:
		var base: EnemyConfig = load(probe["enemy"]) as EnemyConfig
		var armored: EnemyConfig = base.duplicate() as EnemyConfig
		armored.armor = float(probe["armor"])
		_add_cells(armored, "armor%.0f" % armored.armor, base)
	print("[lethality] Layer 1 table (config arithmetic, %d cells):"
			% _cells.size())
	for cell: Dictionary in _cells:
		var p: Dictionary = cell["predicted"]
		var verdict: String = "NEVER (%s)" % p["why"] if not p["kills"] \
				else "%d hit%s, ttk %.1fs" % [p["shots"],
				"" if int(p["shots"]) == 1 else "s", p["ttk"]]
		print("[lethality]   %-8s x %-18s %s"
				% [cell["weapon"], cell["label"], verdict])
	_print_combos()
	_start_cell()
	physics_frame.connect(_on_physics_frame)


## `config` is what the planted shots actually run against (already stripped
## for a cracked row); `named` supplies the type_id for the label.
func _add_cells(config: EnemyConfig, state: String, named: EnemyConfig) -> void:
	var label: String = String(named.type_id)
	if state != "":
		label += "(%s)" % state
	for weapon: String in Lethality.WEAPONS:
		_cells.append({"enemy": config, "weapon": weapon, "label": label,
				"predicted": Lethality.versus(weapon, _combat, config)})


## The combo rows: what a two-weapon answer costs, computed from the state
## split rather than tabulated as a special case. Arithmetic only — no duel
## flies this — but it is what makes "missile strips, gun finishes" a
## PREDICTION instead of a surprise in the validation column.
func _print_combos() -> void:
	for enemy_path: String in ENEMIES:
		var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
		if enemy.shield_max <= 0.0:
			continue
		print("[lethality] combos vs %s (strip -> finish):" % enemy.type_id)
		for strip: String in Lethality.WEAPONS:
			for finish: String in Lethality.WEAPONS:
				var result: Dictionary = Lethality.combo(
						strip, finish, _combat, enemy)
				if not bool(result["kills"]):
					print("[lethality]   %-8s -> %-8s  no: %s"
							% [strip, finish, result["why"]])
					continue
				print("[lethality]   %-8s -> %-8s  %d + %d hits, ttk %.1fs"
						% [strip, finish, result["strip_shots"],
						result["finish_shots"], result["ttk"]])
				# SELF-CONSISTENCY: a combo that uses one weapon for both legs
				# is not a combo at all — it is that weapon's solo row, split
				# in two. If the two disagree, the combo's time accounting is
				# wrong (it was: the inter-leg cadence gap was missing).
				if strip != finish:
					continue
				var solo: Dictionary = Lethality.versus(strip, _combat, enemy)
				if int(result["shots"]) != int(solo["shots"]) \
						or absf(float(result["ttk"]) - float(solo["ttk"])) > 0.001:
					_failures.append(
							"%s->%s combo (%d hits, %.2fs) != %s solo (%d hits, %.2fs)"
							% [strip, finish, result["shots"], result["ttk"],
							strip, solo["shots"], solo["ttk"]])


func _start_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	var enemy: EnemyConfig = cell["enemy"]
	_health = Health.new()
	_health.max_health = enemy.hull
	root.add_child(_health)
	_health.configure_defenses(enemy)
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
		"flak":
			# One BODY's share of a burst. The pack yield lives in Layer 2, so
			# what gets planted here is a single fragment cloud's worth of damage
			# to a single target, at the pod's own cycle.
			_damage = _combat.flak_damage
			_hit_interval_ticks = maxi(
					int(roundf(pps / _combat.flak_fire_rate)), 1)
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
	var label: String = "%s x %s" % [cell["weapon"], cell["label"]]
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
