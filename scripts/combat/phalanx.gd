class_name Phalanx
extends CharacterBody3D

## Phalanx — the heavy gunship (GAMEPLAY-DESIGN A7, roster type EIGHT).
##
## THE ESCALATION ANCHOR, and it exists to close a hole the user named while
## answering A.q1: *"in order to 'feel' an escalation we must introduce tougher
## enemies, and not simply spawn more and more raiders. however if it means we
## deploy an enemy unit that has no reason to be there it breaks the immersion."*
## Once the aegis correctly left defensive garrisons, `HEAVY_TYPES` held a bomber
## that is never there and a jammer with no weapon — so *"the war escalates"*
## meant *"the war gets foggier"* and nothing else. The roster had no heavy
## DEFENDER. This is it, and a besieged enemy digging in behind heavier hardware
## is immersive in exactly the way a bomber parked in its own back yard is not.
##
## The user's own sketch: *"a heavy frame that moves slower and has multiple
## turrets that fire at me at the same time, something like the aegis but faster,
## carrying a shield/force field, and has multiple vectors of attack."*
##
## ---------------------------------------------------------------------------
## THE SHIELD IS AN ARC THAT CHASES ITS ATTACKER, AND THAT IS THE WHOLE TYPE
## ---------------------------------------------------------------------------
##
## The aegis's screen asks **what are you shooting with** — a damage threshold no
## chip gun can cross. This one asks **where are you shooting from**. The arc
## slews toward whatever last hurt it (`shield_slew_deg_s`), so:
##
##   park in one orbit slot  -> the arc catches up -> your damage stops landing
##   keep moving around it   -> the arc lags       -> your damage lands
##
## Meanwhile every surviving mount fires at you from wherever you are, so moving
## does not make you SAFE — it decides whether your shots count. That tension is
## the design: there is no slot that is both safe and useful, which is what P4.2
## means by the anti-orbit type. It punishes the peel-and-kill rhythm the raider
## deliberately allows.
##
## Two shielded enemies that wanted the same answer would be one enemy. These two
## are countered on different axes on purpose, and neither counter helps with the
## other.
##
## ---------------------------------------------------------------------------
## THE MOUNTS ARE DESTRUCTIBLE, on the user's call (2026-08-07)
## ---------------------------------------------------------------------------
##
## Shooting it from a bearing damages the mount covering that bearing until the
## mount dies, and only then the hull. So a long fight visibly degrades it and
## the incoming volume falls as you work — a heavy enemy whose threat only ends
## when its health bar does is a health bar.
##
## THE ARC IS TAKEN FROM WHERE THE PLAYER IS, not from the projectile. `take_hit`
## carries a damage number and nothing else — that is the project-wide contract
## and it is worth keeping — so the bearing is derived from the attacker's own
## position at the moment of the hit. It costs no new plumbing and it behaves
## identically for a bolt, a missile and a splash, which a velocity-derived
## bearing would not.
##
## Counter-web (P4.3): stand-off `++` (hit it from outside its guns' comfort),
## burst `+` (a mount is cheap to strip in one pass), chip gun `-` (it out-heals
## a trickle through the arc), terrain `++` (cover is how you cross its open
## ground). Frame pressure (P4.4): light `++` (out-slew the arc), heavy `--` (it
## cannot leave the shielded side fast enough to matter).

signal destroyed(points: float)
## One mount went. Points for the mount, and a HUD or a check can watch the
## fight degrade rather than inferring it from a health bar.
signal mount_destroyed(points: float)

## Encounter-design constants (not flight/input physics). Everything a designer
## would TUNE lives in EnemyConfig; these are shape.
##
## How long a mount must hold the target before its first shot. THE TELEGRAPH,
## and A7 asks for it by name — *"the telegraph is spin-up, turrets tracking
## before they fire, so the commitment is visible"*. A heavy that opens up the
## instant it sees you is a reflex test; one that visibly winds up is a decision.
const SPINUP_SECONDS: float = 0.9
## Aim cone a mount must be inside before it will fire.
const AIM_TOLERANCE_DEG: float = 5.0
## How far it drifts from where it was placed. It HOLDS GROUND AND DENIES IT
## (A7: *"it does not chase"*), so this is a leash rather than a pursuit range —
## it repositions inside its own patch and never follows you home.
const STATION_DRIFT_M: float = 14.0
## Preferred height above its station, so it looks down over what it guards.
const STATION_HEIGHT: float = 4.0
const MIN_ALTITUDE: float = 3.0
## Emissive energy of a mount at rest and fully spun up. Bloom threshold is 1.0,
## so the rest value is a dull ember and the ready value is a lamp.
const MOUNT_ENERGY_REST: float = 0.4
const MOUNT_ENERGY_READY: float = 5.0
## Shield shell opacity when the screen is full, and when it is spent.
const SHELL_ALPHA_FULL: float = 0.30
const SHELL_ALPHA_SPENT: float = 0.02

@export var enemy_config: EnemyConfig
## Per-instance seed, set before the node enters the tree (P4.8 determinism).
@export var ai_seed: int = -1

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _health: Health = $Health
@onready var _mounts_root: Node3D = $Visual/Mounts
@onready var _shell: MeshInstance3D = $Visual/Shell

var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _pool: ProjectilePool
var _home: Vector3
## Where the screen is pointing, flat and unit length. Chases `_threat_bearing`.
var _shield_dir: Vector3 = Vector3.FORWARD
## The bearing the last hit came from, which is what the screen steers for.
var _threat_bearing: Vector3 = Vector3.FORWARD
var _shell_material: StandardMaterial3D

## One entry per mount. Parallel arrays rather than a Mount class: the whole of a
## mount's state is three numbers and a node, and a class would be a file to open
## before you can read this one.
var _mount_nodes: Array[Node3D] = []
var _mount_materials: Array[StandardMaterial3D] = []
var _mount_hull: Array[float] = []
var _mount_spinup: Array[float] = []
var _mount_cooldown: Array[float] = []
## The bearing each mount sits on, in the body's own frame — used to decide which
## mount an attacker is shooting at.
var _mount_bearing: Array[Vector3] = []


func _ready() -> void:
	add_to_group(&"enemies")
	_home = global_position
	if ai_seed >= 0:
		_rng.seed = ai_seed
	else:
		_rng.randomize()
	_health.max_health = enemy_config.hull
	_health.configure_defenses(enemy_config)
	_health.revive()
	_health.died.connect(_on_died)
	_shell_material = _shell.get_surface_override_material(0) as StandardMaterial3D
	_build_mounts()
	# It faces its own patch until something teaches it otherwise, so a Phalanx
	# nobody has shot at yet is not silently shielded against the way in.
	_shield_dir = -global_basis.z
	_shield_dir.y = 0.0
	if _shield_dir.length() < 0.01:
		_shield_dir = Vector3.FORWARD
	_shield_dir = _shield_dir.normalized()
	_threat_bearing = _shield_dir


## THE MOUNTS, laid evenly around the body so there is no bearing without a gun
## on it. A7's *"no blind side you can simply sit in"* is this loop.
func _build_mounts() -> void:
	var count: int = maxi(enemy_config.mount_count, 0)
	var template: Node3D = _mounts_root.get_child(0) as Node3D if \
			_mounts_root.get_child_count() > 0 else null
	if template == null:
		return
	for i: int in count:
		var mount: Node3D = template.duplicate() as Node3D
		var angle: float = TAU * float(i) / float(count)
		var bearing := Vector3(sin(angle), 0.0, -cos(angle))
		mount.position = bearing * 1.15
		mount.rotation.y = angle
		mount.visible = true
		_mounts_root.add_child(mount)
		var mesh: MeshInstance3D = mount.get_node_or_null(^"Barrel") as MeshInstance3D
		var material: StandardMaterial3D = null
		if mesh != null and mesh.mesh != null \
				and mesh.mesh.material is StandardMaterial3D:
			# Per-instance, so one mount lighting up does not light the ring.
			material = (mesh.mesh.material as StandardMaterial3D).duplicate() \
					as StandardMaterial3D
			mesh.material_override = material
		_mount_nodes.append(mount)
		_mount_materials.append(material)
		_mount_hull.append(enemy_config.mount_hull)
		_mount_spinup.append(0.0)
		_mount_cooldown.append(0.0)
		_mount_bearing.append(bearing)
	template.visible = false


## How many mounts can still shoot. Public because it IS the fight's progress
## bar — a check asserts it falls, and a HUD would want the same answer.
func mounts_alive() -> int:
	var alive: int = 0
	for hull: float in _mount_hull:
		if hull > 0.0:
			alive += 1
	return alive


## Where the screen is pointing, flat and unit length. Public for the same reason
## `Lance.warning_level()` is: it is a design decision rather than an internal,
## and a headless check cannot see a shield but can assert the vector.
func shield_facing() -> Vector3:
	return _shield_dir


## Is a hit arriving from `bearing` (a flat unit vector FROM the body TOWARD the
## attacker) covered by the screen?
func shield_covers(bearing: Vector3) -> bool:
	if enemy_config.shield_arc_deg <= 0.0 or not _health.shielded():
		return false
	# A 360-degree arc means ALL ROUND, and it needs saying rather than falling
	# out of the comparison. `Vector3.angle_to` computes in 32-bit floats, so two
	# opposed vectors give 3.14159274 while `deg_to_rad(360) * 0.5` gives the
	# 64-bit 3.14159265 — and the larger one loses, leaving a configuration that
	# reads "covered from every side" with a hairline gap directly astern. Found
	# by a mutation landing exactly on it.
	if enemy_config.shield_arc_deg >= 360.0:
		return true
	return _shield_dir.angle_to(bearing) <= deg_to_rad(enemy_config.shield_arc_deg) * 0.5


func _physics_process(delta: float) -> void:
	_player = _find_player()
	_slew_shield(delta)
	_update_shell()
	_hold_station(delta)
	if _player == null:
		_cool_mounts(delta)
		return
	for i: int in _mount_nodes.size():
		_drive_mount(i, delta)


## IT HOLDS GROUND. Drifts around its own station rather than closing on the
## player, so the counterplay is to leave and come back on a different bearing —
## which is the whole reason the shield's slew rate means anything.
func _hold_station(delta: float) -> void:
	var target: Vector3 = _home + Vector3.UP * STATION_HEIGHT
	if _player != null:
		# Face the fight from its own patch: it will slide within the leash to
		# keep a standoff, and no further.
		var toward: Vector3 = _player.global_position - _home
		toward.y = 0.0
		if toward.length() > enemy_config.preferred_range:
			target = _home + toward.normalized() * minf(STATION_DRIFT_M,
					toward.length() - enemy_config.preferred_range) \
					+ Vector3.UP * STATION_HEIGHT
	target.y = maxf(target.y, MIN_ALTITUDE)
	var offset: Vector3 = target - global_position
	var desired: Vector3 = offset.normalized() * minf(offset.length() * 1.5,
			enemy_config.speed) if offset.length() > 0.05 else Vector3.ZERO
	velocity = velocity.move_toward(desired, enemy_config.accel * delta)
	move_and_slide()


## The screen chases whatever last hurt it, at its own rate and no faster. A
## `shield_slew_deg_s` high enough to always face the attacker would make the
## type unkillable from any bearing; that is the failure mode, and it is a config
## value rather than a hidden constant so it can be found and moved.
func _slew_shield(delta: float) -> void:
	if enemy_config.shield_arc_deg <= 0.0:
		return
	var error: float = _shield_dir.angle_to(_threat_bearing)
	if error <= 0.0001:
		return
	var axis: Vector3 = _shield_dir.cross(_threat_bearing)
	if axis.length_squared() < 1.0e-12:
		axis = Vector3.UP
	var step: float = minf(error, deg_to_rad(enemy_config.shield_slew_deg_s) * delta)
	_shield_dir = _shield_dir.rotated(axis.normalized(), step).normalized()


## THE SCREEN, SEEN. The shell is oriented to the arc and fades with the pool, so
## what the player reads is where their shots will stop and how much is left —
## the screamer's rule that a cue must be the mechanic rather than a proxy.
func _update_shell() -> void:
	if _shell_material == null:
		return
	if enemy_config.shield_arc_deg <= 0.0 or enemy_config.shield_max <= 0.0:
		_shell.visible = false
		return
	var fraction: float = _health.shield / maxf(enemy_config.shield_max, 0.01)
	_shell.visible = fraction > 0.01
	_shell.global_rotation.y = atan2(_shield_dir.x, _shield_dir.z)
	var colour: Color = _shell_material.albedo_color
	colour.a = lerpf(SHELL_ALPHA_SPENT, SHELL_ALPHA_FULL, fraction)
	_shell_material.albedo_color = colour
	_shell_material.emission_energy_multiplier = 0.2 + fraction * 1.6


## One mount: track, spin up, fire. Every living mount engages independently, so
## the volume of fire IS the number still standing.
func _drive_mount(index: int, delta: float) -> void:
	_mount_cooldown[index] = maxf(_mount_cooldown[index] - delta, 0.0)
	if _mount_hull[index] <= 0.0:
		return
	if _pool == null:
		_pool = get_tree().get_first_node_in_group(&"projectile_pool") as ProjectilePool
	var mount: Node3D = _mount_nodes[index]
	var range_m: float = global_position.distance_to(_player.global_position)
	if range_m > enemy_config.sight_range or not _engageable():
		_mount_spinup[index] = maxf(_mount_spinup[index] - delta, 0.0)
		_set_mount_glow(index, _mount_spinup[index] / SPINUP_SECONDS)
		return
	var lead: Vector3 = _lead_position()
	_track_mount(mount, lead, delta)
	if not _mount_aimed(mount, lead):
		# Lost the line: the wind-up bleeds away rather than resetting, so a
		# jinking pilot degrades it continuously instead of flipping a switch.
		_mount_spinup[index] = maxf(_mount_spinup[index] - delta, 0.0)
		_set_mount_glow(index, _mount_spinup[index] / SPINUP_SECONDS)
		return
	_mount_spinup[index] = minf(_mount_spinup[index] + delta, SPINUP_SECONDS)
	_set_mount_glow(index, _mount_spinup[index] / SPINUP_SECONDS)
	if _mount_spinup[index] < SPINUP_SECONDS or _mount_cooldown[index] > 0.0:
		return
	if _pool == null:
		return
	_fire_mount(mount)
	_mount_cooldown[index] = 1.0 / maxf(enemy_config.fire_rate, 0.01)


func _cool_mounts(delta: float) -> void:
	for i: int in _mount_nodes.size():
		_mount_cooldown[i] = maxf(_mount_cooldown[i] - delta, 0.0)
		_mount_spinup[i] = maxf(_mount_spinup[i] - delta, 0.0)
		_set_mount_glow(i, _mount_spinup[i] / SPINUP_SECONDS)


## A dead player, a disarmed one, or one behind cover is not engaged. The turret
## precedent exactly: the spawn pad has to be safe.
func _engageable() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if not _player.visible:
		return false
	var armed: Variant = _player.get(&"armed")
	if armed is bool and not (armed as bool):
		return false
	return true


func _lead_position() -> Vector3:
	var flight_time: float = global_position.distance_to(_player.global_position) \
			/ maxf(enemy_config.muzzle_speed, 1.0)
	var player_velocity := Vector3.ZERO
	var linear: Variant = _player.get(&"linear_velocity")
	if linear is Vector3:
		player_velocity = linear as Vector3
	return _player.global_position + player_velocity * flight_time


func _track_mount(mount: Node3D, point: Vector3, delta: float) -> void:
	var desired: Vector3 = point - mount.global_position
	var current: Vector3 = -mount.global_basis.z
	var angle: float = current.angle_to(desired)
	if angle < 0.0001:
		return
	var axis: Vector3 = current.cross(desired)
	if axis.length_squared() < 0.000001:
		axis = Vector3.UP
	var step: float = minf(angle, deg_to_rad(enemy_config.turn_speed_deg) * delta)
	mount.global_basis = (Basis(axis.normalized(), step)
			* mount.global_basis).orthonormalized()


func _mount_aimed(mount: Node3D, point: Vector3) -> bool:
	return (-mount.global_basis.z).angle_to(point - mount.global_position) \
			< deg_to_rad(AIM_TOLERANCE_DEG)


func _fire_mount(mount: Node3D) -> void:
	var direction: Vector3 = -mount.global_basis.z
	if enemy_config.aim_jitter_deg > 0.0:
		var spread: float = deg_to_rad(enemy_config.aim_jitter_deg)
		direction = direction.rotated(Vector3.UP,
				_rng.randf_range(-spread, spread)).rotated(
				direction.cross(Vector3.UP).normalized(),
				_rng.randf_range(-spread, spread))
	var lifetime: float = enemy_config.sight_range \
			/ maxf(enemy_config.muzzle_speed, 1.0) * 1.6
	_pool.fire(mount.global_position + direction * 0.6,
			direction * enemy_config.muzzle_speed,
			enemy_config.damage, team, [get_rid()], 0.0, lifetime)
	SoundBank.play_at(&"shot", mount.global_position, -6.0, 0.2)


func _set_mount_glow(index: int, amount: float) -> void:
	var material: StandardMaterial3D = _mount_materials[index]
	if material == null:
		return
	if _mount_hull[index] <= 0.0:
		material.emission_energy_multiplier = 0.0
		return
	material.emission_energy_multiplier = lerpf(MOUNT_ENERGY_REST,
			MOUNT_ENERGY_READY, clampf(amount, 0.0, 1.0))


## THE LAYERS, in the order a round meets them: screen, then the mount covering
## the bearing you are shooting from, then the hull.
##
## The bearing comes from the ATTACKER'S POSITION rather than from the round.
## `take_hit(damage)` carries a number and nothing else — that is the contract
## every weapon in the game speaks — so deriving the arc here costs no new
## plumbing and behaves identically for a bolt, a missile and a splash. A
## velocity-derived bearing would disagree with all three.
func take_hit(damage: float) -> void:
	var bearing: Vector3 = _attack_bearing()
	# Anything that lands teaches it where you are, INCLUDING a round the screen
	# stopped — otherwise a shielded hit would be free information denied.
	_threat_bearing = bearing
	if shield_covers(bearing):
		_health.take(damage)
		return
	var index: int = _mount_facing(bearing)
	if index >= 0 and _mount_hull[index] > 0.0:
		_damage_mount(index, damage)
		return
	# Past the screen and past the guns: the hull, with the screen bypassed
	# rather than spent, because it is not in the way.
	_health.take(damage, false)


## Flat unit vector from the body toward whoever is shooting. Falls back to the
## screen's own facing when there is no player, so a hit with nobody on the field
## (a check, a stray splash) resolves rather than dividing by zero.
func _attack_bearing() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return _shield_dir
	var offset: Vector3 = _player.global_position - global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		return _shield_dir
	return offset.normalized()


## The mount sitting closest to the bearing being shot from — the one the
## attacker can actually see. Skips dead mounts, so stripping one exposes the
## hull on that side rather than silently handing the damage to a neighbour.
func _mount_facing(bearing: Vector3) -> int:
	var local: Vector3 = global_basis.inverse() * bearing
	local.y = 0.0
	if local.length() < 0.01:
		return -1
	local = local.normalized()
	var best: int = -1
	var best_angle: float = INF
	for i: int in _mount_bearing.size():
		if _mount_hull[i] <= 0.0:
			continue
		var angle: float = (_mount_bearing[i] as Vector3).angle_to(local)
		if angle < best_angle:
			best_angle = angle
			best = i
	return best


func _damage_mount(index: int, damage: float) -> void:
	_mount_hull[index] = maxf(_mount_hull[index] - damage, 0.0)
	if _mount_hull[index] > 0.0:
		return
	var mount: Node3D = _mount_nodes[index]
	Effects.explosion(get_tree().root, mount.global_position, 0.8)
	mount.visible = false
	_set_mount_glow(index, 0.0)
	# A fraction of the body's worth, so stripping the guns is progress that
	# scores rather than a chore you do before the kill.
	mount_destroyed.emit(enemy_config.points * 0.15)


func _find_player() -> Node3D:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not is_instance_valid(player) or not (player is Node3D):
		return null
	return player as Node3D


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position, 2.2)
	destroyed.emit(enemy_config.points)
	queue_free()
