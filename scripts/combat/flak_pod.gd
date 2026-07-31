class_name FlakPod
extends Node3D

## The player's flak pod — the slice's third weapon (GAMEPLAY-DESIGN P3.1,
## P4.10) and the designed answer to the gnat row of the P4.3 counter-matrix.
##
## Mounted under the FPV camera beside the blaster and the missile rack, so it
## fires along the same view axis and the same reticle stays truthful. It is a
## plain ballistic launcher: the interesting behaviour all lives in the shell's
## proximity fuse (flak_shell.gd).
##
## NO FIRE-CONTROL ASSIST, on purpose. The blaster carries a gun director
## (fire_assist_miss_m) because a bolt has to intersect a body; the flak shell
## only has to arrive NEAR one, and that forgiveness IS its assist. Bolting a
## second trigger-puller onto it would hand the column an advantage the design
## never priced (P4.3: "FCS is not a column").

const SHELL_SCENE: PackedScene = preload("res://scenes/combat/flak_shell.tscn")

@export var combat_config: CombatConfig

## Test/bench hook, mirroring Weapon.fire_override: forces the trigger down.
var fire_override: bool = false

## --- Delivery-bench instrumentation (BALANCE.md Layer 2) ---
## An area weapon needs two numbers where a bolt needs one, because "did it
## land" and "how much of the pack did it cover" are different questions with
## different owners:
##   bursts_connected / shots_fired  -> the arrival rate (aim, evasion)
##   bodies_struck / bursts_connected -> `splash`, the per-weapon x target yield
## Keeping both here (rather than counting hits target-side) means one source of
## truth for both, and lets the bench cross-check them against each other.
var shots_fired: int = 0
var bursts_connected: int = 0
var bodies_struck: int = 0

## Which resupply gate refills this launcher. Read through the `magazines`
## group, so a gate never needs to know what nodes a drone is built from.
var ammo_kind: StringName = &"flak"
## Shells left. -1 until _ready loads the magazine; a magazine of 0 means
## unlimited (every bench that predates the feature, and the way to switch the
## whole mechanic off from a config).
var rounds: int = -1

var _cooldown: float = 0.0
var _drone: FlightController


func _ready() -> void:
	_drone = owner as FlightController
	add_to_group(&"magazines")
	rearm()


## Capacity. 0 = unlimited.
func magazine() -> int:
	return maxi(int(combat_config.flak_magazine), 0)


func unlimited() -> bool:
	return magazine() <= 0


func has_ammo() -> bool:
	return unlimited() or rounds > 0


## Put `fraction` of a full magazine back, capped at capacity. Gates, drops and
## the wave-clear re-arm all come through here so there is one place that knows
## what "full" means.
func rearm(fraction: float = 1.0) -> void:
	if unlimited():
		rounds = 0
		return
	rounds = clampi(rounds + int(ceil(float(magazine()) * fraction)), 0, magazine()) \
			if rounds >= 0 else magazine()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# flak_switch is the stateful radio trigger (switch position = trigger
	# held), created at runtime by InputBindings — hence the has_action guard,
	# which also keeps headless benches (no bindings applied) silent. It adds
	# no aim logic: the v1.28 no-director decision stands, this is just a
	# trigger a hand on the sticks can leave on.
	var trigger_down: bool = fire_override \
			or Input.is_action_pressed(&"fire_flak") \
			or (InputMap.has_action(&"flak_switch")
					and Input.is_action_pressed(&"flak_switch"))
	if _drone.armed and _cooldown <= 0.0 and has_ammo() and trigger_down:
		_fire()
		_cooldown = 1.0 / maxf(
				combat_config.flak_fire_rate * RunMods.current.flak_fire_rate_mult,
				0.001)


## The fuse radius the NEXT shell will carry, meters. The pod's ranging computer
## is FCS like every other director, so a screamer's jam shrinks it toward zero —
## and a shell with no fuse radius is a shell that only bursts on contact.
##
## P3.6 already promised this shape: "the fuse ranging is onboard computation —
## a screamer degrades it to contact-only, GRACEFULLY". Graceful is the whole
## point of doing it here rather than with a flag: the pod does not stop working
## inside a bubble, it stops working at a distance, which is a different and much
## more interesting loss.
##
## Note what does NOT degrade: `flak_burst_radius`. The fragments do not care
## about the jam, so a contact-fused shell is still an area weapon — it just has
## to arrive where a fused one only had to arrive NEAR. That is the degradation
## the design asked for and not one step further.
func fuse_radius() -> float:
	return combat_config.flak_fuse_radius * (1.0 - Jamming.level_at(self))


## Called by every shell as it detonates. `bodies` is how many hostiles the
## fragment cloud caught — zero for a burst that went off in empty air or
## against scenery.
func report_burst(bodies: int) -> void:
	if bodies <= 0:
		return
	bursts_connected += 1
	bodies_struck += bodies


func _fire() -> void:
	shots_fired += 1
	if not unlimited():
		rounds -= 1
	Blackbox.log_event(&"fired", "flak")
	var direction: Vector3 = -global_basis.z
	var velocity: Vector3 = direction * combat_config.flak_muzzle_speed \
			+ _drone.linear_velocity * combat_config.inherit_velocity
	var origin: Vector3 = global_position + direction * 0.4
	var shell := SHELL_SCENE.instantiate() as FlakShell
	# Parented beside the drone, not under it: the shell must not inherit the
	# aircraft's motion after launch (the same reason missiles are).
	_drone.get_parent().add_child(shell)
	shell.global_position = origin
	shell.setup(combat_config, self, _drone.team, [_drone.get_rid()], velocity,
			combat_config.flak_damage * RunMods.current.flak_damage_mult,
			fuse_radius())
	SoundBank.play_at(&"shot", origin, -3.0, 0.3)
