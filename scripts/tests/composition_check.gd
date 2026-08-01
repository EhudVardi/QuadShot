extends SceneTree

## Headless wave-COMPOSITION behaviour check (M6a step 8). Every new bestiary
## type gets one of these the day it lands, and this is the check the roster
## rule demands the day the run stopped being raiders-only.
##
## The scar it exists for: a results table can only ever say "this wave did not
## clear", which is equally consistent with a tough wave, a broken wave, and a
## wave holding a unit that can never die. Three of the six roster types can
## deadlock a wave in a way a body count cannot see:
##
##   - a gnat CLOUD is one unit and nine bodies, and reports `cleared`, not
##     `destroyed` — a director counting `destroyed` clears the wave eight
##     bodies early and then never again;
##   - a TURRET respawns on a 20 s timer, so a wave holding one is unclearable
##     for as long as the run lasts;
##   - an AEGIS can leave the field WITHOUT dying, by reaching its target — the
##     one exit that pays no points and fires no `destroyed`.
##
## Two halves. Part A is arithmetic over the composition table with no arena at
## all, which is the only way to cover sorties nobody has time to fly to. Part B
## flies three real sorties and clears every wave except the bombers, which are
## deliberately let through so the detonation path is the one under test.
##
## Run: <godot> --headless -s scripts/tests/composition_check.gd --path .

const MAX_SECONDS: float = 60.0
## How many sorties Part B walks. Three covers every row of the plan; past that
## the table repeats its last row by construction (and Part A proves it).
const SORTIES: int = 3
## Sweeps for Part A. Deliberately wider than any run reaches, because the
## table clamps and the clamp is exactly where an off-by-one would hide.
const SORTIE_SWEEP: int = 8
const WAVE_SWEEP: int = 4
const BUDGET_SWEEP: int = 10

var _main: Node3D
var _drone: FlightController
var _director: WaveDirector
var _phase: int = 0
var _ticks: int = 0
var _ticks_max: int
var _failures: Array[String] = []
## (sortie, wave) of the last composition verified, so each wave is checked
## once, on the frame it appears.
var _last_key: Array = []
## Every type Part B actually watched spawn into a live run.
var _flown: Dictionary = {}
var _sorties_cleared: int = 0
var _detonations: int = 0
## The run has actually begun — before that, `running == false` is normal.
var _started: bool = false


func _initialize() -> void:
	_check_table()
	if not _failures.is_empty():
		_report()
		return
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate() as Node3D
	root.add_child(_main)
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_physics_frame)


## ---------- Part A: the table, without an arena ----------

func _check_table() -> void:
	for type_id: StringName in WaveDirector.ROSTER:
		var path: String = String(WaveDirector.ROSTER[type_id]["scene"])
		if load(path) as PackedScene == null:
			_fail("roster type %s has no loadable scene at %s" % [type_id, path])

	for sortie_n: int in range(1, SORTIE_SWEEP + 1):
		for wave_n: int in range(1, WAVE_SWEEP + 1):
			for budget: int in range(1, BUDGET_SWEEP + 1):
				var composed: Array[StringName] = WaveDirector.compose(
						sortie_n, wave_n, budget)
				var where: String = "s%d w%d budget %d" % [sortie_n, wave_n, budget]
				# The budget is the WHOLE wave, not a base the plan adds to.
				if composed.size() != budget:
					_fail("%s composed %d units" % [where, composed.size()])
				for type_id: StringName in composed:
					if not WaveDirector.ROSTER.has(type_id):
						_fail("%s composed unknown type %s" % [where, type_id])
				# The escort rule: the screamer carries no weapon, so a wave of
				# nothing but screamers is a wave with no fight in it.
				if not WaveDirector.has_threat(composed):
					_fail("%s composed a wave with nothing that threatens" % where)

	# The bug this whole item exists to fix: five of six roster types had never
	# appeared in a run. If a type stops reaching the plan, that is the same
	# bug back, and it is invisible from anywhere else.
	var reachable: Dictionary = {}
	for sortie_n: int in range(1, SORTIE_SWEEP + 1):
		for wave_n: int in range(1, WAVE_SWEEP + 1):
			for type_id: StringName in WaveDirector.compose(sortie_n, wave_n, BUDGET_SWEEP):
				reachable[type_id] = true
	for type_id: StringName in WaveDirector.ROSTER:
		if not reachable.has(type_id):
			_fail("roster type %s never reaches a wave — the run cannot field it"
					% type_id)
	print("[composition_check] table: %d types, %d compositions swept"
			% [WaveDirector.ROSTER.size(),
			SORTIE_SWEEP * WAVE_SWEEP * BUDGET_SWEEP])


## ---------- Part B: three real sorties ----------

func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks >= _ticks_max:
		_fail("timed out in phase %d (s%d w%d, %d units left)"
				% [_phase, _director.sortie if _director != null else -1,
				_director.wave if _director != null else -1,
				_director.remaining if _director != null else -1])
		_report()
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_setup()
			_phase = 1
		1:
			# Arming starts the run from main's _process, an idle frame later.
			if not _director.running:
				if not _started:
					return
				_fail("the run ended on its own — the player died mid-check")
				_report()
				return
			_started = true
			if _director.awaiting_gate:
				_sorties_cleared += 1
				print("[composition_check] sortie %d cleared" % _director.sortie)
				if _sorties_cleared >= SORTIES:
					_report()
					return
				_director.advance_sortie()
				return
			_verify_wave()
			_cull_wave()


func _verify_wave() -> void:
	if _director.remaining <= 0:
		return
	var key: Array = [_director.sortie, _director.wave]
	if key == _last_key:
		return
	_last_key = key
	var expected: Array[StringName] = WaveDirector.compose(_director.sortie,
			_director.wave,
			_director.wave_budget(_director.sortie, _director.wave))
	var actual: Array[StringName] = []
	for unit: Node in _director.units:
		var type_id: StringName = _type_of(unit)
		if type_id == &"":
			_fail("s%d w%d spawned %s, which is not a roster scene"
					% [_director.sortie, _director.wave, unit.scene_file_path])
			continue
		actual.append(type_id)
		_flown[type_id] = true
	# The table and the arena must agree, or Part A is proving things about a
	# function the game does not actually spawn from.
	if _tally(actual) != _tally(expected):
		_fail("s%d w%d spawned %s, plan says %s"
				% [_director.sortie, _director.wave, str(_tally(actual)),
				str(_tally(expected))])
	print("[composition_check] s%d w%d: %s" % [_director.sortie, _director.wave,
			str(_tally(actual))])


## Clear the wave, EXCEPT the bombers. A wave holding an untouched aegis can
## only end by that aegis reaching its target, which is the detonation path
## this check exists to prove does not deadlock.
func _cull_wave() -> void:
	for unit: Node in _director.units.duplicate():
		if not is_instance_valid(unit) or _type_of(unit) == &"aegis":
			continue
		if unit.has_method("take_hit"):
			unit.call("take_hit", 99999.0)
			continue
		# A cloud has no hull of its own: the bodies under it are its hit
		# points, spread across space (P4.q5).
		for body: Node in unit.get_children():
			if body.has_method("take_hit"):
				body.call("take_hit", 99999.0)


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_director = _main.get_node("WaveDirector") as WaveDirector
	var config: CombatConfig = _main.get("combat_config")
	# Every field the assertions depend on is pinned explicitly — main
	# auto-loads the pilot's saved combat config, which can carry any
	# difficulty tuning. The opposition is defanged because this check is about
	# BOOKKEEPING, not lethality: the player must survive to watch the waves.
	config.wave_intermission = 0.1
	config.wave_base_enemies = 2.0
	config.wave_growth = 1.0
	config.sortie_waves = 3.0
	config.sortie_enemy_bonus = 1.0
	for type_id: StringName in WaveDirector.ROSTER:
		var enemy: EnemyConfig = load(
				"res://resources/default_enemy_%s.tres" % type_id) as EnemyConfig
		enemy.damage = 0.0
		enemy.sight_range = 0.0
	# FILTERED, not counted. `announced` happens to have exactly one emitter today
	# - the bomber - so a bare counter was right by accident. The day the director
	# announces a wave callout, a gate notice or anything else, an un-filtered
	# count would still read green while proving nothing about the detonation path
	# it is named for. `SortieRunner` already emits six different announcements,
	# so the second emitter is a matter of when, not whether.
	_director.announced.connect(func(text: String) -> void:
		if text.to_lower().contains("bomber"):
			_detonations += 1
		print("[composition_check] %s" % text))
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())


## ---------- small helpers ----------

## Which roster row built this unit. Matched on the scene path rather than the
## class, so the table stays the single source of truth.
func _type_of(unit: Node) -> StringName:
	for type_id: StringName in WaveDirector.ROSTER:
		if unit.scene_file_path == String(WaveDirector.ROSTER[type_id]["scene"]):
			return type_id
	return &""


## Type → count, so two compositions compare by content and not by order.
func _tally(types: Array[StringName]) -> Dictionary:
	var counts: Dictionary = {}
	for type_id: StringName in WaveDirector.ROSTER:
		var n: int = 0
		for other: StringName in types:
			if other == type_id:
				n += 1
		if n > 0:
			counts[String(type_id)] = n
	return counts


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	# A bomber let through must have ended its unit, or a wave that lost one
	# would hang forever and this check would have timed out rather than said
	# so. Both aegis waves are in sortie 3, so this only binds once we got there.
	if _sorties_cleared >= SORTIES and _detonations < 1:
		_fail("no bomber reached its target — the detonation path went untested")
	for type_id: StringName in WaveDirector.ROSTER:
		if _main != null and _sorties_cleared >= SORTIES and not _flown.has(type_id):
			_fail("roster type %s never spawned in %d flown sorties"
					% [type_id, SORTIES])
	for message: String in _failures:
		print("[composition_check] FAIL: %s" % message)
	print("[composition_check] %d sorties cleared, %d bombers through, types flown %s"
			% [_sorties_cleared, _detonations, str(_flown.keys())])
	print("[composition_check] %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
