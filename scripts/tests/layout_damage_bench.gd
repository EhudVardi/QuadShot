extends SceneTree

## DIAGNOSTIC BENCH, written to answer two things the human flew and did not
## believe (2026-08-15). It measures rather than asserts, because both questions
## are "why does this feel wrong" and neither has a pass/fail answer yet.
##
## **Q1 — "I'm not sure the hexa feels different from the Kestrel, in yaw for
## example."** The agent predicted roughly 1.5x the yaw authority. Table A
## measures the yaw torque OPEN LOOP (the raw authority) and then the yaw rate
## the pilot actually gets CLOSED LOOP (through the rate PID, which is how the
## aircraft is really flown). If those two disagree, the prediction was made
## about the wrong quantity.
##
## **Q2 — "the props got damaged but way less [than the VTX], the quad is still
## absolutely flyable... taking damage from being shot makes the quad way WAY
## worse to fly."** Table B applies the SAME damage as a crash and as a bullet
## and prints every component, then flies both wounded aircraft and measures what
## the pilot would feel.
##
## Run: <godot> --headless -s scripts/tests/layout_damage_bench.gd --path .

const SETTLE_S: float = 2.0
const SAMPLE_S: float = 1.5
const ALT: float = 40.0
## Yaw rate asked of the rate controller, rad/s (about 170 deg/s).
const YAW_TARGET: float = 3.0
## Open-loop yaw differential, as a fraction of full command.
const YAW_COMMAND: float = 0.25
const HIT: float = 40.0

enum { OPEN_LOOP, CLOSED_LOOP, WOUND_FLY, REPORT }

var _open: Array[Dictionary] = []
var _closed: Array[Dictionary] = []
var _components: Array[Dictionary] = []
var _flight: Array[Dictionary] = []

var _phase: int = OPEN_LOOP
var _queue: Array[Dictionary] = []
var _index: int = 0
var _ticks: int = 0
var _arena: Node3D
var _drone: FlightController
var _sum_drift: float = 0.0
var _sum_tilt: float = 0.0
var _n: int = 0
var _peak_rate: float = 0.0
var _pps: float


func _initialize() -> void:
	# An instrument measures the REPO's numbers, never one machine's tuning.
	TunableConfig.user_overrides_enabled = false
	_pps = float(Engine.physics_ticks_per_second)
	for frame_id: String in [Frames.KESTREL, Frames.HEXA]:
		_queue.append({"frame": frame_id})
	print("[layout] severity is forced to 1.0 for the damage tables — the design")
	print("[layout] target from E.q8, and what the human flew.")
	physics_frame.connect(_on_frame)


func _on_frame() -> void:
	match _phase:
		OPEN_LOOP:
			_measure_open_loop()
			_phase = CLOSED_LOOP
			_index = 0
			_ticks = 0
		CLOSED_LOOP:
			_run_closed_loop()
		WOUND_FLY:
			_run_wound_flight()
		REPORT:
			_report()


## TABLE A, first half: raw yaw AUTHORITY, with the rate controller out of the
## way entirely. A pure yaw differential is written straight onto the motors and
## the resulting angular acceleration is read off the body. This is the quantity
## the 1.5x prediction was about.
func _measure_open_loop() -> void:
	for case: Dictionary in _queue:
		var arena := Node3D.new()
		root.add_child(arena)
		var drone: FlightController = Frames.build(String(case["frame"]))
		drone.gravity_scale = 0.0
		arena.add_child(drone)
		var motors: MotorModel = drone.get_node("MotorModel") as MotorModel
		# Hover collective plus a pure yaw differential on the spin signs — the
		# mixer's yaw term, applied by hand.
		var hover: float = drone.hover_throttle()
		for i: int in motors.rotor_count:
			motors.set_command(i, clampf(hover - YAW_COMMAND * motors.spins[i],
					0.0, 1.0))
		motors.prime(0.0)
		for i: int in motors.rotor_count:
			motors.set_command(i, clampf(hover - YAW_COMMAND * motors.spins[i],
					0.0, 1.0))
		# Jump the lag straight to the commanded value so this measures the
		# mixer and the torque model, not the spool-up.
		for i: int in motors.rotor_count:
			motors._outputs[i] = clampf(hover - YAW_COMMAND * motors.spins[i],
					0.0, 1.0)
		var yaw_sum: float = 0.0
		for i: int in motors.rotor_count:
			yaw_sum += motors.spins[i] * motors._outputs[i]
		_open.append({
			"frame": case["frame"],
			"rotors": motors.rotor_count,
			"yaw_sum": yaw_sum,
			"torque": drone.config.yaw_authority * yaw_sum,
			"hover": hover,
		})
		arena.queue_free()


## TABLE A, second half: the yaw rate the PILOT gets, through the rate PID.
func _run_closed_loop() -> void:
	if _drone == null:
		_arena = Node3D.new()
		root.add_child(_arena)
		_drone = Frames.build(String(_queue[_index]["frame"]))
		_arena.add_child(_drone)
		_drone.global_position = Vector3(0.0, ALT, 0.0)
		_drone.arm()
		_drone.prime_motors(_drone.hover_throttle())
		_drone.throttle_override = _drone.hover_throttle()
		_drone.rate_override_enabled = true
		_drone.rate_override = Vector3(0.0, 0.0, YAW_TARGET)
		_peak_rate = 0.0
		_ticks = 0
		return
	_ticks += 1
	_peak_rate = maxf(_peak_rate, absf(_drone.telemetry_measured_rates.z))
	if _ticks < int(SAMPLE_S * _pps):
		return
	_closed.append({
		"frame": _queue[_index]["frame"],
		"asked": YAW_TARGET,
		"got": _drone.telemetry_measured_rates.z,
		"peak": _peak_rate,
	})
	_teardown()
	_index += 1
	if _index >= _queue.size():
		_measure_components()
		_index = 0
		_phase = WOUND_FLY
	_ticks = 0


## TABLE B, first half: the same damage delivered two ways, every component read
## off the registry afterwards.
func _measure_components() -> void:
	for frame_id: String in [Frames.KESTREL, Frames.HEXA]:
		for mode: String in ["crash", "bullet"]:
			var arena := Node3D.new()
			root.add_child(arena)
			var drone: FlightController = Frames.build(frame_id)
			arena.add_child(drone)
			drone.damage_config.severity = 1.0
			# A crash is directionless; a bullet arrives from a bearing.
			drone.last_hit_direction = Vector3.ZERO if mode == "crash" \
					else (drone.global_basis * Vector3(1.0, 0.0, -1.0)).normalized()
			drone.apply_hit_to_motors(HIT)
			var healths: PackedStringArray = []
			var lowest: float = 1.0
			var motors: MotorModel = drone.get_node("MotorModel") as MotorModel
			for i: int in motors.rotor_count:
				healths.append("%.2f" % drone.motor_health(i))
				lowest = minf(lowest, drone.motor_health(i))
			# The VTX arithmetic, lifted from main._on_player_damaged so the two
			# cannot disagree: it is the same for a crash and for a bullet.
			var dc: DamageConfig = drone.damage_config
			var vtx: float = clampf(HIT / 100.0 * dc.video_damage_scale
					* dc.severity, 0.0, 1.0)
			_components.append({
				"frame": frame_id,
				"mode": mode,
				"rotors": "/".join(healths),
				"worst": lowest,
				"spread": _spread(drone, motors),
				"vtx_lost": vtx,
			})
			arena.queue_free()


func _spread(drone: FlightController, motors: MotorModel) -> float:
	var lo: float = 1.0
	var hi: float = 0.0
	for i: int in motors.rotor_count:
		lo = minf(lo, drone.motor_health(i))
		hi = maxf(hi, drone.motor_health(i))
	return hi - lo


## TABLE B, second half: fly both wounded aircraft on the position-hold autopilot
## and measure what the pilot would actually feel — drift off station and tilt
## off level. This is the number behind "way WAY worse to fly".
func _run_wound_flight() -> void:
	if _drone == null:
		if _index >= _components.size():
			_phase = REPORT
			return
		var case: Dictionary = _components[_index]
		_arena = Node3D.new()
		root.add_child(_arena)
		_drone = Frames.build(String(case["frame"]))
		_arena.add_child(_drone)
		_drone.global_position = Vector3(0.0, ALT, 0.0)
		_drone.damage_config.severity = 1.0
		_drone.last_hit_direction = Vector3.ZERO if case["mode"] == "crash" \
				else (_drone.global_basis * Vector3(1.0, 0.0, -1.0)).normalized()
		_drone.apply_hit_to_motors(HIT)
		_drone.arm()
		_drone.prime_motors(_drone.hover_throttle())
		_drone.autopilot = true
		_sum_drift = 0.0
		_sum_tilt = 0.0
		_n = 0
		_ticks = 0
		return
	_ticks += 1
	if _ticks < int(SETTLE_S * _pps):
		return
	var flat := Vector3(_drone.linear_velocity.x, 0.0, _drone.linear_velocity.z)
	_sum_drift += flat.length()
	_sum_tilt += rad_to_deg(_drone.global_basis.y.angle_to(Vector3.UP))
	_n += 1
	if _ticks < int((SETTLE_S + SAMPLE_S) * _pps):
		return
	var case: Dictionary = _components[_index]
	_flight.append({
		"frame": case["frame"],
		"mode": case["mode"],
		"drift": _sum_drift / float(maxi(_n, 1)),
		"tilt": _sum_tilt / float(maxi(_n, 1)),
	})
	_teardown()
	_index += 1
	_ticks = 0


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null


func _report() -> void:
	print("")
	print("=== TABLE A — IS THE HEXA'S YAW ACTUALLY DIFFERENT? ===")
	print("[layout] 'yaw sum' is the summed signed rotor output the torque model reads.")
	print("[layout] 'torque' is what the body actually receives, in N.m.")
	print("[layout] %8s %7s %9s %9s" % ["frame", "rotors", "yaw sum", "torque"])
	for row: Dictionary in _open:
		print("[layout] %8s %7d %9.3f %9.3f"
				% [row["frame"], row["rotors"], row["yaw_sum"], row["torque"]])
	var ratio: float = 0.0
	if _open.size() == 2 and absf(float(_open[0]["torque"])) > 0.0001:
		ratio = float(_open[1]["torque"]) / float(_open[0]["torque"])
	print("[layout] OPEN LOOP: the hexa has %.2fx the Kestrel's raw yaw authority." % ratio)
	print("")
	print("[layout] But this is a RATE-CONTROLLED aircraft. Asked for %.1f rad/s of yaw:"
			% YAW_TARGET)
	print("[layout] %8s %11s %11s" % ["frame", "peak rad/s", "held rad/s"])
	for row: Dictionary in _closed:
		print("[layout] %8s %11.3f %11.3f"
				% [row["frame"], row["peak"], row["got"]])

	print("")
	print("=== TABLE B — WHY A CRASH IS BARELY FELT AND A BULLET IS NOT ===")
	print("[layout] Same %.0f points of damage, delivered two ways, at severity 1.0." % HIT)
	print("[layout] 'spread' is the gap between the best and worst rotor: it is what")
	print("[layout] the airframe has to FIGHT, and a symmetric wound has none.")
	print("[layout] %8s %8s %-26s %8s %8s %9s"
			% ["frame", "mode", "rotor health", "worst", "spread", "vtx lost"])
	for row: Dictionary in _components:
		print("[layout] %8s %8s %-26s %8.2f %8.2f %9.2f"
				% [row["frame"], row["mode"], row["rotors"], row["worst"],
				row["spread"], row["vtx_lost"]])

	print("")
	print("[layout] And what the pilot feels, flying each wounded airframe on the")
	print("[layout] position-hold autopilot — drift off station and tilt off level:")
	print("[layout] %8s %8s %11s %11s"
			% ["frame", "mode", "drift m/s", "tilt deg"])
	for row: Dictionary in _flight:
		print("[layout] %8s %8s %11.2f %11.2f"
				% [row["frame"], row["mode"], row["drift"], row["tilt"]])

	for child: Node in root.get_children():
		child.free()
	print("")
	print("[layout] DONE (measurement only — this bench has no pass/fail)")
	quit(0)
