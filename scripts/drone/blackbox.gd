class_name Blackbox
extends Node

## Flight data recorder (Betaflight-style): one CSV row per physics tick
## while armed, one file per arm session under user://blackbox/. No UI —
## arming opens a log, disarming closes it; the absolute path prints to the
## console so the recording is easy to find. Disabled under the headless
## driver so test runs don't spray files.

const DIR_PATH: String = "user://blackbox"
## Flush cadence in ticks (1 s at 240 Hz) so data survives an abrupt quit.
const FLUSH_EVERY: int = 240

@onready var _drone: FlightController = get_parent() as FlightController

var _file: FileAccess
var _time: float = 0.0
var _rows: int = 0


func _ready() -> void:
	set_physics_process(DisplayServer.get_name() != "headless")


func _physics_process(delta: float) -> void:
	if _drone.armed and _file == null:
		_open()
	elif not _drone.armed and _file != null:
		_close()
	if _file == null:
		return
	_time += delta
	var target: Vector3 = _drone.telemetry_target_rates
	var measured: Vector3 = _drone.telemetry_measured_rates
	var integrator: Vector3 = _drone.telemetry_integrator()
	var position: Vector3 = _drone.global_position
	_file.store_csv_line(PackedStringArray([
		"%.4f" % _time,
		str(_drone.get_contact_count()),
		"%.3f" % _drone.collective,
		"%.3f" % target.x, "%.3f" % target.y, "%.3f" % target.z,
		"%.3f" % measured.x, "%.3f" % measured.y, "%.3f" % measured.z,
		"%.5f" % integrator.x, "%.5f" % integrator.y, "%.5f" % integrator.z,
		"%.3f" % _drone.motor_output(0), "%.3f" % _drone.motor_output(1),
		"%.3f" % _drone.motor_output(2), "%.3f" % _drone.motor_output(3),
		"%.2f" % _drone.linear_velocity.length(),
		"%.2f" % position.x, "%.2f" % position.y, "%.2f" % position.z,
	]))
	_rows += 1
	if _rows % FLUSH_EVERY == 0:
		_file.flush()


func _open() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_PATH))
	var path: String = "%s/flight_%d.csv" % [DIR_PATH, Time.get_ticks_msec()]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("[blackbox] cannot open %s" % path)
		return
	_time = 0.0
	_rows = 0
	_file.store_csv_line(PackedStringArray([
		"t", "contacts", "collective",
		"tgt_roll", "tgt_pitch", "tgt_yaw",
		"meas_roll", "meas_pitch", "meas_yaw",
		"i_roll", "i_pitch", "i_yaw",
		"m_fl", "m_fr", "m_bl", "m_br",
		"speed", "x", "y", "z",
	]))
	print("[blackbox] recording %s" % ProjectSettings.globalize_path(path))


func _close() -> void:
	_file.flush()
	print("[blackbox] closed (%d rows)" % _rows)
	_file = null
