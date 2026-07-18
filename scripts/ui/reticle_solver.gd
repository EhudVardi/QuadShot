class_name ReticleSolver
extends RefCounted

## The FCS reticle's geometry, in one place (GAMEPLAY-DESIGN P3.6).
##
## The reticle's whole guarantee is that it mirrors weapon.gd and
## missile_system.gd exactly — it draws where bolts ACTUALLY go, so it never
## lies to the pilot. A guarantee like that survives exactly as long as there
## is one implementation of it, which is why this is a shared solver rather
## than something main.gd owns privately: the game draws it, and the matchup
## harness draws the same thing when you watch a duel. A copy would drift, and
## a drifted reticle is worse than none.
##
## Pure geometry: no nodes owned, no state kept. Hand it the scene's pieces and
## it returns screen-space numbers for hud.update_reticle().

## Ranges the fall-line arc is sampled at, meters.
const ARC_RANGES: Array[float] = [2.0, 8.0, 16.0, 26.0, 38.0, 52.0]
## Ranges that get a labelled tick.
const TICK_RANGES: Array[float] = [20.0, 35.0, 50.0]
## Pipper range when nothing is lined up to range against.
const DEFAULT_RANGE: float = 40.0
## Hostiles outside this cone of the gun line don't set the pipper's range.
const PIP_CONE_DEG: float = 9.0


## Everything hud.update_reticle() needs, or an empty Dictionary when there is
## nothing to draw (disarmed, no camera).
static func solve(camera: Camera3D, weapon: Weapon, drone: FlightController,
		config: CombatConfig, missiles: MissileSystem, tree: SceneTree,
		lock_cone_mult: float) -> Dictionary:
	if camera == null or weapon == null or drone == null or not drone.armed:
		return {}
	var direction: Vector3 = -weapon.global_basis.z
	var velocity: Vector3 = direction * config.muzzle_speed \
			+ drone.linear_velocity * config.inherit_velocity
	var origin: Vector3 = weapon.global_position + direction * 0.4
	var drop: float = ProjectSettings.get_setting("physics/3d/default_gravity") \
			* config.projectile_gravity_scale
	var center: Vector2 = camera.unproject_position(
			camera.global_position + direction * 20.0)

	var arc := PackedVector2Array()
	for r: float in ARC_RANGES:
		var point: Variant = bolt_screen_at_range(camera, origin, velocity, drop, r)
		if point != null:
			arc.append(point)

	var ticks: Array = []
	for r: float in TICK_RANGES:
		var point: Variant = bolt_screen_at_range(camera, origin, velocity, drop, r)
		if point != null:
			ticks.append({"pos": point, "label": "%dm" % int(r)})

	# The pipper sits at the bolt's screen position for the target's range — the
	# nearest hostile aligned with the gun, else a default range. No lead: the
	# pilot still leads a mover by hand (lead-compute is future FCS gear).
	var pip: Variant = bolt_screen_at_range(camera, origin, velocity, drop,
			target_range(tree, direction, origin))

	# Lock zone: the acquire cone, and the wider hold cone (1.5x — matching
	# missile_system.gd's hysteresis) out to which a lock is maintained.
	var cone_deg: float = config.missile_lock_cone_deg * lock_cone_mult
	var locked_target: Node3D = missiles.target if missiles != null else null
	return {
		"center": center,
		"pipper": pip if pip != null else center,
		"arc": arc,
		"ticks": ticks,
		"lock_radius": cone_screen_radius(camera, cone_deg),
		"hold_radius": cone_screen_radius(camera, cone_deg * 1.5),
		"lockable": locked_target != null and is_instance_valid(locked_target),
	}


## Screen position where a bolt is when it has travelled ~r meters (muzzle +
## inherited velocity + drop), or null if that point is behind the camera.
static func bolt_screen_at_range(camera: Camera3D, origin: Vector3,
		velocity: Vector3, drop: float, r: float) -> Variant:
	var t: float = r / maxf(velocity.length(), 1.0)
	var position: Vector3 = origin + velocity * t + Vector3.DOWN * (0.5 * drop * t * t)
	if camera.is_position_behind(position):
		return null
	return camera.unproject_position(position)


## Range to the hostile most aligned with the gun, for the pipper; the default
## range when nothing is lined up.
static func target_range(tree: SceneTree, aim: Vector3, origin: Vector3) -> float:
	var best_range: float = DEFAULT_RANGE
	var best_angle: float = deg_to_rad(PIP_CONE_DEG)
	for hostile: Node in tree.get_nodes_in_group(&"enemies") \
			+ tree.get_nodes_in_group(&"turrets"):
		var body: Node3D = hostile as Node3D
		if body == null or not is_instance_valid(body) \
				or body.is_queued_for_deletion():
			continue
		var to_body: Vector3 = body.global_position - origin
		var angle: float = aim.angle_to(to_body)
		if angle < best_angle:
			best_angle = angle
			best_range = to_body.length()
	return best_range


## Screen radius of the missile lock cone (a cone_deg off-axis point projected).
static func cone_screen_radius(camera: Camera3D, cone_deg: float) -> float:
	var forward: Vector3 = -camera.global_basis.z
	var edge: Vector3 = forward.rotated(camera.global_basis.x, deg_to_rad(cone_deg))
	var edge_point: Vector3 = camera.global_position + edge * 25.0
	if camera.is_position_behind(edge_point):
		return 0.0
	var center: Vector2 = camera.unproject_position(
			camera.global_position + forward * 25.0)
	return center.distance_to(camera.unproject_position(edge_point))
