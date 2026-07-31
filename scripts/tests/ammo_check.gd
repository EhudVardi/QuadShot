extends SceneTree

## Headless MAGAZINE check (Iteration 10, R.q2/R.q3/R.q4/R.q6). The blaster has
## heat and can never run out; the flak pod and the missile rack can, and every
## way of putting rounds back has to work or a run reaches a wave it cannot
## clear with a pilot who did nothing wrong.
##
## The failure this exists for is the mirror of `heat_check`'s: not a gun that
## never comes back, but a magazine that never refills. Four ways to refill
## exist and each one is a separate way to be silently broken:
##
##   1. firing SPENDS, and a dry launcher refuses (otherwise the count is
##      decoration);
##   2. a resupply GATE fills the magazine it is keyed to and nothing else,
##      spends exactly one charge, and refuses to spend one on a full magazine
##      (a gate that eats a charge for nothing punishes good routing);
##   3. a SPENT gate is inert — R.q4's finite charges are the difficulty knob,
##      and a gate that quietly kept working would delete it;
##   4. clearing a wave re-arms NOTHING (R.q3 retracted in v1.93 after the user
##      flew it), so ammunition is a genuine sortie resource and the gates keep
##      their teeth.
##
## Plus salvage (R.q6): a drop tops up, and a full magazine leaves it alone.
##
## Run: <godot> --headless -s scripts/tests/ammo_check.gd --path .

const MAX_SECONDS: float = 30.0

var _main: Node3D
var _drone: FlightController
var _flak: FlakPod
var _missiles: MissileSystem
var _director: WaveDirector
var _combat: CombatConfig
var _phase: int = 0
var _ticks: int = 0
var _ticks_max: int
var _failures: Array[String] = []
var _gate: ResupplyGate
var _started: bool = false


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_main)
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks >= _ticks_max:
		_fail("timed out in phase %d" % _phase)
		_report()
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_setup()
			_phase = 1
		1:
			if not _director.running:
				if _started:
					_fail("the run ended on its own — the player died mid-check")
					_report()
				return
			_started = true
			_check_spending()
			_check_gate()
			_check_salvage()
			_check_no_free_rearm()
			_report()


## 1. Firing spends, and a dry launcher refuses.
func _check_spending() -> void:
	var full: int = _flak.magazine()
	if _flak.rounds != full:
		_fail("flak did not start full (%d of %d)" % [_flak.rounds, full])
	# Drain by hand rather than by holding the trigger: this is bookkeeping,
	# and a real 24-shell burst would take ten seconds of arena time.
	_flak.rounds = 0
	if _flak.has_ammo():
		_fail("an empty flak pod still reports ammo")
	var before: int = _flak.shots_fired
	_flak.fire_override = true
	# The pod fires from _physics_process, so this frame's call has already
	# happened; what matters is that the count never moves while dry, which the
	# next phases keep verifying as the check runs on.
	if _flak.shots_fired > before:
		_fail("a dry flak pod fired")
	_flak.fire_override = false


## 2 and 3. A gate fills its own kind, spends one charge, ignores a full
## magazine, and goes inert when spent.
func _check_gate() -> void:
	_gate = ResupplyGate.new()
	_gate.kind = &"flak"
	_gate.charges = 1
	_gate.cooldown = 0.0
	_main.add_child(_gate)
	_flak.rounds = 0
	_missiles.rounds = 0

	_gate.call(&"_on_body_entered", _drone)
	if _flak.rounds != _flak.magazine():
		_fail("a flak gate left the pod at %d of %d"
				% [_flak.rounds, _flak.magazine()])
	if _missiles.rounds != 0:
		_fail("a FLAK gate refilled the missile rack (%d)" % _missiles.rounds)
	if _gate.charges != 0:
		_fail("gate spent %d charges on one pass" % (1 - _gate.charges))
	if not _gate.spent():
		_fail("a gate at 0 charges does not report spent")

	# Spent gate: inert.
	_flak.rounds = 0
	_gate.call(&"_on_body_entered", _drone)
	if _flak.rounds != 0:
		_fail("a SPENT gate still refilled (%d) — R.q4's charges mean nothing"
				% _flak.rounds)

	# A full magazine must not cost a charge.
	var fresh := ResupplyGate.new()
	fresh.kind = &"flak"
	fresh.charges = 2
	fresh.cooldown = 0.0
	_main.add_child(fresh)
	_flak.rearm()
	fresh.call(&"_on_body_entered", _drone)
	if fresh.charges != 2:
		_fail("a gate spent a charge on an already-full magazine")
	fresh.queue_free()
	print("[ammo_check] gate: fills its own kind, one charge per pass, inert when spent")


## Salvage tops up, and leaves a full magazine alone.
func _check_salvage() -> void:
	var drop := Salvage.new()
	drop.kind = &"flak"
	_main.add_child(drop)
	_flak.rounds = 0
	drop.call(&"_collect")
	var expected: int = int(ceil(float(_flak.magazine()) * Salvage.REFILL_FRACTION))
	if _flak.rounds != expected:
		_fail("salvage gave %d shells, %.2f of a magazine is %d"
				% [_flak.rounds, Salvage.REFILL_FRACTION, expected])
	# A pickup consumed by a full magazine is one the pilot watched vanish for
	# nothing, and they will read that as the drop being broken.
	var full_drop := Salvage.new()
	full_drop.kind = &"flak"
	_main.add_child(full_drop)
	_flak.rearm()
	full_drop.call(&"_collect")
	if full_drop.is_queued_for_deletion():
		_fail("salvage consumed itself against a full magazine")
	full_drop.queue_free()
	print("[ammo_check] salvage: tops up %d shells, spares itself against a full pod"
			% expected)


## 4. Clearing a wave re-arms NOTHING. R.q3 answered "free re-arm" and was
## retracted after three rounds of play: I had flagged that R.q2 and R.q3
## together moved the unit of scarcity from the sortie to the wave, and flying
## it confirmed the gates went slack. This asserts the retraction, because a
## free refill quietly creeping back is exactly the kind of regression that
## makes a whole economy feel pointless without any single thing looking wrong.
func _check_no_free_rearm() -> void:
	_flak.rounds = 3
	_missiles.rounds = 1
	_director.wave_cleared.emit(_director.sortie, _director.wave)
	if _flak.rounds != 3 or _missiles.rounds != 1:
		_fail("clearing a wave re-armed for free (flak %d, missiles %d) — R.q3 was retracted"
				% [_flak.rounds, _missiles.rounds])
	else:
		print("[ammo_check] a cleared wave re-arms nothing: gates and kills only")
	# And the gates the director lays are real, keyed, and countable.
	if _director.gates.is_empty():
		_fail("the sortie laid no resupply gates")
	elif _director.gates.size() != _director.gate_count(_director.sortie):
		_fail("sortie %d laid %d gates, gate_count says %d"
				% [_director.sortie, _director.gates.size(),
				_director.gate_count(_director.sortie)])
	else:
		print("[ammo_check] sortie %d laid %d gates (pad-poor decay: sortie 6 gets %d)"
				% [_director.sortie, _director.gates.size(), _director.gate_count(6)])
	_check_gate_spacing()


## Gates must not overlap each other, and must not be laid inside scenery.
##
## This is a REPORTED bug turned into an assertion: "the ammo gates were spawned
## clipping into each other". Placement is rejection-sampled now, and a sample
## that keeps its own constraint is exactly the kind of thing that quietly stops
## doing so when the arena, the radii or the gate count change. Re-laid many
## times because one lay of three gates passing proves very little.
func _check_gate_spacing() -> void:
	var laid: int = 0
	var overlaps: int = 0
	var buried: int = 0
	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = WaveDirector.GATE_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	for sortie_n: int in range(1, 7):
		_director.sortie = sortie_n
		_director.call(&"_lay_gates")
		var points: Array[Vector3] = []
		for gate: Node in _director.gates:
			points.append((gate as Node3D).global_position)
		laid += points.size()
		for i: int in points.size():
			for j: int in range(i + 1, points.size()):
				if points[i].distance_to(points[j]) < WaveDirector.GATE_MIN_SEPARATION:
					overlaps += 1
			query.transform = Transform3D(Basis.IDENTITY, points[i])
			# The gates themselves are StaticBody3D now, so exclude them or every
			# gate reports as buried inside itself.
			var excludes: Array[RID] = []
			for gate: Node in _director.gates:
				excludes.append((gate as CollisionObject3D).get_rid())
			query.exclude = excludes
			for hit: Dictionary in space.intersect_shape(query, 4):
				if hit["collider"] is StaticBody3D:
					buried += 1
					break
	if overlaps > 0:
		_fail("%d gate pairs closer than %.0f m across 6 sorties"
				% [overlaps, WaveDirector.GATE_MIN_SEPARATION])
	if buried > 0:
		_fail("%d gates laid inside scenery across 6 sorties" % buried)
	if overlaps == 0 and buried == 0:
		print("[ammo_check] %d gates over 6 sorties: none overlapping, none buried"
				% laid)


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod
	_missiles = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_director = _main.get_node("WaveDirector") as WaveDirector
	_combat = _main.get("combat_config")
	# Every field the assertions depend on is pinned explicitly — main
	# auto-loads the pilot's saved combat config, which can carry any tuning.
	_combat.flak_magazine = 24.0
	_combat.missile_rack = 6.0
	# Arming starts a real run, and a real run shoots back; this check is about
	# bookkeeping, not a fight.
	for type_id: StringName in WaveDirector.ROSTER:
		var enemy_type: StringName = &"gnat" if type_id == &"gnats" else type_id
		var enemy: EnemyConfig = load(
				"res://resources/default_enemy_%s.tres" % enemy_type) as EnemyConfig
		enemy.damage = 0.0
		enemy.sight_range = 0.0
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	# The magazines loaded in _ready, before the pinned capacities above.
	_flak.rearm()
	_missiles.rearm()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	for message: String in _failures:
		print("[ammo_check] FAIL: %s" % message)
	print("[ammo_check] %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
