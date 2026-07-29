class_name Weapon
extends Node3D

## Player blaster. Mounted under the FPV camera so it fires along the view
## axis — the screen-center reticle is always truthful, regardless of camera
## uptilt. Fires only while armed.

@export var combat_config: CombatConfig

## Test hook (scripts/tests/combat_check.gd): forces the trigger down.
var fire_override: bool = false

## Seconds since the gun director last had a firing solution; 0 at spawn (the
## director gets the benefit of the doubt) and growing whenever it is silent.
##
## THIS IS THE HONEST SIGNAL FOR "IS THE DIRECTOR WORKING", and it replaced a
## threshold on the solution WINDOW that was measured wrong. v1.83 guessed that a
## window under 0.25 m meant a silent director; the duels then showed the pilot
## deferring to a 0.43 m window and firing **one round in ten seconds** against a
## screamer — nominally assisted, actually mute. A window is an input to the
## director's decision; how often it decides to fire is the thing that matters,
## and only one of those two can be observed without guessing.
##
## Deliberately NOT affected by anyone pulling the trigger manually: it counts the
## DIRECTOR's solutions, so a pilot that has taken the trigger back cannot make
## the director look busy and flip itself back — the feedback loop that a
## shots-fired counter would have created.
var director_idle_s: float = 0.0

## Bolts fired since spawn — the delivery benches' denominator (BALANCE.md
## Layer 2: aim_quality and evasion are both hits-per-shot ratios).
var shots_fired: int = 0

var _cooldown: float = 0.0
var _drone: FlightController
var _pool: ProjectilePool


func _ready() -> void:
	_drone = owner as FlightController


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _pool == null:
		_pool = get_tree().get_first_node_in_group(&"projectile_pool") as ProjectilePool
		if _pool == null:
			return
	# Evaluated every tick rather than short-circuited behind the trigger, so
	# `director_idle_s` describes the DIRECTOR and not "the director on the ticks
	# nobody happened to be shooting". Costs one extra sweep per tick while a
	# trigger is held; the sweep is already bounded and skipped entirely when the
	# director is unequipped (the first line of _assist_solution).
	var assist: bool = _assist_solution()
	director_idle_s = 0.0 if assist else director_idle_s + delta
	var trigger_down: bool = fire_override or Input.is_action_pressed(&"fire")
	if _drone.armed and _cooldown <= 0.0 and (trigger_down or assist):
		_fire()
		_cooldown = 1.0 / (combat_config.fire_rate * RunMods.current.fire_rate_mult)


## The gun director's EFFECTIVE solution window right now, meters. The configured
## threshold is what the equipment offers; this is what survives the electronic
## environment it is being flown in.
##
## 0 when unequipped, and shrunk toward 0 by a screamer's jam (P4.2: "FCS
## solutions degrade, gun director confidence collapses"). Graded rather than
## switched, so flying INTO a bubble reads as an assist quietly getting worse
## before it stops — see jamming.gd for why the gradient is the user's call.
func director_window() -> float:
	return maxf(combat_config.fire_assist_miss_m, 0.0) \
			* (1.0 - Jamming.level_at(self))


## Is there a gun director EQUIPPED at all? A different and much weaker question
## than "is it working" — see `director_idle_s`, which is the one a brain deciding
## whether to take its own trigger should be asking.
func director_active() -> bool:
	return director_window() > 0.0


## Fire-control assist (FCS prototype): true when some hostile's predicted
## miss distance — the real ballistic arc (muzzle + inherited velocity +
## drop) swept against the target's linear motion — falls under the
## effective threshold. The pilot's job becomes putting the drone at the
## right point in space; the trigger stops competing with flying.
func _assist_solution() -> bool:
	var window: float = director_window()
	if window <= 0.0:
		return false
	var direction: Vector3 = -global_basis.z
	var origin: Vector3 = global_position + direction * 0.4
	var velocity: Vector3 = direction * combat_config.muzzle_speed \
			+ _drone.linear_velocity * combat_config.inherit_velocity
	var drop: float = ProjectSettings.get_setting("physics/3d/default_gravity") \
			* combat_config.projectile_gravity_scale
	var space := get_world_3d().direct_space_state
	var hostiles: Array[Node] = get_tree().get_nodes_in_group(&"enemies") \
			+ get_tree().get_nodes_in_group(&"turrets")
	for hostile: Node in hostiles:
		var body: Node3D = hostile as Node3D
		if body == null or not is_instance_valid(body) \
				or body.is_queued_for_deletion():
			continue
		var to_target: Vector3 = body.global_position - origin
		if to_target.length() > combat_config.fire_assist_range \
				or to_target.normalized().dot(direction) < 0.2:
			continue
		# Don't volley into walls: require line of sight to the hostile.
		var query := PhysicsRayQueryParameters3D.create(origin, body.global_position)
		query.exclude = [_drone.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] != body:
			continue
		var raw_velocity: Variant = body.get("velocity")
		var target_velocity: Vector3 = raw_velocity if raw_velocity is Vector3 \
				else Vector3.ZERO
		# Sweep the projectile's arc against the target's predicted motion.
		var t: float = 0.0
		while t < combat_config.projectile_lifetime:
			var projectile: Vector3 = origin + velocity * t \
					+ Vector3.DOWN * (0.5 * drop * t * t)
			if (projectile - origin).length() > combat_config.fire_assist_range:
				break
			var predicted: Vector3 = body.global_position + target_velocity * t
			if projectile.distance_to(predicted) < window:
				return true
			t += 0.02
	return false


func _fire() -> void:
	shots_fired += 1
	Blackbox.log_event(&"fired", "blaster")
	var direction: Vector3 = -global_basis.z
	var velocity: Vector3 = direction * combat_config.muzzle_speed \
			+ _drone.linear_velocity * combat_config.inherit_velocity
	# Spawn clear of the drone's own collider (also excluded by RID).
	var origin: Vector3 = global_position + direction * 0.4
	_pool.fire(origin, velocity,
			combat_config.projectile_damage * RunMods.current.damage_mult, _drone.team,
			[_drone.get_rid()], combat_config.projectile_gravity_scale,
			combat_config.projectile_lifetime)
	SoundBank.play_at(&"shot", origin, -6.0, 0.12)
