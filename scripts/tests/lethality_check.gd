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
	"res://resources/default_enemy_falx.tres",
	# The screamer is a normal Layer 1 target (hull 30, no shield, no armor) even
	# though it is invisible to the layer in the other direction — it carries no
	# weapon, so `Lethality.incoming` reports mode `none` for it. Being boring here
	# is not a reason to leave it out: an unlisted type's stats drift without
	# anything noticing, which is the v1.27 rule.
	"res://resources/default_enemy_screamer.tres",
	# The Lance carries no gun (damage 0, fire_rate 0) and kills by CONTACT blast,
	# so `Lethality.incoming` reports mode `contact` for it — the gnat precedent.
	# Being unusual in that direction is exactly why it has to be listed: the
	# v1.27 rule is that an unlisted type's stats drift without anything noticing.
	"res://resources/default_enemy_lance.tres",
	# The heavy defender (A7). Its screen is DIRECTIONAL, which Layer 1 cannot
	# see — the calculator models `Health`, and `Health` applies a shield to
	# every hit. So these rows price the IN-ARC case, which is the worst one for
	# the player, and the gap to the harness is the arc. Listed anyway, because
	# the v1.27 rule is that an unlisted type's stats drift unnoticed.
	"res://resources/default_enemy_phalanx.tres",
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

## Sim cap for a predicted-NEVER cell: it must survive this long under sustained
## planted fire to count as verified-never. Fixed, because "never" is a claim
## about endurance and a cap derived from a prediction would make it circular.
const MAX_SECONDS: float = 30.0
## Extra time a predicted-KILL cell is given beyond its own predicted TTK.
##
## THE CAP USED TO BE A SINGLE CONSTANT, AND THAT MADE IT A LANDMINE. Its comment
## read *"the longest predicted kill (missile x aegis, 6 s) fits several times
## over"* — which went stale the moment the aegis's hull moved. Tripling it to 240
## (2026-08-07) pushed that cell past 30 s, and the check reported *"predicted
## kill, planted shots no kill"*: a RIG limit wearing the costume of a balance
## finding. A per-cell cap derived from the cell's own prediction cannot go stale
## when a config moves, which is the whole point of a bench that is supposed to
## survive tuning.
const KILL_MARGIN_SECONDS: float = 10.0
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
## The blaster's duty cycle, mirrored from the calculator (see `_add_cells`).
var _burst_shots: int = 0
var _burst_pause_ticks: int = 0
var _next_hit_tick: int = 0


func _initialize() -> void:
	_combat = load("res://resources/default_combat_config.tres") as CombatConfig
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
	_add_incoming_cells()
	_verify_weaponless()
	_verify_contact()
	_verify_survive()
	print("[lethality] Layer 1 table (config arithmetic, %d cells):"
			% _cells.size())
	for cell: Dictionary in _cells:
		var p: Dictionary = cell["predicted"]
		var verdict: String = "NEVER (%s)" % p["why"] if not p["kills"] \
				else "%d hit%s, ttk %.1fs" % [p["shots"],
				"" if int(p["shots"]) == 1 else "s", p["ttk"]]
		print("[lethality]   %-29s %s" % [_cell_name(cell), verdict])
	_print_combos()
	_start_cell()
	physics_frame.connect(_on_physics_frame)


## `config` is what the planted shots actually run against (already stripped
## for a cracked row); `named` supplies the type_id for the label.
func _add_cells(config: EnemyConfig, state: String, named: EnemyConfig) -> void:
	var label: String = String(named.type_id)
	if state != "":
		label += "(%s)" % state
	var pps: float = float(Engine.physics_ticks_per_second)
	for weapon: String in Lethality.WEAPONS:
		var interval: float = 0.0
		var damage: float = 0.0
		match weapon:
			"blaster":
				damage = _combat.projectile_damage
				interval = 1.0 / _combat.fire_rate
			"missile":
				damage = _combat.missile_damage
				interval = _combat.missile_cooldown
			"flak":
				# One BODY's share of a burst. The pack yield lives in Layer 2,
				# so what is planted here is a single fragment cloud's worth of
				# damage to a single target, at the pod's own cycle.
				damage = _combat.flak_damage
				interval = 1.0 / _combat.flak_fire_rate
		_cells.append({
			"weapon": weapon, "label": label, "direction": "out",
			# MOUNTS ARE HULL FOR THIS PURPOSE, and the rig has to say so on its own
			# side or it stops describing what the calculator describes. A Phalanx
			# routes every round to the nearest LIVING mount before its hull, from
			# any bearing, so the battery is 600 points that must be chewed through
			# first. Taken from `Lethality.target_from_enemy` rather than recomputed,
			# because the whole value of this bench is that the two agree.
			"hull": float(Lethality.target_from_enemy(config)["hull"]),
			"armor": config.armor, "defenses": config,
			"damage": damage, "interval": interval,
			# THE BLASTER'S HEAT SINK IS PART OF ITS CADENCE, and the planted rig
			# has to fire on the same clock the calculator predicts or the two
			# disagree about TIME while agreeing about hits.
			#
			# It went unnoticed for as long as it did because no target ever
			# outlasted the sink: every enemy died inside `burst_shots` bolts, so
			# the vent never fell inside a measured window. The Phalanx is the
			# first body needing 40 (A7), and it surfaced at once — predicted
			# 6.00 s against a planted 3.90 s, on an identical 40 hits.
			"burst_shots": Lethality.burst_shots(_combat) if weapon == "blaster" else 0,
			"burst_pause": Lethality.vent_seconds(_combat) if weapon == "blaster" else 0.0,
			"predicted": Lethality.versus(weapon, _combat, config),
		})
	# `pps` is read by _start_cell; touching it here keeps the two in sync if
	# the tick rate ever changes under us.
	assert(pps > 0.0)


## LAYER 3a (Iteration 9 / S2): the same planted-shot discipline, arrow
## reversed — one enemy type's weapon fired into a REAL player `Health`, built
## from the frame the drone actually flies. This is the verification that was
## missing while the frame axis was being banded on unmeasured durability.
func _add_incoming_cells() -> void:
	for frame_id: String in Frames.ROSTER:
		var frame: FrameConfig = Frames.config(frame_id)
		for enemy_path: String in ENEMIES:
			var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
			var predicted: Dictionary = Lethality.incoming(enemy, frame)
			# Only RANGED types have a cadence to plant on. Contact types are
			# verified synchronously in _verify_contact (no shield on a frame
			# means no time dependence at all), and weaponless types are
			# asserted as arithmetic in _verify_weaponless.
			if predicted["mode"] != &"ranged":
				continue
			_cells.append({
				"weapon": String(enemy.type_id), "direction": "in",
				"label": "%s <- %s" % [frame_id, enemy.type_id],
				"hull": frame.hull, "armor": frame.armor, "defenses": null,
				# A BATTERY FIRES FROM EVERY MOUNT, so the planted cadence has to be
				# the whole body's rather than one gun's — the same correction
				# `Lethality.incoming` carries, applied on the rig side so the two
				# still describe one clock. Without it the model predicted a kill in
				# 4.0 s and the rig could not land one at all inside the cap.
				"damage": enemy.damage,
				"interval": 1.0 / (enemy.fire_rate * float(maxi(enemy.mount_count, 1))),
				"predicted": predicted,
			})


## The combo rows: what a two-weapon answer costs, computed from the state
## split rather than tabulated as a special case. Arithmetic only — no duel
## flies this — but it is what makes "missile strips, gun finishes" a
## PREDICTION instead of a surprise in the validation column.
func _print_combos() -> void:
	for enemy_path: String in ENEMIES:
		var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
		# A THRESHOLD GATE IS WHAT MAKES A COMBO A QUESTION. This table answers
		# "strip with X, finish with Y", and that is only a real choice when some
		# weapons cannot strip at all — the aegis, whose screen refuses anything
		# under `shield_break_threshold`.
		#
		# The PHALANX has a screen with no threshold (A7): every weapon strips it,
		# and its counter is POSITIONAL rather than a loadout. Tabulating combos
		# for it answers a question the type does not pose — and it fails the
		# self-consistency assertion below for a real reason: `Lethality.combo`
		# splits the fight at shield-down and drops the carry-through of the hit
		# that broke it, which only shows up on a screen thin enough to be broken
		# and overshot by one round.
		if enemy.shield_max <= 0.0 or enemy.shield_break_threshold <= 0.0:
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
							"%s: %s->%s combo (%d hits, %.2fs) != %s solo (%d hits, %.2fs)"
							% [enemy.type_id, strip, finish, result["shots"],
							result["ttk"], strip, solo["shots"], solo["ttk"]])


## LAYER 3 COMPOSED (`BalancePrediction.survive`, v1.78). Nothing here plants a
## shot: the composition is pure arithmetic over `incoming`, which the planted
## cells above already verify against the shipped `Health`. What can still go
## wrong is the composition itself, so it is checked the way S12 checks a source
## of truth — against **properties that can fail**, each cheap and each capable
## of catching a real inversion:
##
##  1. IDENTITY. At a perfect connect rate and one attacker, survival must be the
##     Layer 1 ttk exactly. A composition that quietly rescales would drift here
##     first, and it is the only anchor that ties Layer 3b's number to verified
##     damage code.
##  2. MONOTONICITY IN CONCURRENCY. More shooters can never mean more life.
##  3. MONOTONICITY IN EVASION. A worse connect rate can never mean less life.
##     Both directions matter because the factor is stored as a CONNECT rate
##     (low = evasive), which reads backwards from its own name — the exact
##     shape of mistake that makes a sign error survive review.
##  4. LINEARITY IS A CLAIM, NOT A CHECK. Doubling the count halves the clock by
##     construction here, and that is deliberately NOT asserted against anything:
##     `survival_seconds`' own header calls it falsifiable by the concurrency
##     bench, and asserting a model against itself would launder an assumption
##     into a verified fact.
func _verify_survive() -> void:
	for enemy_path: String in ENEMIES:
		var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
		for frame_id: String in Frames.ROSTER:
			var frame: FrameConfig = Frames.config(frame_id)
			var solo: Dictionary = Lethality.incoming(enemy, frame)
			if solo["mode"] != &"ranged" or not bool(solo["kills"]):
				continue
			var perfect: Dictionary = BalancePrediction.survive(enemy, frame,
					1.0, 1)
			if not is_equal_approx(float(perfect["seconds"]),
					float(solo["ttk"])):
				_failures.append("survive(%s <- %s) at a perfect connect reads %.2fs, but Layer 1 says %.2fs"
						% [frame_id, enemy.type_id, perfect["seconds"],
						solo["ttk"]])
			var crowd: Dictionary = BalancePrediction.survive(enemy, frame,
					1.0, 3)
			if float(crowd["seconds"]) > float(perfect["seconds"]) + 0.001:
				_failures.append("survive(%s <- %s) says 3 attackers are LESS deadly than 1 (%.2fs vs %.2fs)"
						% [frame_id, enemy.type_id, crowd["seconds"],
						perfect["seconds"]])
			var dodging: Dictionary = BalancePrediction.survive(enemy, frame,
					0.25, 1)
			if float(dodging["seconds"]) < float(perfect["seconds"]) - 0.001:
				_failures.append("survive(%s <- %s) says dodging three shots in four SHORTENS your life (%.2fs vs %.2fs)"
						% [frame_id, enemy.type_id, dodging["seconds"],
						perfect["seconds"]])
	print("[lethality]   survive(): identity vs Layer 1, and monotone in both "
			+ "concurrency and connect rate (linearity is a claim for the "
			+ "concurrency bench, not an assert)")


## The v1.72 finding, as an assertion rather than a paragraph: a type carrying
## no weapon against the player prices NO frame's durability, so every frame
## looks identical against it and the frame axis is structurally blind there.
## If a future roster gives the aegis a defensive gun this check FAILS, which
## is the correct alarm — the Atlas x Aegis band would have to be revisited.
func _verify_weaponless() -> void:
	for enemy_path: String in ENEMIES:
		var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
		var identical: bool = true
		var first: float = -1.0
		for frame_id: String in Frames.ROSTER:
			var result: Dictionary = Lethality.incoming(enemy,
					Frames.config(frame_id))
			if result["mode"] != &"none":
				identical = false
				break
			if bool(result["kills"]):
				_failures.append("%s carries no weapon yet kills a %s"
						% [enemy.type_id, frame_id])
			var cost: float = float(result["hull_fraction"])
			if first < 0.0:
				first = cost
			elif not is_equal_approx(first, cost):
				_failures.append("%s is weaponless yet frames differ against it"
						% enemy.type_id)
		if identical:
			print("[lethality]   weaponless: %s prices NO frame's durability — "
					% enemy.type_id
					+ "every frame is identical against it, so the frame axis "
					+ "is structurally blind here (v1.72)")


## CONTACT types (the gnat). A frame has no shield, so `Health.take` has no
## time dependence for it — the whole exchange can be planted synchronously and
## compared exactly, no physics frames needed.
##
## This is the cell that proves flat armor does what P4.4 promises, and it only
## exists because `fire_rate == 0` turned out to mean "spends itself on contact"
## rather than "harmless" (gnat_swarm._resolve_stings → take_hit → die).
func _verify_contact() -> void:
	for enemy_path: String in ENEMIES:
		var enemy: EnemyConfig = load(enemy_path) as EnemyConfig
		for frame_id: String in Frames.ROSTER:
			var frame: FrameConfig = Frames.config(frame_id)
			var predicted: Dictionary = Lethality.incoming(enemy, frame)
			if predicted["mode"] != &"contact":
				continue
			# Plant the whole pack into a real Health wired the way
			# FlightController._ready wires the drone's.
			var health := Health.new()
			health.max_health = frame.hull
			root.add_child(health)
			health.armor = frame.armor
			# `_ready` has NOT run: this bench plants during _initialize, before
			# the first frame, so `current` is still its 0.0 default and the
			# first sting would "kill" a full-hull frame. The cell machine never
			# hit this because it plants from _on_physics_frame. State the
			# starting condition instead of inheriting a lifecycle assumption.
			health.current = frame.hull
			health.alive = true
			var bodies: int = int(predicted["bodies"])
			for body: int in bodies:
				if not health.alive:
					break
				# The model names the raw figure it derived from, so a type whose
				# damage lives somewhere other than `damage` (the Lance keeps its in
				# `bomb_damage`) is planted correctly without this bench learning the
				# roster. Planting the wrong field is how a model and its own
				# verification quietly stop describing the same thing.
				health.take(float(predicted.get("raw_per_hit", enemy.damage)))
			# Read `alive` directly rather than latching the `died` signal in a
			# lambda: GDScript closures capture locals BY VALUE, so the flag set
			# inside the callback never reaches this scope.
			var died: bool = not health.alive
			var spent: float = frame.hull - maxf(health.current, 0.0)
			health.queue_free()

			if died != bool(predicted["kills"]):
				_failures.append("%s <- %s pack: predicted %s, planted %s"
						% [frame_id, enemy.type_id,
						"kill" if predicted["kills"] else "survives",
						"killed" if died else "survived"])
				continue
			if not died and absf(spent - float(predicted["pack_damage"])) > 0.01:
				_failures.append("%s <- %s pack: predicted %.1f damage, planted %.1f"
						% [frame_id, enemy.type_id, predicted["pack_damage"], spent])
				continue
			print("[lethality]   verified %-18s %d stings spend %.0f of %.0f hull "
					% ["%s <- %s pack:" % [frame_id, enemy.type_id], bodies,
					spent, frame.hull]
					+ "(%.0f%%, %s)" % [float(predicted["hull_fraction"]) * 100.0,
					"KILLS" if died else "survivable"])


## Outgoing cells read "weapon x target"; incoming cells already carry their
## own "frame <- enemy" shape, and doubling it up reads as a typo.
func _cell_name(cell: Dictionary) -> String:
	if cell["direction"] == "in":
		return String(cell["label"])
	return "%s x %s" % [cell["weapon"], cell["label"]]


func _start_cell() -> void:
	var cell: Dictionary = _cells[_cell_i]
	_health = Health.new()
	_health.max_health = float(cell["hull"])
	root.add_child(_health)
	# An outgoing cell configures from the enemy's own block; an incoming cell
	# is the PLAYER's Health, which has armor and no shield — set the same way
	# FlightController._ready sets it, so the bench cannot drift from the drone.
	if cell["defenses"] != null:
		_health.configure_defenses(cell["defenses"] as EnemyConfig)
	else:
		_health.armor = float(cell["armor"])
	_health.died.connect(func() -> void: _death_tick = _ticks)
	var pps: float = float(Engine.physics_ticks_per_second)
	_damage = float(cell["damage"])
	_hit_interval_ticks = maxi(int(roundf(pps * float(cell["interval"]))), 1)
	_ticks = 0
	_hits_planted = 0
	_death_tick = -1
	_burst_shots = int(cell.get("burst_shots", 0))
	_burst_pause_ticks = int(roundf(pps * float(cell.get("burst_pause", 0.0))))
	_next_hit_tick = 0
	# Per cell, from the cell's own prediction: a predicted kill gets its TTK plus
	# a margin, a predicted never gets the fixed endurance window.
	var predicted: Dictionary = cell["predicted"]
	var seconds: float = MAX_SECONDS
	if bool(predicted["kills"]):
		seconds = float(predicted["ttk"]) + KILL_MARGIN_SECONDS
	_ticks_cap = int(seconds * pps)


func _on_physics_frame() -> void:
	if _health.alive and _ticks >= _next_hit_tick:
		_health.take(_damage)
		_hits_planted += 1
		_next_hit_tick = _ticks + _hit_interval_ticks
		# A full sink means the gun is dead until it has vented, exactly as
		# `Lethality` credits it — same rule, same place in the sequence.
		if _burst_shots > 0 and _hits_planted % _burst_shots == 0:
			_next_hit_tick += _burst_pause_ticks
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
	var label: String = _cell_name(cell)
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
