class_name FlightController
extends RigidBody3D

## Orchestrates the flight loop each physics tick (handoff §6.3):
## sticks → target rates → rate PID → quad-X mixer → motors.
## Pilot-convention axes everywhere outside the Godot-space conversion in
## _measured_rates(): x = roll (+right), y = pitch (+nose up), z = yaw (+right).

enum FlightMode { ACRO, ANGLE }

## THE AIRFRAME'S PROPORTIONS, as fractions of `FlightConfig.body_m`. Taken from
## the hand-authored 0.28 m Kestrel that every one of these numbers reproduces
## exactly, so the roster's size ladder (kestrel 0.28 m, condor 1.2 m, roc 3.0 m)
## is one scene rather than three.
##
## `arm_length` is deliberately NOT in this list even though the Kestrel's arm is
## 0.4286 x its body: the arm is a physics quantity that the motor mixer reads
## every tick, so it stays an authored config field and the MOTOR MESHES are
## placed from it. A frame is free to be a wide-armed 3 m machine or a compact
## one, and the picture follows the physics rather than the other way round.
const BODY_HEIGHT_RATIO: float = 0.2857
const MOTOR_SIZE_RATIO: float = 0.1786
const MOTOR_HEIGHT_RATIO: float = 0.0893
const MOTOR_LIFT_RATIO: float = 0.1875
const NOSE_LIFT_RATIO: float = 0.1786
const NOSE_REACH_RATIO: float = 0.3929
## Near plane as a fraction of body size, floored at Godot's usual 0.05. The
## floor is load-bearing at the small end: the 0.28 m Kestrel's lens sits inside
## its own hull, and a near plane that scaled all the way down would suddenly
## render the inside of the airframe in front of the pilot.
const NEAR_PLANE_RATIO: float = 0.0667
const NEAR_PLANE_MIN: float = 0.05

## Hard contact. Carries the IMPACT SPEED — the velocity the collision took away
## — which `CombatConfig.impact_g` turns into peak deceleration and main prices
## as damage (roadmap M2, GAMEPLAY-DESIGN Iteration 17 / E6).
##
## The controller reports a SPEED and not a g, deliberately, and the split is the
## honest one: a speed is what the solver actually produced, a deceleration needs
## a stopping distance that no physics tick can supply (see `impact_g`). It also
## keeps this file combat-thin, which is why the damage arithmetic lives on the
## config rather than here.
signal crashed(impact_speed: float)
## The dev reset put the airframe back to new. Whoever owns the wounds that do
## NOT live on the drone — the hull bar and the video transmitter, both in main —
## clears them here, so one keypress means one thing.
signal airframe_reset
## The airframe changed under everything holding a reference to it (V10).
##
## `config` is a DIFFERENT FlightConfig instance after a swap, so anything that
## cached the old one is now editing a frame nobody is flying. The debug overlay
## did exactly that and it cost a flight: the FPV angle slider kept working on the
## Kestrel and did nothing on the Roc, because it was still writing to the
## Kestrel's resource. Everything else in the tree re-reads `drone.config` per
## call and needs no signal — the overlay builds controls once, so it needs this.
signal frame_changed

## The airframe being flown (GAMEPLAY-DESIGN P3.3/P3.9). Swapping frames is
## swapping this one resource: it carries the flight model AND the hull.
@export var frame: FrameConfig
## Damage model (GAMEPLAY-DESIGN Iteration 7). Null in the harness/tests, where
## motors stay undamaged and flight is the shipped model exactly.
@export var damage_config: DamageConfig
## Benches set this false before the node enters the tree (see Frames.build).
##
## An instrument must measure the REPO's numbers. Until Phase 4b it did not: the
## balance benches instantiate drone.tscn, which auto-loaded user://, so every
## delivery factor in the committed artifact was measured against whatever the
## human had last tuned into their own override — here, rate_p 0.007 and
## rate_ff 0.0008 against the repo's 0.004 and 0. The ruler was machine-local
## and the config stamp could not see it, because the stamp watched CombatConfig
## and EnemyConfig while the drift sat in FlightConfig.
@export var load_user_overrides: bool = true

## This frame's flight model — `frame.flight_config`, resolved in _ready().
## Not an @export any more: a frame that could be flown with another frame's
## FlightConfig is not a frame. Everything that read `drone.config` still does.
var config: FlightConfig

@onready var _motors: MotorModel = $MotorModel
@onready var _input: InputHandler = $InputHandler
@onready var _fpv_camera: Camera3D = $FpvCamera

var armed: bool = false
var flight_mode: FlightMode = FlightMode.ACRO
## Combat identity read by projectiles (same-team hits don't damage).
var team: StringName = &"player"
## World direction the last projectile hit came FROM (set by projectile.gd,
## consumed by main.gd for the HUD damage-direction indicator).
var last_hit_direction: Vector3 = Vector3.ZERO
## Body-space direction of travel at the last collision, flattened to the rotor
## plane. Consumed and cleared by `apply_hit_to_motors` to weight a crash toward
## the side that led the impact. Zero means "no crash heading" and restores the
## perfectly even spread this replaced.
var last_crash_heading: Vector3 = Vector3.ZERO
## Effective throttle [0, 1] this tick (gamepad, or the test override below).
var collective: float = 0.0
## Test hook (scripts/tests/hover_check.gd): >= 0 replaces gamepad throttle.
var throttle_override: float = -1.0
## Test hook (scripts/tests/step_response.gd): replaces stick target rates.
var rate_override_enabled: bool = false
var rate_override: Vector3 = Vector3.ZERO
## Pause-mode position hold (set by main while slow-mo pause is active):
## overrides sticks with a level-and-brake controller so the drone parks
## itself while the pilot tunes/binds in peace.
var autopilot: bool = false

## For the overlay's target-vs-actual readout; zeroed while disarmed.
var telemetry_target_rates: Vector3 = Vector3.ZERO
var telemetry_measured_rates: Vector3 = Vector3.ZERO

var _rate_controller: RateController = RateController.new()
var _arm_switch_was: bool = false
var _spawn_transform: Transform3D
var _previous_velocity: Vector3 = Vector3.ZERO
## False until the first physics tick has stored a velocity to difference against.
## Without it, a bench that sets `linear_velocity` before the drone ever ticks
## would have its whole launch speed read as a collision on tick one.
var _previous_velocity_valid: bool = false
## Reused by `motor_drive()`, which the HUD reads once per rendered frame.
var _drive_scratch: PackedFloat32Array = PackedFloat32Array()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## Fly another frame without editing a scene: `<godot> --path . -- --frame atlas`.
##
## A dev affordance, NOT the shipped picker — P3.8's briefing chain (intel ->
## frame -> loadout) and P3.9's HANGAR overlay section are where choosing an
## airframe actually belongs. This exists so the human's hands can judge a new
## frame the day it lands, which is the only test that matters for feel.
##
## Gated on `load_user_overrides` so the BENCHES never see it: an instrument that
## can be re-aimed by a command line is not an instrument, and Frames.build
## already says which frame it means.
func _frame_from_cmdline() -> FrameConfig:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--frame")
	if at < 0 or at + 1 >= args.size():
		return null
	var path: String = "res://resources/default_frame_%s.tres" % args[at + 1]
	if not ResourceLoader.exists(path):
		push_error("[frame] no such frame '%s' (%s)" % [args[at + 1], path])
		return null
	return load(path) as FrameConfig


## The menu tower's frame pick (B5 step 4, MenuLaunch.frame_id). Outranks
## the CLI flag — a menu choice is newer intent than the launch command —
## and sits behind the same load_user_overrides gate, so the BENCHES see
## neither: Frames.build already says which frame an instrument means.
func _frame_from_menu() -> FrameConfig:
	if MenuLaunch.frame_id == &"":
		return null
	var path: String = "res://resources/default_frame_%s.tres" % MenuLaunch.frame_id
	if not ResourceLoader.exists(path):
		push_error("[frame] menu picked unknown frame '%s'" % MenuLaunch.frame_id)
		return null
	return load(path) as FrameConfig


func _ready() -> void:
	if load_user_overrides:
		var picked: FrameConfig = _frame_from_menu()
		if picked == null:
			picked = _frame_from_cmdline()
		if picked != null:
			frame = picked
	_adopt_frame()
	if damage_config != null:
		# Every other config auto-loads its user:// override on boot; this one
		# did not, so saved damage tuning was silently ignored until the
		# overlay's Load button was pressed — the one config whose edits
		# vanished between sessions.
		#
		# GATED ON `load_user_overrides` LIKE EVERY OTHER CONFIG, and it was not
		# until 2026-08-14. `Frames.build` turns that flag off precisely so a
		# bench measures the REPO's numbers and not one machine's tuning — but
		# this line sat outside the guard, so every bench in the suite quietly
		# adopted whatever the human had saved into user://damage_config.tres.
		# `motor_min_thrust` reaches the flight model on the very next tick, so
		# this was a live channel from a human's overlay into the instrument.
		#
		# It was HARMLESS THE DAY IT WAS FOUND — the saved file happened to carry
		# no property overrides at all, so it loaded the script's own defaults,
		# which match the repo's — and that is exactly why it is worth a comment.
		# A leak that currently agrees with the truth is a leak nobody will
		# notice on the day it stops agreeing (scar 1: *check what user:// is
		# overriding before believing any config experiment*).
		if load_user_overrides and damage_config.load_from_user():
			print("[config] loaded %s" % damage_config.save_path())
		_motors.min_thrust_floor = damage_config.motor_min_thrust
	_spawn_transform = global_transform
	# NOT connected to `body_entered` any more, and that is the whole of the fix
	# for the silent building strike — see `_price_contact`. `contact_monitor` and
	# `max_contacts_reported` stay set in drone.tscn because `get_contact_count()`
	# needs them, and so does the rate controller's ground check.
	# THE UPTILT MUST EXIST BEFORE THE FIRST PHYSICS TICK, and until 2026-08-06 it
	# did not. It was applied only in `_process`, which runs on the IDLE frame —
	# so whether the camera was tilted when the first `_physics_process` ran
	# depended on whether an idle frame happened to fall in between, which is a
	# function of machine load.
	#
	# That is not a cosmetic race. The weapon is a CHILD of this camera, so the
	# gun line inherits the tilt, and `ReferencePilot` aims by the gun's basis.
	# With the tilt missing the pilot reads a level gun, concludes it is already
	# on target, and commands nothing; with it present it correctly pitches the
	# nose down to put a 44-degree gun on a level target. Measured: the pilot's
	# first commanded pitch rate came out as 0.00008 in one process and -3.84 in
	# another, from the identical command line — and from that tick the whole
	# flight, the shot count and the measured factor diverge.
	#
	# **This is the Track 5 root cause** (GAMEPLAY-DESIGN v2.23). It is also a
	# real one-frame defect in the GAME: every flight's first frame was flown with
	# an untilted camera.
	_apply_camera_config()


func _process(_delta: float) -> void:
	# Re-read every frame so the Phase 3 overlay can tune these live.
	_apply_camera_config()


func _apply_camera_config() -> void:
	_fpv_camera.fov = config.fpv_fov_deg
	_fpv_camera.rotation_degrees.x = config.fpv_uptilt_deg


## Everything that depends on WHICH frame this is. Called from `_ready` and again
## from `swap_frame`, so the two can never drift — which they would, because the
## list is seven things long and six of them are easy to forget.
func _adopt_frame() -> void:
	config = frame.flight_config
	print("[frame] flying %s (%.2f m, mass %.2f kg, TWR %.1f, hull %.0f, armor %.0f)"
			% [frame.display_name, config.body_m, config.mass,
			config.thrust_to_weight_ratio, frame.hull, frame.armor])
	if not frame.flight_config_matches():
		push_error("[frame] %s carries a flight config for '%s'"
				% [frame.frame_id, config.frame_id])
	if load_user_overrides:
		if frame.load_from_user():
			print("[config] loaded %s" % frame.loaded_from)
		if config.load_from_user():
			print("[config] loaded %s" % config.loaded_from)
	# The frame owns the hull, and applies it HERE rather than in main.gd. That
	# move closes a hole in the instrument: the benches instantiate this scene
	# directly and never ran main's wiring, so they measured whatever default sat
	# on the Health node while the game measured CombatConfig.player_max_health.
	# The two agreed at 100 by luck; tuning one would have silently desynced the
	# harness's damage-taken column from the game's.
	($Health as Health).max_health = frame.hull
	($Health as Health).armor = frame.armor
	($Health as Health).revive()
	# BEFORE the geometry, which reads the mounts off it (E.q1). A frame declares
	# its rotor layout the way it declares its mass; everything downstream — the
	# mixer, the meshes, the audio emitters, the HUD pips, the hit picker — asks
	# the motor model rather than assuming four.
	_motors.configure(MotorModel.layout_from_id(config.rotor_layout))
	# AFTER the layout, never before: plate mass is priced per ROTOR among other
	# things, so a hexa pays for six pods and the count has to be real by now.
	_apply_loaded_mass()
	# Printed only when there IS plating, so an unplated frame's boot line is
	# unchanged and the ladder's logs stay comparable across the roster.
	var plate: float = plate_mass()
	if plate > 0.0:
		print("[frame] %s carries %.3f kg of plating (%.1f%% of its dry mass): TWR %.1f -> %.2f"
				% [frame.display_name, plate, plate / maxf(config.mass, 0.0001) * 100.0,
				config.thrust_to_weight_ratio, effective_twr()])
	_apply_frame_geometry()


## Build the airframe's body, motors and lens at this frame's size.
##
## FRESH Mesh AND Shape RESOURCES EVERY TIME, never edits of the ones the .tscn
## carries. Sub-resources in a PackedScene are shared across every instance of
## it, so resizing them in place would mean a bench spawning three drones had one
## airframe whose size was decided by whichever instance readied last.
func _apply_frame_geometry() -> void:
	var body: float = config.body_m
	var hull := Vector3(body, body * BODY_HEIGHT_RATIO, body)
	var collision := BoxShape3D.new()
	collision.size = hull
	($Collision as CollisionShape3D).shape = collision
	($Body as MeshInstance3D).mesh = _sized_box(($Body as MeshInstance3D).mesh, hull)

	var motor := Vector3(body * MOTOR_SIZE_RATIO, body * MOTOR_HEIGHT_RATIO,
			body * MOTOR_SIZE_RATIO)
	var lift: float = body * MOTOR_LIFT_RATIO
	# THE MESHES FOLLOW THE LAYOUT, not a hard-coded four corners (E.q1). The
	# scene authors FL/FR/BL/BR so the datum airframe is legible in the editor and
	# so indices 0-3 keep their nodes; anything past that is built here. A layout
	# with fewer rotors hides the spares rather than freeing them, so swapping
	# back to a quad in place cannot lose a mesh it will want again.
	for i: int in _motors.rotor_count:
		var node: MeshInstance3D = _motor_mesh(i)
		node.visible = true
		node.mesh = _sized_box(node.mesh, motor)
		var mount: Vector3 = _motors.motor_position(i, config)
		node.position = Vector3(mount.x, lift, mount.z)
	var spare: int = _motors.rotor_count
	while true:
		var extra: MeshInstance3D = get_node_or_null(
				NodePath(MOTOR_NODES[spare] if spare < MOTOR_NODES.size()
				else "Motor%d" % spare)) as MeshInstance3D
		if extra == null:
			break
		extra.visible = false
		spare += 1
	var nose: MeshInstance3D = $NoseMarker
	nose.mesh = _sized_box(nose.mesh, motor)
	nose.position = Vector3(0.0, body * NOSE_LIFT_RATIO, -body * NOSE_REACH_RATIO)

	# The lens is placed, not scaled — see FlightConfig.fpv_offset.
	_fpv_camera.position = config.fpv_offset
	_fpv_camera.near = maxf(body * NEAR_PLANE_RATIO, NEAR_PLANE_MIN)


## The four the .tscn authors, in MotorModel's index order.
const MOTOR_NODES: Array[String] = ["MotorFL", "MotorFR", "MotorBL", "MotorBR"]


## The mesh node for rotor `index`, created on first use past the authored four.
##
## A new one copies the mesh of rotor 0 so it inherits the airframe's material —
## the body's material lives ON the mesh resource, and a bare MeshInstance3D
## would render a white cube on an otherwise dark quad.
func _motor_mesh(index: int) -> MeshInstance3D:
	var node_name: String = MOTOR_NODES[index] if index < MOTOR_NODES.size() \
			else "Motor%d" % index
	var node: MeshInstance3D = get_node_or_null(NodePath(node_name)) as MeshInstance3D
	if node != null:
		return node
	node = MeshInstance3D.new()
	node.name = node_name
	var datum: MeshInstance3D = get_node_or_null(
			NodePath(MOTOR_NODES[0])) as MeshInstance3D
	if datum != null:
		node.mesh = datum.mesh
		node.material_override = datum.material_override
	add_child(node)
	return node


## A new BoxMesh at `size`, keeping whatever material the old one carried — the
## body's material lives ON the mesh resource, so replacing the mesh without
## carrying it over would repaint the airframe white.
func _sized_box(previous: Mesh, size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	if previous is BoxMesh:
		box.material = (previous as BoxMesh).material
	return box


## Change airframe in place, on the pad, without reloading the scene (V10).
##
## THE POINT IS BACK-TO-BACK COMPARISON, which is the only way the size ladder
## says anything: *"being able to fly them both IN THE SAME EXACT ENV' will
## absolutely give me the sense of scale."* Reloading the scene per frame would
## work and would put a load screen between the two halves of the comparison.
##
## It always disarms and always zeroes velocity: swapping airframe mid-manoeuvre
## would hand the new frame the old one's momentum, and 500 kg at 140 m/s
## arriving inside a 0.65 kg body is not a comparison, it is a physics incident.
func swap_frame(next: FrameConfig) -> void:
	if next == null or next == frame:
		return
	disarm()
	frame = next
	_adopt_frame()
	_apply_camera_config()
	_motors.repair()
	_rate_controller.reset()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# The velocity was just thrown away by hand, so the next tick must not read
	# the discarded speed as a collision (see `_price_contact`).
	_previous_velocity_valid = false
	frame_changed.emit()


func _physics_process(delta: float) -> void:
	# FIRST, before anything this tick touches the velocity: price whatever the
	# solver did to us during the LAST step.
	_price_contact()
	if damage_config != null:
		_motors.min_thrust_floor = damage_config.motor_min_thrust
	_input.poll(config, hover_throttle(), delta)
	collective = throttle_override if throttle_override >= 0.0 else _input.throttle
	if autopilot and armed:
		# Hold altitude around hover throttle; _autopilot_rates() holds level.
		collective = clampf(hover_throttle()
				+ config.autopilot_climb_gain * -linear_velocity.y, -1.0, 1.0)
	_handle_buttons()
	if armed:
		_run_rate_control(delta)
	else:
		_rate_controller.reset()
		_motors.force_stop()
		telemetry_target_rates = Vector3.ZERO
		telemetry_measured_rates = Vector3.ZERO
	_motors.step(delta, config)
	_motors.apply_thrust(self, config, _gravity)
	_apply_aerodynamics()
	_previous_velocity = linear_velocity
	_previous_velocity_valid = true


func arm() -> bool:
	if armed:
		return true
	# absf: in 3D mode zero thrust is center stick, and reverse counts as hot.
	if absf(collective) >= config.arm_throttle_threshold:
		print("[drone] arm refused: throttle %.0f%% is above the %.0f%% threshold - hold the throttle stick down"
				% [collective * 100.0, config.arm_throttle_threshold * 100.0])
		return false
	armed = true
	print("[drone] ARMED")
	return true


func disarm() -> void:
	armed = false
	_rate_controller.reset()
	_motors.force_stop()
	print("[drone] disarmed")


## Move the drone AND the point B sends it back to, before anything is flown.
##
## THE SECOND HALF IS THE WHOLE REASON THIS EXISTS. `_spawn_transform` is
## captured in `_ready`, and a child's `_ready` runs before its parent's — so a
## scene that repositions the drone from its own `_ready` (which is exactly what
## the composed sortie's ingress does, A6) would leave the reset key teleporting
## the pilot back to wherever the .tscn happened to park them, which for a sortie
## is the middle of the enemy base.
func place_at(new_transform: Transform3D) -> void:
	global_transform = new_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Teleported and stopped by hand, so the next tick has no honest velocity
	# difference to price (see `_price_contact`).
	_previous_velocity_valid = false
	_spawn_transform = new_transform


## The dev reset (B / R). A FULL restore, not just a teleport.
##
## It repaired the rotors and nothing else, which read as "reset does not clear
## damage" from the cockpit — the human's report, and they were right: the two
## wounds you can actually SEE are the hull bar and the broken video feed, and
## both survived it. The rotor repair was already here, so the intent was never
## in doubt; the hull and the transmitter simply live in `main` and were never
## wired up. `airframe_reset` is that wiring.
func reset_to_spawn() -> void:
	disarm()
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_motors.repair()
	_rate_controller.clear_integrator()
	last_hit_direction = Vector3.ZERO
	# Same reason as `place_at`: the speed was discarded, not lost to a wall.
	_previous_velocity_valid = false
	($Health as Health).revive()
	airframe_reset.emit()
	print("[drone] reset to spawn")


## Battle damage to the airframe's flight (GAMEPLAY-DESIGN Iteration 7 / D2):
## a hit degrades the motor on the side it came FROM, so the wound is asymmetric
## and located, not an abstract number. Directionless damage (a crash) frays the
## whole frame. Gated by the severity dial; a no-op without a damage_config.
func apply_hit_to_motors(damage: float) -> void:
	if damage_config == null or damage_config.severity <= 0.0:
		return
	var raw: float = damage * damage_config.motor_damage_scale
	var amount: float = minf(raw, damage_config.motor_damage_max) \
			* damage_config.severity
	var from_body: Vector3 = global_basis.inverse() * last_hit_direction
	from_body.y = 0.0
	if from_body.length_squared() < 0.000001:
		_apply_crash(raw)
		return
	if amount <= 0.0:
		return
	_apply_located(from_body.normalized(), amount)


## A located hit, spread across whatever it actually reaches (E.q2 `derived`,
## E4.3 separation).
##
## The round arrives from `from_body` and therefore meets the airframe on that
## side; the impact point is that bearing taken out to the hull's own edge. Every
## routed component within `hit_footprint_m` of it shares the damage, weighted by
## closeness — and because that footprint is a fixed number of METRES, a small
## airframe's tightly packed rotors share a round while a large one's take it
## singly. Nobody authors that difference; it is what building at true size buys.
##
## DAMAGE IS CONSERVED: the weights are normalised, so straddling three
## components costs the same as landing on one. This decides WHERE, never how
## much.
##
## The nearest component takes the whole hit when nothing falls inside the
## footprint, which is the large airframe's ordinary case and is what keeps E7's
## repeatability — *"if in two different runs i get the same engine hit — thats a
## lession to be learned"* — true on a frame whose parts are metres apart.
func _apply_located(from_body: Vector3, amount: float) -> void:
	var parts: Array[AirframeComponents.Part] = AirframeComponents.targetable(self)
	if parts.is_empty() or amount <= 0.0:
		return
	var impact: Vector3 = from_body * (config.body_m * 0.5)
	impact.y = 0.0
	var footprint: float = damage_config.hit_footprint_m
	var weights: Array[float] = []
	var total: float = 0.0
	var nearest: int = 0
	var nearest_distance: float = INF
	for i: int in parts.size():
		var pos: Vector3 = parts[i].position
		pos.y = 0.0
		var distance: float = pos.distance_to(impact)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = i
		var weight: float = 0.0
		if footprint > 0.0:
			weight = maxf(1.0 - distance / footprint, 0.0)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		_damage_component(parts[nearest], amount)
		return
	for i: int in parts.size():
		if weights[i] > 0.0:
			_damage_component(parts[i], amount * weights[i] / total)


## A crash frays the WHOLE frame, and lopsidedly (E6, corrected by the human's
## flight report 2026-08-15). Two changes from the version this replaces, both
## approved after the bench measured what was wrong with it:
##
## **THE BULLET CAP DOES NOT APPLY.** `motor_damage_max` exists so that *"one bolt
## frays a motor, it never kills one outright"* — a rule about small arms, which a
## crash had been inheriting. It meant rotor damage stopped rising at about 50
## points, so a 130 m/s impact into a building cost exactly what a 25 m/s bump
## did. Crash severity never reached the rotors at all above that line, which
## quietly undid the whole point of making crash damage scale with violence.
##
## **AND IT IS WEIGHTED TOWARD THE SIDE THAT HIT.** An even crash was measured to
## be FREE: identical damage produced 27.63 degrees of tilt as a bullet and
## **0.00** as a crash, because a multirotor does not care about a symmetric loss.
## The weights are normalised to mean 1, so this redistributes the wound rather
## than resizing it, and every rotor still takes something at any asymmetry below
## 1 — a crash loading the whole frame is E6's actual content and is not up for
## negotiation, only its evenness was.
func _apply_crash(raw: float) -> void:
	var heading: Vector3 = last_crash_heading
	last_crash_heading = Vector3.ZERO
	var base: float = raw * damage_config.severity \
			* damage_config.crash_motor_scale
	if base <= 0.0:
		return
	# Walked over the REGISTRY rather than over a rotor count (E10 step 2), so
	# E6's *"all parts feel"* it is literally what this loop says, and a
	# component that becomes damageable is loaded by a crash the day it is added.
	var parts: Array[AirframeComponents.Part] = AirframeComponents.of(self)
	var lean: float = clampf(damage_config.crash_asymmetry, 0.0, 1.0)
	if heading.length_squared() < 0.000001 or lean <= 0.0:
		for part: AirframeComponents.Part in parts:
			_damage_component(part, base)
		return
	# `heading` is the way the airframe was travelling, so a rotor lying along it
	# is on the leading edge and meets the wall first.
	var weights: Array[float] = []
	var total: float = 0.0
	for part: AirframeComponents.Part in parts:
		var flat := Vector3(part.position.x, 0.0, part.position.z)
		var lead: float = 0.0
		if flat.length_squared() > 0.000001:
			lead = maxf(flat.normalized().dot(heading), 0.0)
		var weight: float = (1.0 - lean) + lean * lead
		weights.append(weight)
		total += weight
	# Normalised to mean 1: asymmetry moves the damage around the airframe, it
	# does not add or remove any. Without this, raising the knob would silently
	# make every crash gentler and re-tune E6's calibration by accident.
	var mean: float = total / float(maxi(weights.size(), 1))
	if mean <= 0.0:
		return
	for i: int in parts.size():
		_damage_component(parts[i], base * weights[i] / mean)


## Route damage to one component. The dispatch is where "addressable" stops being
## a description and starts doing something.
##
## The unbuilt rows are a deliberate no-op rather than an error: E10 step 2 is
## *"every component present, only the built ones doing anything"*, so the table
## can hold the whole of E3 while the failure modes arrive one at a time.
func _damage_component(part: AirframeComponents.Part, amount: float) -> void:
	# PLATING IS APPLIED HERE AND NOWHERE ELSE (E4.2). Every path that can hurt a
	# component — a located round, a crash, and whatever routes here later — goes
	# through this function, so armour cannot be bypassed by adding a new one.
	#
	# Flat, in the same 0-to-1 units as the component's health, which is the same
	# grammar `FrameConfig.armor` already uses on the hull: worth most against
	# many small hits and least against few big ones. A rotor plated at 0.05 is
	# untouched by chip fire and no better off against a missile.
	var through: float = amount - part.armor
	if through <= 0.0:
		return
	match part.kind:
		&"rotor":
			_motors.damage_motor(part.index, through)
		_:
			pass


func motor_health(index: int) -> float:
	return _motors.health(index)


## Lowest engine capability (0 = a dead corner, 1 = all healthy).
func worst_motor_health() -> float:
	return _motors.min_health()


func repair_motors() -> void:
	_motors.repair()
	# Clear the windup trim that fought the wound, so the fixed quad flies clean
	# instead of drifting while the I-term unwinds (the repair-gate "nudge").
	_rate_controller.clear_integrator()


## THE AIRFRAME AS FLOWN: authored dry mass plus whatever its plating weighs
## (GAMEPLAY-DESIGN Iteration 17 / E.q7). The `.tres` keeps saying what the
## airframe weighs EMPTY, which is the number an engineer would quote, and the
## armour is a load it carries.
func loaded_mass() -> float:
	return config.mass + plate_mass()


## What this airframe's plating weighs, kg. Zero on any frame with no plating, so
## an unplated roster is bit-identical to the model before E.q7's loop closed.
func plate_mass() -> float:
	return AirframeComponents.plate_mass(frame, config, _motors.rotor_count)


## THE PERFORMANCE HALF OF E.q7'S LOOP, and it is deliberately NOT compensated.
## `MotorModel.max_total_thrust` is `TWR x config.mass x g` — the thrust budget is
## bought with the DRY airframe — so hanging plate on it lifts the hover throttle
## and drops the effective thrust-to-weight without anybody authoring a penalty.
## That is *"the armor costs mass, and the mass costs performance"* falling out of
## the arithmetic rather than being applied to it.
func effective_twr() -> float:
	var loaded: float = loaded_mass()
	if loaded <= 0.0:
		return 0.0
	return _motors.max_total_thrust(config, _gravity) / (loaded * _gravity)


func _apply_loaded_mass() -> void:
	mass = loaded_mass()


## Throttle fraction at which total thrust equals weight. With the linear
## thrust model this is exactly 1/TWR on a bare airframe; computed honestly so it
## stays correct with plating aboard, and so it would stay correct if the thrust
## model gained a curve later.
func hover_throttle() -> float:
	return loaded_mass() * _gravity / _motors.max_total_thrust(config, _gravity)


## Test/setup hook: skip motor spool-up (see scripts/tests/hover_check.gd).
func prime_motors(value: float) -> void:
	_motors.prime(value)


func _handle_buttons() -> void:
	if Input.is_action_just_pressed(&"arm_toggle"):
		if armed:
			disarm()
		else:
			arm()
	# FPV-style stateful arming (bindable in the overlay's BINDINGS section,
	# unbound by default): switch position IS the armed state — up arms, down
	# disarms — matching how a real radio's arm switch behaves.
	if InputMap.has_action(&"arm_switch") \
			and not InputMap.action_get_events(&"arm_switch").is_empty():
		var switch_on: bool = Input.is_action_pressed(&"arm_switch")
		if switch_on != _arm_switch_was:
			_arm_switch_was = switch_on
			if switch_on:
				arm()
			else:
				disarm()
	if Input.is_action_just_pressed(&"reset_drone"):
		reset_to_spawn()
	if Input.is_action_just_pressed(&"flight_mode_toggle"):
		if flight_mode == FlightMode.ACRO:
			flight_mode = FlightMode.ANGLE
		else:
			flight_mode = FlightMode.ACRO
		print("[drone] flight mode: %s" % FlightMode.keys()[flight_mode])


## PER-ROTOR DRIVE, in mixer order, for a readout that wants all of them at once.
##
## Reuses one array rather than building a new one, because the HUD reads this
## EVERY FRAME and a fresh PackedFloat32Array per frame is garbage for nothing.
## Values are the post-lag outputs, so this is what the motors are actually
## doing rather than what they were just asked for; in 3D throttle mode they can
## be NEGATIVE, which is a reversed prop and not a bug.
func motor_drive() -> PackedFloat32Array:
	if _drive_scratch.size() != _motors.rotor_count:
		_drive_scratch.resize(_motors.rotor_count)
	for i: int in _motors.rotor_count:
		_drive_scratch[i] = _motors.output(i)
	return _drive_scratch


## Which way each rotor turns, +1 or -1, straight off the layout. Read rather
## than re-authored: on a quad the diagonals share a direction, on the hexa six
## alternate around the ring, and any second copy of that table is scar six
## waiting to happen.
func motor_spins() -> PackedFloat32Array:
	return _motors.spins


func motor_spin(index: int) -> float:
	return _motors.spins[index]


func motor_output(index: int) -> float:
	return _motors.output(index)


## Blackbox/overlay telemetry: the rate PID integrator state.
func telemetry_integrator() -> Vector3:
	return _rate_controller.integrator()


## HUD stick display: raw physical stick positions (x=+right, y=+up, [-1,1]).
func stick_positions() -> Array[Vector2]:
	return [_input.stick_left, _input.stick_right]


## Projectile hits land here; the Health component and its wiring (main.gd)
## decide the consequences — the flight controller stays combat-thin.
func take_hit(damage: float) -> void:
	($Health as Health).take(damage)


## PRICE CONTACT EVERY TICK IT LASTS, not only the tick it began (the human's
## ruling, 2026-08-15, option 2 of three offered).
##
## **THE BUG THIS REPLACES, because it is worth never rebuilding.** This used to
## hang off `body_entered`, which is an ENTER signal — and a whole building is ONE
## `StaticBody3D` carrying a `CollisionShape3D` per slab. So an airframe that
## touched a tower gently and then flew into it never entered a second time, and
## the entire encounter was priced at whatever that first touch was worth.
## Measured by `graze_bench`: drift in at 4 m/s (free, 0.00 hull), hold contact,
## then drive into it at 60 m/s — one event, zero damage. Whether a collision hurt
## depended on how fast you ENTERED contact rather than on how hard you were
## hitting, which is exactly the *"sometimes"* in the flight report.
##
## **WHY EMITTING EVERY CONTACT TICK IS SAFE, AND IT IS ARITHMETIC RATHER THAN A
## HOPE.** The threshold is 73.5 g, which needs 12.0 m/s of delta-v in a SINGLE
## tick. At 240 Hz an airframe under full power builds at most `TWR x g / 240` —
## half a metre per second on the fiercest frame in the roster — so grinding along
## a wall under thrust can never reach it, and resting on the ground produces
## `g / 240` = 0.04 m/s. Only a genuine strike crosses the line, and a strike
## spends its own speed doing so, which makes the mechanic self-limiting: you
## cannot be re-accelerated to 12 m/s inside one tick to be hit again.
##
## So the sub-threshold ticks cost one `crash_damage` call that returns zero and
## an early return in `main`, and this file stays combat-thin: it reports a SPEED
## every tick there is contact, and what that speed is worth is not its business.
func _price_contact() -> void:
	# The first tick has no previous velocity to difference against, and a bench
	# that sets `linear_velocity` before the drone ever ticks would otherwise read
	# its whole launch speed as a collision.
	if not _previous_velocity_valid:
		return
	if get_contact_count() <= 0:
		return
	# WHICH WAY THE AIRFRAME WAS GOING, in body space, kept for the asymmetric
	# crash. The direction of travel IS the side that hit, and it has to be
	# captured from the PRE-collision velocity: by now the impact has already
	# started spinning the aircraft.
	var travel: Vector3 = global_basis.inverse() * _previous_velocity
	travel.y = 0.0
	last_crash_heading = travel.normalized() if travel.length_squared() > 0.000001 \
			else Vector3.ZERO
	# The velocity the solver took away across the last step. Measured across the
	# whole ladder from 3 to 131 m/s, this is mass-blind, which is what E6
	# requires — and it is measured the same way it always was, so E6's
	# calibration is untouched by the change in WHEN it is read.
	crashed.emit((_previous_velocity - linear_velocity).length())


func _run_rate_control(delta: float) -> void:
	telemetry_target_rates = _target_rates()
	telemetry_measured_rates = _measured_rates()
	var command: Vector3 = _rate_controller.update(
			telemetry_target_rates, telemetry_measured_rates, delta, config,
			get_contact_count() > 0)
	# Mixing: positive pilot roll lowers the right side, positive pitch raises the
	# nose, positive yaw spins the nose right (signs verified against the layout
	# tables in motor_model.gd).
	#
	# MIXED AGAINST THE ACTUAL MOUNT OFFSETS, not against ±1 signs (E.q1). For the
	# quad-X those offsets ARE ±1, so this is the same arithmetic it always was.
	# For any other layout each rotor is commanded in proportion to its own moment
	# arm, which is what produces a pure torque rather than a torque plus a
	# sideways lurch — the mixer follows the geometry instead of assuming corners.
	#
	# Air-mode floor keeps attitude authority at zero throttle. In 3D mode
	# there is no floor — thrust runs the full [-1, 1] range and PID
	# corrections around zero provide the authority.
	var motor_floor: float = config.motor_idle
	if config.throttle_curve == FlightConfig.ThrottleCurve.THREE_D:
		motor_floor = -1.0
	for i: int in _motors.rotor_count:
		var motor: float = collective
		motor -= command.x * _motors.x_offsets[i]
		motor -= command.y * _motors.z_offsets[i]
		motor -= command.z * _motors.spins[i]
		_motors.set_command(i, clampf(motor, motor_floor, 1.0))


func _target_rates() -> Vector3:
	if rate_override_enabled:
		return rate_override
	if autopilot:
		return _autopilot_rates()
	if flight_mode == FlightMode.ACRO:
		return _input.rate_command
	# Angle mode (handoff §6.4): stick deflection → target attitude, and an
	# attitude P loop converts the error to a target rate for the SAME rate
	# controller. Yaw stays rate-based. The asin-based angles are only valid
	# within ±90°, fine for a ±55° self-level envelope.
	var max_angle: float = deg_to_rad(config.max_angle_deg)
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var current_pitch: float = asin(clampf(forward.y, -1.0, 1.0))
	var current_roll: float = asin(clampf(-right.y, -1.0, 1.0))
	var roll_rate: float = config.angle_p * (_input.stick_shaped.x * max_angle - current_roll)
	var pitch_rate: float = config.angle_p * (_input.stick_shaped.y * max_angle - current_pitch)
	# Never command faster than acro's rate limits.
	var max_roll: float = deg_to_rad(config.max_rate_deg.x)
	var max_pitch: float = deg_to_rad(config.max_rate_deg.y)
	return Vector3(
		clampf(roll_rate, -max_roll, max_roll),
		clampf(pitch_rate, -max_pitch, max_pitch),
		_input.rate_command.z)


## Pause-mode position hold: tilt against horizontal drift (braking), level
## out otherwise, yaw frozen; the collective override in _physics_process
## handles the vertical axis. Reuses the angle-mode attitude loop with
## computed target angles instead of stick input.
func _autopilot_rates() -> Vector3:
	var max_angle: float = deg_to_rad(config.max_angle_deg)
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var forward_flat: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	var right_flat: Vector3 = Vector3(right.x, 0.0, right.z).normalized()
	var horizontal: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var tilt: float = deg_to_rad(config.autopilot_tilt_deg_per_ms)
	var target_pitch: float = clampf(horizontal.dot(forward_flat) * tilt,
			-max_angle * 0.6, max_angle * 0.6)
	var target_roll: float = clampf(-horizontal.dot(right_flat) * tilt,
			-max_angle * 0.6, max_angle * 0.6)
	var current_pitch: float = asin(clampf(forward.y, -1.0, 1.0))
	var current_roll: float = asin(clampf(-right.y, -1.0, 1.0))
	var max_roll: float = deg_to_rad(config.max_rate_deg.x)
	var max_pitch: float = deg_to_rad(config.max_rate_deg.y)
	return Vector3(
			clampf(config.angle_p * (target_roll - current_roll), -max_roll, max_roll),
			clampf(config.angle_p * (target_pitch - current_pitch), -max_pitch, max_pitch),
			0.0)


## Body angular velocity mapped to pilot axes. Godot body space: +X right,
## +Y up, +Z back (front is -Z); angular_velocity is world-space, and the
## basis transpose (= inverse, orthonormal) brings it into body space.
func _measured_rates() -> Vector3:
	var body_angular: Vector3 = global_basis.transposed() * angular_velocity
	return Vector3(-body_angular.z, body_angular.x, -body_angular.y)


func _apply_aerodynamics() -> void:
	# Explicit, config-driven — the body's built-in damping is disabled
	# (handoff §6.5) so everything the overlay can tune lives in our model.
	apply_central_force(-config.drag_coefficient * linear_velocity.length() * linear_velocity)
	apply_torque(-config.angular_damping * angular_velocity)
