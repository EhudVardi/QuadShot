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
## THE SCREEN IS TWO COUNTER-ROTATING SHELLS, AND TIMING IS THE WHOLE TYPE
## ---------------------------------------------------------------------------
##
## This replaces a tracking arc (v2.34/v2.35) that WORKED and could not be READ.
## A.q10 is the record: the user reported it as a bug twice, the second report
## was measured and the mechanic was correct, and *"a mechanic that reads as
## broken while it is working is a failed mechanic"*. Their call was to replace
## it: *"move away from a dynamically directional shield and do another option
## you've suggested - a rotating shield that needs good timing to penetrate...
## rotating around the ship in some patterns that can confuse the attacker."*
##
## The aegis's screen asks **what are you shooting with** — a damage threshold no
## chip gun can cross. This one asks **when are you shooting**. Two nested shells
## of slotted armour turn at their own rates in opposite directions, and a round
## reaches the body only when a slot in EACH is on its bearing at the same
## instant.
##
## IT IS A BARRIER, NOT A BATTERY, and that is a deliberate break from the aegis.
## A blocked round is REFUSED — nothing is spent and the screen never falls, so
## `shield_max` is 0 on this type. The arc it replaces was a 300-point pool that
## a blaster emptied in about a second, after which the mechanic simply stopped
## happening; a rotating screen that evaporated the same way would have been
## just as unreadable, for the same reason.
##
## WHY TWO SHELLS. A single rotating ring does NOT punish a stationary orbit: you
## park in one slot and fire every time the gap comes round, which is exactly the
## peel-and-kill rhythm P4.2 gives this type the job of refusing. Two shells at
## incommensurate rates make the alignment on a FIXED bearing rare and irregular,
## while flying WITH one shell's rotation parks you inside its slot and leaves
## only the other one to time. So the counter is *fly with the pattern*, camping
## is punished, and the anti-orbit property the tracking carried is preserved by
## a mechanism the player can SEE.
##
## Meanwhile every surviving mount fires at you from wherever you are, so moving
## does not make you SAFE — it decides whether your shots count. There is still
## no slot that is both safe and useful.
##
## ---------------------------------------------------------------------------
## THE STERN VENT — the third skill, and the one that is aim
## ---------------------------------------------------------------------------
##
## *"a small weak point at the back of the ship, requiring some skilled accurate
## firing to make use of."* A round that hits the vent plate while the vent is
## OPEN goes straight to the hull, past the screen and past the guns.
##
## IT OPENS ON A WINDOW, which was the user's answer to the objection that a
## permanently exposed stern is a camping spot that would make the rotation
## decoration: *"it should be a small caveat of the entire fortress. i think it
## should be opened for a window of time."*
##
## THE APERTURE IS CUT THROUGH BOTH SHELLS while it lasts, so the hole is
## geometrically real and the picture never contradicts the rule. And the plate
## is a SMALL PHYSICAL BODY rather than a bearing test, which is what makes this
## the accuracy skill rather than a second positioning one: you must be astern
## (position), during the window (timing), and actually put rounds on a 1.6 m
## plate at range (aim). A splash weapon cannot exploit it; a direct-fire gun in
## steady hands can.
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
## Counter-web (P4.3), REWRITTEN WITH THE MECHANIC (A.q10) — the counters used to
## be *out-slew the arc* and they are now *time the pattern* and *hit the vent*:
## chip gun `+` (was `-`: a sustained, precisely-aimed gun is the only thing that
## can spend a two-second slot or a stern window, and it never runs dry doing it),
## burst `0` (a slot is a duration, not a moment, so a single heavy round wastes
## most of an opening it paid to reach), missile `+` (it arrives on its own line,
## but a lock spent while the shell is shut is a lock wasted), flak `-` (was `+`:
## splash cannot exploit a 1.6 m vent plate and a wide burst is mostly stopped by
## the panels around the slot), terrain `+` (cover still crosses its open ground,
## but it no longer helps you reach a blind side, because there is not one).
##
## Frame pressure (P4.4): light `+`, heavy `0`. THIS IS THE LINE THE REWORK
## MOVED. Beating a tracking arc was a slew race and the Atlas could not win one,
## so the heavy column was `--`. Timing a rotating shell is not a race — a heavy
## frame holds a gun line BETTER, which is worth more against a two-second slot
## and worth much more against a small plate at range. The light frame keeps the
## edge because matching a shell's rotation is a speed problem, so the gap
## narrows rather than inverting.

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
## How far out from the centreline the guns sit. A fortress wears its battery on
## the beam; the user flew the first version and found the mounts *"too small to
## individually take down"*, which was scale as much as hull.
const MOUNT_RING_M: float = 3.4
const MOUNT_ENERGY_REST: float = 0.4
const MOUNT_ENERGY_READY: float = 5.0
## Shells in the screen. A COUNT rather than a config field because it is shape:
## the numbers that make a pattern are per-shell and they are all tunable, but
## "how many shells" changes the scene, so it cannot be a slider.
const RING_COUNT: int = 2
## Radius of the innermost shell, metres. It must match the scene, and it is
## duplicated here for one reason: an attacker INSIDE it is past the screen, and
## without that the picture would lie to anyone who flew in through a slot.
const SCREEN_INNER_RADIUS_M: float = 5.3
## How long a splash stays lit on the panel that stopped a round.
const SPLASH_DECAY_S: float = 6.0
## Emissive energy of the stern vent plate: cold and shut, about to open, open.
const VENT_ENERGY_SHUT: float = 0.15
const VENT_ENERGY_READY: float = 1.6
const VENT_ENERGY_OPEN: float = 7.0

@export var enemy_config: EnemyConfig
## Per-instance seed, set before the node enters the tree (P4.8 determinism).
@export var ai_seed: int = -1

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _health: Health = $Health
@onready var _mounts_root: Node3D = $Visual/Mounts
@onready var _shells_root: Node3D = $Visual/Shells
@onready var _vent: ShieldShell = $SternVent
@onready var _vent_mesh: MeshInstance3D = $SternVent/Mesh

var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _pool: ProjectilePool
var _home: Vector3

## Rotation of each shell, radians. THE WHOLE STATE OF THE SCREEN — the hit test
## and the shader are both derived from exactly these two numbers, so the
## picture cannot disagree with the mechanic.
var _ring_phase: Array[float] = []
var _ring_material: Array[ShaderMaterial] = []
## Seconds through the vent's open/shut cycle.
var _vent_clock: float = 0.0
var _vent_material: StandardMaterial3D
## Splash: where the last refused round hit, and how bright it still is.
var _splash_dir: Vector3 = Vector3.BACK
var _splash: float = 0.0

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
	_build_mounts()
	_build_screen()
	_vent.hit.connect(_on_vent_hit)
	_vent_material = _vent_mesh.get_surface_override_material(0) as StandardMaterial3D
	# THE VENT PLATE IS A SEPARATE PHYSICS BODY BOLTED TO THIS ONE, and without
	# this line `move_and_slide` fights its own child: the plate sits off-centre
	# at the stern and overlaps the hull's shape, so depenetration pushed the
	# fortress along its own keel. MEASURED, because it looked like an AI bug —
	# station drift 0.0 m with the plate's collider disabled against **49.6 m in
	# 5 seconds** with it on, sliding away from the player at the type's full
	# 5 m/s. The aegis gets away with the same arrangement only because its shield
	# sphere is centred on the body, so its depenetration cancels; that is luck
	# rather than design, and it is worth knowing before the next body grows a
	# second collider.
	add_collision_exception_with(_vent)


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
		# Out on the beam, clear of the superstructure, so each gun is a target you
		# can pick out and shoot at rather than a detail on the hull.
		mount.position = bearing * MOUNT_RING_M
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


## THE SCREEN, BUILT. One sphere per shell, each carrying its own instance of
## `shield_rings.gdshader` — the slots are cut in the fragment shader from the
## same phase the hit test reads, so the hole you can see through IS the hole
## your rounds go through.
func _build_screen() -> void:
	for i: int in RING_COUNT:
		_ring_phase.append(0.0)
		_ring_material.append(null)
		var shell: MeshInstance3D = _shells_root.get_child(i) as MeshInstance3D \
				if _shells_root.get_child_count() > i else null
		if shell == null:
			continue
		# Per-instance: two shells sharing one material would share a phase, and
		# the whole pattern is the two of them disagreeing.
		var material: ShaderMaterial = (shell.get_surface_override_material(0)
				as ShaderMaterial).duplicate() as ShaderMaterial
		shell.set_surface_override_material(0, material)
		_ring_material[i] = material
		# A RANDOM START PHASE PER BODY, so two Phalanxes in one garrison do not
		# present the same pattern at the same instant and a pilot cannot learn
		# one rhythm and apply it to the field. Seeded, so a check still gets the
		# same fight twice (P4.8 determinism).
		_ring_phase[i] = _rng.randf() * TAU


## Slots in shell `index`. Zero means this type has no such shell — which is
## every other type in the roster, and is how the whole mechanic switches off
## from a config.
func _ring_gaps(index: int) -> int:
	return enemy_config.shield_outer_gaps if index == 0 \
			else enemy_config.shield_inner_gaps


func _ring_gap_deg(index: int) -> float:
	return enemy_config.shield_outer_gap_deg if index == 0 \
			else enemy_config.shield_inner_gap_deg


func _ring_rate_deg_s(index: int) -> float:
	return enemy_config.shield_outer_rate_deg_s if index == 0 \
			else enemy_config.shield_inner_rate_deg_s


## Where shell `index` currently sits, radians. Public because it IS the screen's
## state and a headless check cannot see a shader — the same reason
## `Lance.warning_level()` is public.
func ring_phase(index: int) -> float:
	return _ring_phase[index] if index < _ring_phase.size() else 0.0


## Is the vent open RIGHT NOW? Public: it is the weak point's whole contract.
func vent_open() -> bool:
	if enemy_config.stern_vent_arc_deg <= 0.0 \
			or enemy_config.stern_vent_open_s <= 0.0 \
			or enemy_config.stern_vent_cycle_s <= 0.0:
		return false
	return _vent_clock < enemy_config.stern_vent_open_s


## 0 just after it shut, 1 the instant before it opens. THE TELEGRAPH — the plate
## brightens across the whole shut phase, so the window is something you can see
## coming rather than something you have to count. P4.4's readability rule.
func vent_charge() -> float:
	if vent_open():
		return 1.0
	var shut_s: float = enemy_config.stern_vent_cycle_s \
			- enemy_config.stern_vent_open_s
	if shut_s <= 0.0:
		return 1.0
	return clampf((_vent_clock - enemy_config.stern_vent_open_s) / shut_s, 0.0, 1.0)


## Does the screen stop a round arriving from `bearing` (a vector FROM the body
## TOWARD the attacker)? THE ONE QUESTION THE TYPE ASKS.
##
## A round is stopped if ANY shell has armour on that bearing. The stern aperture
## is cut through every shell at once, so while the vent is open the bearing
## behind the ship is clear all the way in — which is exactly what the shader
## draws, and the reason the aperture is not modelled as a per-shell slot.
func screen_blocks(bearing: Vector3) -> bool:
	var local: Vector3 = global_basis.inverse() * bearing
	local.y = 0.0
	if local.length() < 0.0001:
		return false
	# INSIDE THE SHELLS THERE IS NO SCREEN. A pilot who flies in through a slot
	# is past it, and this line is what keeps the picture honest for them —
	# without it the shells would stop rounds fired from a position visibly
	# inside them. It is a knife fight with six guns at point-blank, so it is an
	# extreme rather than an exploit, but it must not be a lie.
	if _player != null and is_instance_valid(_player) \
			and global_position.distance_to(_player.global_position) \
			< SCREEN_INNER_RADIUS_M:
		return false
	local = local.normalized()
	var azimuth: float = atan2(local.x, local.z)
	if vent_open() and absf(azimuth) < deg_to_rad(enemy_config.stern_vent_arc_deg) * 0.5:
		return false
	for i: int in RING_COUNT:
		if _ring_blocks(i, azimuth):
			return true
	return false


## One shell's own answer. `azimuth` is measured in the body's frame, 0 astern.
func _ring_blocks(index: int, azimuth: float) -> bool:
	var gaps: int = _ring_gaps(index)
	if gaps <= 0:
		return false
	var sector: float = TAU / float(gaps)
	var half: float = deg_to_rad(_ring_gap_deg(index)) * 0.5
	# SLOTS THAT MEET LEAVE NO ARMOUR, and it needs saying rather than falling
	# out of the comparison below — the same class of guard the old arc needed at
	# 360 degrees, where a float comparison left a hairline gap astern. Here the
	# residual would be one bearing that blocks in a shell configured wide open.
	if half * 2.0 >= sector:
		return false
	if half <= 0.0:
		return true
	var offset: float = fposmod(azimuth - _ring_phase[index] + sector * 0.5,
			sector) - sector * 0.5
	return absf(offset) >= half


func _physics_process(delta: float) -> void:
	_player = _find_player()
	_spin_screen(delta)
	_cycle_vent(delta)
	_update_screen(delta)
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


## THE SHELLS TURN, and this is the entire state of the defence: two angles.
##
## They ignore the player completely — deliberately, and it is the point of the
## rework. The screen this replaces steered for the threat it could see, which
## worked and read as broken, because the player had to infer a bearing from a
## featureless dome. A shell that turns at a constant rate whatever you do is
## MECHANICAL: predictable, learnable and self-evidencing, since motion and
## pattern are visible in a way that intent is not.
func _spin_screen(delta: float) -> void:
	for i: int in RING_COUNT:
		if _ring_gaps(i) <= 0:
			continue
		_ring_phase[i] = fposmod(
				_ring_phase[i] + deg_to_rad(_ring_rate_deg_s(i)) * delta, TAU)


## The vent's clock, wrapped. Nothing about it depends on the player: the window
## is the fortress's own rhythm, so it can be learned rather than provoked.
func _cycle_vent(delta: float) -> void:
	if enemy_config.stern_vent_cycle_s <= 0.0:
		return
	_vent_clock = fposmod(_vent_clock + delta, enemy_config.stern_vent_cycle_s)


## THE SCREEN, SEEN — and on this type the picture is half the mechanic (A.q10).
##
## Every uniform below is READ OUT of the same state the hit test uses. There is
## no separate animation state and no smoothing, because a cue that disagrees
## with the mechanic by even a little teaches the player the wrong edge, and here
## the wrong edge is the expensive one: believing a slot is open.
func _update_screen(delta: float) -> void:
	_splash = maxf(_splash - delta / SPLASH_DECAY_S, 0.0)
	var vent_half_rad: float = deg_to_rad(enemy_config.stern_vent_arc_deg) * 0.5
	for i: int in RING_COUNT:
		var material: ShaderMaterial = _ring_material[i]
		if material == null:
			continue
		var gaps: int = _ring_gaps(i)
		material.set_shader_parameter(&"gaps", gaps)
		material.set_shader_parameter(&"gap_half_rad",
				deg_to_rad(_ring_gap_deg(i)) * 0.5)
		material.set_shader_parameter(&"phase", _ring_phase[i])
		material.set_shader_parameter(&"phase_rate", _ring_rate_deg_s(i))
		material.set_shader_parameter(&"vent_half_rad", vent_half_rad)
		material.set_shader_parameter(&"vent_open", 1.0 if vent_open() else 0.0)
		material.set_shader_parameter(&"flash_dir", _splash_dir)
		material.set_shader_parameter(&"flash", _splash)
	_update_vent_glow()


## The plate brightens across the whole shut phase and goes white-hot when the
## window opens. A weak point nobody can find is not a weak point.
func _update_vent_glow() -> void:
	if _vent_material == null:
		return
	var lit: bool = enemy_config.stern_vent_arc_deg > 0.0 \
			and enemy_config.stern_vent_cycle_s > 0.0
	_vent_mesh.visible = lit
	if not lit:
		return
	var energy: float = VENT_ENERGY_OPEN if vent_open() \
			else lerpf(VENT_ENERGY_SHUT, VENT_ENERGY_READY, vent_charge())
	_vent_material.emission_energy_multiplier = energy


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
## every weapon in the game speaks — so deriving the bearing here costs no new
## plumbing and behaves identically for a bolt, a missile and a splash. A
## velocity-derived bearing would disagree with all three.
##
## A ROUND THE SCREEN STOPS IS REFUSED, not absorbed. Nothing is spent and the
## screen never falls, because it is a barrier rather than a battery — see the
## header. It splashes on the panel that stopped it, where the player can see
## which one it was.
func take_hit(damage: float) -> void:
	var bearing: Vector3 = _attack_bearing()
	if screen_blocks(bearing):
		_splash_dir = global_basis.inverse() * bearing
		_splash = 1.0
		return
	var index: int = _mount_facing(bearing)
	if index >= 0 and _mount_hull[index] > 0.0:
		_damage_mount(index, damage)
		return
	_health.take(damage)


## THE WEAK POINT, and the plate is a real body so this is an AIM test rather
## than a second positioning one (A.q10). Through an OPEN vent the round skips
## the screen and the whole battery and lands on the hull; a shut vent is just
## plating, so the round resolves exactly like any other arriving from astern —
## which means the screen still gets its say and the shot is not wasted, only
## ordinary.
func _on_vent_hit(damage: float) -> void:
	if not vent_open():
		take_hit(damage)
		return
	_health.take(damage)
	Effects.impact(get_tree().root, _vent.global_position)


## Flat unit vector from the body toward whoever is shooting. Falls back to
## astern when there is no player, so a hit with nobody on the field (a check, a
## stray splash) resolves rather than dividing by zero.
func _attack_bearing() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return global_basis.z
	var offset: Vector3 = _player.global_position - global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		return global_basis.z
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
	Effects.explosion(get_tree().root, mount.global_position, 1.6)
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
	Effects.explosion(get_tree().root, global_position, 4.0)
	destroyed.emit(enemy_config.points)
	queue_free()
