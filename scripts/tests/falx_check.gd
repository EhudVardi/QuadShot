extends SceneTree

## Falx behaviour check (P4.2, roster type five).
##
## Three bugs were found in this type inside its first hour, and every one of
## them was INVISIBLE to the existing suite: the harness only ever reported "the
## cell reads 0%", which is equally consistent with a tough enemy, a broken
## enemy, and an enemy that has flown to the next postcode. This file exists so
## each of them fails by name instead.
##
##   1. IT LEFT. With no target it flew straight ahead forever — and "no target"
##      includes every second before the player arms, so in the dev room it was
##      a dot on the horizon before anyone looked up. Found from the cockpit,
##      not by any test: *"the falx was flying away regardless of what i did."*
##   2. IT REFUSED TO ATTACK. Committing to a pass wanted 56 m of separation,
##      so at the harness's 40 m spawn it spent the whole duel setting up and
##      never fired. Visible only as `dmg-taken 0.0` in a cell nobody was
##      reading closely.
##   3. IT BROKE OFF ON FRAME ONE. Overshoot was judged against the BODY's
##      facing, and a fresh enemy has identity rotation and no velocity, so it
##      decided it had already flown past before it had moved.
##
## The two phases below are the two halves of the type's life — is it still here,
## and does it actually attack — which are exactly the two questions the bugs
## answered wrongly.
##
## Run: <godot> --headless -s scripts/tests/falx_check.gd --path .

const FALX_SCENE: String = "res://scenes/combat/falx.tscn"
## Seconds of patrol before the leash is measured. Long enough that a body
## flying straight at 25 m/s would be ~200 m gone.
const PATROL_SECONDS: float = 8.0
## How far from home a patrolling falx may drift. The circuit radius plus room
## for the arc it needs to get onto it — generous on purpose, because this
## guards ABSCONDING, not tidiness.
const LEASH_FACTOR: float = 1.8
## Seconds of engagement before the attack assertions are made. Two full
## run-in / recover / setup cycles fit.
const ENGAGE_SECONDS: float = 12.0
const ENGAGE_RANGE: float = 40.0
const ALTITUDE: float = 14.0

enum { PATROL, ENGAGE, DONE }

var _pps: float
var _phase: int = PATROL
var _ticks: int = 0
var _arena: Node3D
var _falx: Node3D
var _drone: FlightController
var _pool: ProjectilePool
var _home: Vector3
## Peak projectiles in flight during the engagement. The falx is the only thing
## shooting (the player has no pilot here), so anything above zero is the type
## having pulled its trigger.
var _peak_rounds: int = 0
## Closest the falx came to the player — a pass that never presses is not a pass.
var _closest: float = INF
var _failures: PackedStringArray = []


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	print("[falx] two phases: does it stay, and does it attack")
	_build_patrol()
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_ticks += 1
	match _phase:
		PATROL:
			if _ticks >= int(PATROL_SECONDS * _pps):
				_score_patrol()
				_teardown()
				_build_engage()
				_phase = ENGAGE
				_ticks = 0
		ENGAGE:
			if is_instance_valid(_falx) and is_instance_valid(_drone):
				_closest = minf(_closest, _falx.global_position.distance_to(
						_drone.global_position))
			if _pool != null:
				_peak_rounds = maxi(_peak_rounds, _pool.live_count())
			if _ticks >= int(ENGAGE_SECONDS * _pps):
				_score_engage()
				_report()


## PHASE 1: no player in the tree at all, so `_can_engage` is false every tick
## and the type is on its idle behaviour — the state bug 1 lived in.
func _build_patrol() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)
	_home = Vector3(0.0, 20.0, 0.0)
	_falx = _spawn_falx(_home)


func _score_patrol() -> void:
	if not is_instance_valid(_falx):
		_failures.append("the falx did not survive an empty arena")
		return
	var drift: float = _falx.global_position.distance_to(_home)
	var leash: float = Falx.PATROL_RADIUS * LEASH_FACTOR
	print("[falx] patrol: %.0f m from home after %.0fs (leash %.0f m)"
			% [drift, PATROL_SECONDS, leash])
	if drift > leash:
		_failures.append("ABSCONDED: %.0f m from home after %.0fs with no target (leash %.0f m) — the idle behaviour is flying it out of the level"
				% [drift, PATROL_SECONDS, leash])


## PHASE 2: a real armed drone, and no pilot flying it. The player is a parked
## target so the ONLY thing that can put rounds in the air is the falx, which is
## what makes `_peak_rounds` a clean read on bugs 2 and 3.
func _build_engage() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)
	_drone = Frames.build(Frames.KESTREL)
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALTITUDE, 0.0)
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())
	# Immortal: the check is about whether the falx ATTACKS, and a dead player
	# stops being a target mid-measurement.
	var health: Health = _drone.get_node("Health") as Health
	health.max_health = 1.0e9
	health.revive()
	# Spawned at identity rotation, exactly as the harness and the dev room place
	# it — which is the condition bug 3 needed.
	_falx = _spawn_falx(Vector3(0.0, ALTITUDE, -ENGAGE_RANGE))


func _score_engage() -> void:
	print("[falx] engage: closest approach %.0f m, peak rounds in flight %d"
			% [_closest, _peak_rounds])
	if _peak_rounds <= 0:
		_failures.append("NEVER FIRED in %.0fs against a stationary armed player — the type is not attacking (bugs 2 and 3 both looked exactly like this)"
				% ENGAGE_SECONDS)
	if _closest > ENGAGE_RANGE:
		_failures.append("NEVER PRESSED: closest approach %.0f m from a %.0f m spawn — it never ran in at all"
				% [_closest, ENGAGE_RANGE])


func _spawn_falx(at: Vector3) -> Node3D:
	var falx: Node3D = (load(FALX_SCENE) as PackedScene).instantiate() as Node3D
	# Seeded for determinism (P4.8), and set before the node enters the tree.
	falx.set(&"ai_seed", 0)
	falx.position = at
	_arena.add_child(falx)
	return falx


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_falx = null
	_drone = null
	_pool = null


func _report() -> void:
	_phase = DONE
	if _failures.is_empty():
		print("[falx] PASS")
		quit(0)
		return
	for failure: String in _failures:
		print("[falx] FAIL: %s" % failure)
	print("[falx] FAIL")
	quit(1)
