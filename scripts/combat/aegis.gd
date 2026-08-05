class_name Aegis
extends CharacterBody3D

## Aegis — shielded bomber (GAMEPLAY-DESIGN P4.2, reworked Iteration 14 / A2).
##
## The one roster member that does not care about you. It flies a strike route
## toward something of YOURS at a walking pace, does not evade and does not
## shoot. Every second it stays alive is a countdown, so it converts the fight
## from "can I kill this" into "can I kill this IN TIME" — a priority call
## rather than a duel.
##
## WHAT THE REWORK CHANGED, and why it is a drift report rather than a redesign.
## P4.2 has said since Iteration 2 that the aegis flies *toward a friendly asset*
## and that arrival is bad for you. It never said the aegis is EXPENDED. The
## implementation read "arrives" as "detonates", which quietly made it a kamikaze
## — a different enemy in a different web position — and `SortieRunner` then
## aimed it at the sortie's own centre, so the enemy's bomber flew into the
## middle of the base it was defending and blew up on its own objective.
##
## So it now CARRIES ORDNANCE, SPENDS IT, AND LEAVES:
##
##   - it flies bombing PASSES, one per bomb, instead of ending on one arrival;
##   - the payload is a MAGAZINE (A.q2), in the same group and the same
##     vocabulary the player's flak pod and missile rack use, so a bomber out of
##     bombs is legible in exactly the way a pilot out of flak already is;
##   - when the payload is spent it EGRESSES, and getting out is a distinct
##     outcome the war can price (A.q3) rather than a second kind of death.
##
## THAT IS THREE OUTCOMES WHERE SELF-DETONATION OFFERED TWO: kill it before it
## drops anything, kill it between passes, or fail and watch it go home having
## done its damage. The third is the one the war-sim can price differently.
##
## Its shield (health.gd) gates hull behind a per-hit threshold, so the answer
## has to arrive in big pieces: chip guns are hard-countered (P4.3 `--`), burst
## and missiles crack it (`++`). Cracking opens a timed window before regen
## closes it again, which is when the gun finally earns its keep — the combo,
## not the gun alone.
##
## `payload` 0 KEEPS THE OLD BEHAVIOUR EXACTLY, and that is deliberate: the
## ticking-bomb form is still one config field away, the dev room's `loop_route`
## specimen is untouched, and no other roster type has to know this file grew a
## magazine.

signal destroyed(points: float)
## One bomb delivered. The per-pass event, distinct from the unit being over.
signal bomb_dropped(at: Vector3)
## Payload spent and it got out. THE ENEMY SURVIVED — a different outcome from
## being killed, and the one A.q3 prices back into the war.
signal escaped
## This bomber is finished with the field, however that happened: it escaped, or
## (with no payload) it arrived and was spent. Every existing consumer —
## `WaveDirector`, `SortieRunner`, `composition_check` — reads this to mean "the
## unit is over without dying", so its meaning is unchanged by the rework.
signal detonated

## Encounter-design constants (not flight/input physics).
const ARRIVE_RADIUS: float = 3.0
const DEFAULT_ROUTE_LENGTH: float = 120.0
## How far past its target a spent bomber has to get before it counts as AWAY.
## Clear of the outer ring rather than off the map: the run home is counterplay
## you can still interrupt, not a lap of honour.
const EGRESS_RADIUS: float = 90.0
## And a fallback, because "it reaches a radius" is a promise the world can break
## — a bomber wedged against scenery would otherwise live forever as a body
## nothing can resolve. Generous enough that it never pre-empts a real egress.
const EGRESS_SECONDS: float = 25.0
## The climb-out and turn between passes. A bomber that snapped round instantly
## would delete the window the whole type is balanced around — the recovery is
## where a shielded thing is finally killable, exactly as the falx's is.
const REATTACK_CLIMB: float = 18.0
const REATTACK_SECONDS: float = 3.0

enum Phase { RUN_IN, REATTACK, EGRESS }

@export var enemy_config: EnemyConfig
## Dev-room affordance (per instance, off everywhere else): instead of being
## spent on arrival, the bomber restarts its run at full shield. Cracking a
## shield is a skill worth practising more than once per launch.
##
## IT SHORT-CIRCUITS THE PAYLOAD, and that is not laziness — `delivery_bench`
## measures the aegis cells with this on, so preserving the old loop exactly is
## what keeps those measurements comparable across the rework.
@export var loop_route: bool = false

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

## Where the strike route ends. Set before the node enters the tree; if it is
## left unset the bomber flies its own heading for DEFAULT_ROUTE_LENGTH, so a
## specimen dropped into a map still behaves like a bomber.
var route_end: Vector3 = Vector3.INF

## THE MAGAZINE (A.q2). Same field name and same four methods as `FlakPod` and
## `MissileSystem`, because the decision was that one mechanism covers both.
var rounds: int = 0
## Which resupply refills this. `bomb` matches no `ResupplyGate.kind` in the
## game — gates are only ever `flak` or `missile` — so the player's own gates and
## salvage drops cannot rearm an enemy bomber. `aegis_check` asserts that rather
## than trusting it.
var ammo_kind: StringName = &"bomb"

@onready var _shell: ShieldShell = $ShieldShell
@onready var _shield_visual: MeshInstance3D = $ShieldShell/Mesh
@onready var _shell_collision: CollisionShape3D = $ShieldShell/Collision
@onready var _health: Health = $Health

var _shield_flash: float = 0.0
var _route_start: Vector3
var _phase: int = Phase.RUN_IN
var _phase_time: float = 0.0
var _reattack_point: Vector3
var _bombs_dropped: int = 0


func _ready() -> void:
	_route_start = global_position
	# Without this the bomber's own move_and_slide fights the shell it carries.
	add_collision_exception_with(_shell)
	_shell.hit.connect(_health.take)
	if route_end == Vector3.INF:
		route_end = global_position - global_basis.z * DEFAULT_ROUTE_LENGTH
	_health.max_health = enemy_config.hull
	_health.configure_defenses(enemy_config)
	_health.revive()
	_health.died.connect(_on_died)
	_health.shield_absorbed.connect(_on_shield_absorbed)
	_health.shield_broken.connect(_on_shield_broken)
	add_to_group(&"magazines")
	rearm()


## ---------- the magazine (A.q2) ----------

## Capacity. 0 = unlimited, exactly as the player's launchers read it — which
## here means "not a bomber", the legacy ticking-bomb form.
func magazine() -> int:
	return maxi(int(enemy_config.payload), 0)


func unlimited() -> bool:
	return magazine() <= 0


func has_ammo() -> bool:
	return unlimited() or rounds > 0


func rearm(fraction: float = 1.0) -> void:
	if unlimited():
		rounds = 0
		return
	rounds = clampi(rounds + int(ceil(float(magazine()) * fraction)), 0, magazine())


## Bombs actually delivered. What the war prices, and what a check reads.
func bombs_dropped() -> int:
	return _bombs_dropped


func take_hit(damage: float) -> void:
	_health.take(damage)


func _physics_process(delta: float) -> void:
	_phase_time += delta
	match _phase:
		Phase.RUN_IN:
			_run_in(delta)
		Phase.REATTACK:
			_reattack(delta)
		Phase.EGRESS:
			_egress(delta)
	_face_route(delta)
	_update_shield_visual(delta)


## No evasion, no arrival easing: it holds its route speed until it is on top of
## the target. The telegraph is that you can see exactly where it is going and
## exactly how long you have.
func _run_in(delta: float) -> void:
	var offset: Vector3 = route_end - global_position
	if offset.length() < ARRIVE_RADIUS:
		_arrive()
		return
	_fly_toward(route_end, delta)


## THE ARRIVAL. With a payload this is a bomb and the bomber lives; without one
## it is the old ticking bomb going off, unchanged.
func _arrive() -> void:
	if loop_route:
		# The dev-room / delivery-bench specimen: spend nothing, start again.
		_restart_run()
		return
	if unlimited():
		# LEGACY: no payload, so arrival IS the detonation. Every consumer of
		# `detonated` behaves exactly as it did before the rework.
		Effects.explosion(get_tree().root, route_end, 3.0)
		detonated.emit()
		queue_free()
		return
	_drop_bomb()
	if rounds > 0:
		_enter_reattack()
		return
	# THE UNIT IS OVER WHEN THE PAYLOAD IS, not when the bomber is finally out of
	# sight (P4.q5). It came, it dropped everything it had, and it is now flying
	# away — a wave that waited for it to cross a line would be a wave held open
	# by an enemy that has already done its worst, which `composition_check`
	# caught as a 60 s timeout with one unit left.
	#
	# It stays ALIVE and killable through the whole run home, and that is the
	# point: kill it on the way out and you get the kill, the dent, and no raid
	# priced against your ground, because `escaped` never fires.
	detonated.emit()
	_enter(Phase.EGRESS)


## One bomb. It damages what it lands ON rather than the bomber, which is the
## whole difference between a bomber and a kamikaze.
func _drop_bomb() -> void:
	rounds = maxi(rounds - 1, 0)
	_bombs_dropped += 1
	Effects.explosion(get_tree().root, route_end, 2.4)
	SoundBank.play_at(&"explosion", route_end, -4.0, 0.6)
	_splash(route_end)
	bomb_dropped.emit(route_end)


## Blast, applied to anything of the other team inside the radius. Deliberately
## a distance test over the two groups rather than a physics query: the same
## reasoning `gnat_swarm` uses for its sting, and a bomb that only hurt bodies
## with colliders in the right layer would be a bomb that mostly did nothing.
func _splash(at: Vector3) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"player") \
			+ get_tree().get_nodes_in_group(&"objectives"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.get(&"team") == team:
			continue
		var distance: float = (node as Node3D).global_position.distance_to(at)
		if distance > enemy_config.bomb_radius:
			continue
		# Linear falloff, so standing at the edge of a bomb is meaningfully
		# better than standing on it.
		var scale: float = 1.0 - distance / maxf(enemy_config.bomb_radius, 0.001)
		if node.has_method(&"take_hit"):
			node.call(&"take_hit", enemy_config.bomb_damage * scale)


## Climb away, then come round for the next pass. The window a shielded thing is
## killable in — the same structural role the falx's recovery plays.
func _enter_reattack() -> void:
	var away: Vector3 = global_position - route_end
	away.y = 0.0
	if away.length() < 1.0:
		away = -global_basis.z
	_reattack_point = route_end + away.normalized() * (EGRESS_RADIUS * 0.4) \
			+ Vector3.UP * REATTACK_CLIMB
	_enter(Phase.REATTACK)


func _reattack(delta: float) -> void:
	_fly_toward(_reattack_point, delta)
	if _phase_time >= REATTACK_SECONDS \
			or global_position.distance_to(_reattack_point) < ARRIVE_RADIUS:
		_enter(Phase.RUN_IN)


## Payload spent: go home. Getting out is the ENEMY SURVIVING (A2), so it is a
## separate signal from being killed and the war prices it separately.
func _egress(delta: float) -> void:
	var away: Vector3 = global_position - route_end
	away.y = 0.0
	if away.length() < 1.0:
		away = -global_basis.z
	_fly_toward(global_position + away.normalized() * 40.0 + Vector3.UP * 4.0, delta)
	if global_position.distance_to(route_end) >= EGRESS_RADIUS \
			or _phase_time >= EGRESS_SECONDS:
		escaped.emit()
		queue_free()


func _enter(phase: int) -> void:
	_phase = phase
	_phase_time = 0.0


func _restart_run() -> void:
	global_position = _route_start
	velocity = Vector3.ZERO
	_health.revive()
	_enter(Phase.RUN_IN)


func _fly_toward(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	velocity = velocity.move_toward(offset.normalized() * enemy_config.speed,
			enemy_config.accel * delta)
	move_and_slide()


func _face_route(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 1.0:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z),
				1.0 - exp(-3.0 * delta))


## The shield is the type's whole readability problem: a player whose shots do
## nothing must be able to SEE why. The bubble is visible only while the shield
## holds, and flares on every absorbed hit.
## The shield is a barrier, not an overlay: when it is up you can neither shoot
## through it nor fly inside it, and when it drops both facts reverse at once.
func _update_shield_visual(delta: float) -> void:
	_shield_flash = maxf(_shield_flash - delta * 3.0, 0.0)
	var up: bool = _health.shielded()
	_shield_visual.visible = up
	if _shell_collision.disabled == up:
		_shell_collision.set_deferred(&"disabled", not up)
	if up:
		var material: StandardMaterial3D = \
				_shield_visual.get_surface_override_material(0) as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 0.6 + _shield_flash * 3.0


func _on_shield_absorbed(_amount: float) -> void:
	_shield_flash = 1.0
	# Stands in as a ricochet until the bank grows a dedicated shield sound.
	SoundBank.play_at(&"shot", global_position, -14.0, 0.4)


func _on_shield_broken() -> void:
	_shield_visual.visible = false
	_shell_collision.set_deferred(&"disabled", true)
	Effects.explosion(get_tree().root, global_position, 0.7)


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position, 2.0)
	destroyed.emit(enemy_config.points)
	queue_free()
