class_name FlakShell
extends Node3D

## A proximity-fused flak shell (GAMEPLAY-DESIGN P3.1, "Flak pod": shells
## detonate at computed range into a fragment cloud).
##
## It flies the bolt's flight path — manual integration with a segment raycast
## per step, so it cannot tunnel — but it never has to TOUCH anything. Once
## armed it bursts as soon as a hostile falls inside the fuse radius, and the
## burst damages every hostile inside the larger burst radius.
##
## THE GAP BETWEEN THE TWO RADII IS THE WEAPON. A fuse tighter than the burst
## lets the shell get *into* a cloud before it goes off, so the fragments come
## from the middle of the pack rather than off its near face. That is the whole
## P4.3 flak column in one geometric fact: it is not a gun that happens to
## splash, it is a weapon that is paid per BURST while the target is priced per
## BODY.
##
## Damage is FLAT inside the burst radius, deliberately. Layer 1 of the balance
## model (BALANCE.md) is "if this weapon connects, what happens", verified by
## planting shots into a real Health node. A falloff curve would make
## damage-per-connect a function of geometry — smearing a delivery concern into
## the lethality layer — and the planted-shot bench could no longer check the
## arithmetic at all.
##
## Instantiated and freed like the missile rather than pooled: the cycle is slow
## by design (P3.1, "auto, slow cycle"), so this is a couple of allocations a
## second, not the ten-a-second the bolt pool exists to absorb.

## Hostiles the burst sweeps. The same two groups weapon.gd's fire assist reads,
## for the same reason: they are the sets that carry take_hit. The sweep is
## hostile-only, so an ENEMY flak pod would need this generalized (the team
## check below is already written for it) — noted rather than pre-built.
const TARGET_GROUPS: Array[StringName] = [&"enemies", &"turrets"]

var _config: CombatConfig
var _pod: FlakPod
var _velocity: Vector3
var _team: StringName
var _exclude: Array[RID] = []
var _life: float = 0.0
var _travelled: float = 0.0
var _damage: float = 0.0

var _gravity_default: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(config: CombatConfig, pod: FlakPod, team: StringName,
		exclude: Array[RID], velocity: Vector3, damage: float) -> void:
	_config = config
	_pod = pod
	_team = team
	_exclude = exclude
	_velocity = velocity
	_damage = damage
	_life = config.flak_shell_lifetime
	_orient()


func _physics_process(delta: float) -> void:
	_velocity += Vector3.DOWN \
			* (_gravity_default * _config.flak_shell_gravity_scale * delta)
	var step: Vector3 = _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + step)
	query.exclude = _exclude
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		# Contact detonation. A shell that hits a wall still bursts there, which
		# is why flak works around cover and why a screamer degrading the fuse
		# to contact-only (P3.1) is a degradation rather than a disabling.
		global_position = hit["position"]
		_burst()
		return
	global_position += step
	_travelled += step.length()
	_orient()
	_life -= delta
	if _travelled >= _config.flak_arm_distance \
			and _hostile_within(_config.flak_fuse_radius):
		_burst()
		return
	if _life <= 0.0:
		# The airburst at the end of flight: the round self-destructs rather
		# than raining spent shells, and the effective range is therefore a
		# consequence of flight time and drop, not a hard cutoff.
		_burst()


## True when any hostile is inside `radius` of the shell. Distance is measured
## to the body's ORIGIN, so a large hull (the aegis is 3.4 m long) fuses a
## little later than its skin would suggest — an honest approximation, and
## uniform across types so no cell is quietly favoured.
func _hostile_within(radius: float) -> bool:
	var radius_squared: float = radius * radius
	for group: StringName in TARGET_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body: Node3D = node as Node3D
			if not _is_hostile(body):
				continue
			if body.global_position.distance_squared_to(global_position) \
					<= radius_squared:
				return true
	return false


func _is_hostile(body: Node3D) -> bool:
	return body != null and is_instance_valid(body) \
			and not body.is_queued_for_deletion() \
			and body.get("team") != _team and body.has_method("take_hit")


## The fragment cloud: flat damage to every hostile inside the burst radius,
## then report the yield to the pod. The two counters the pod keeps are what the
## delivery bench splits into `evasion` (did the burst ARRIVE) and `splash` (how
## many bodies one arriving burst covered) — see BALANCE.md Layer 2.
func _burst() -> void:
	var radius_squared: float = _config.flak_burst_radius * _config.flak_burst_radius
	var bodies: int = 0
	for group: StringName in TARGET_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body: Node3D = node as Node3D
			if not _is_hostile(body):
				continue
			if body.global_position.distance_squared_to(global_position) \
					> radius_squared:
				continue
			body.call("take_hit", _damage)
			bodies += 1
			if _team == &"player":
				Blackbox.log_event(&"hit", "flak", _damage, body.global_position)
	if is_instance_valid(_pod):
		_pod.report_burst(bodies)
	Effects.explosion(get_tree().root, global_position,
			_config.flak_burst_radius * 0.12)
	SoundBank.play_at(&"explosion", global_position, -9.0, 0.35)
	queue_free()


func _orient() -> void:
	var direction: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(direction, up)
