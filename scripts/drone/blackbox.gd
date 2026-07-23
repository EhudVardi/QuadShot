class_name Blackbox
extends Node

## Flight data recorder (Betaflight-style): one CSV row per physics tick
## while armed, one file per arm session under user://blackbox/. No UI —
## arming opens a log, disarming closes it; the absolute path prints to the
## console so the recording is easy to find. Disabled under the headless
## driver so test runs don't spray files.
##
## COMBAT EVENT LOG (GAMEPLAY-DESIGN v1.29, sized there before it was built):
## a sparse companion file, `events_<stamp>.csv` beside `flight_<stamp>.csv` —
## one line per combat EVENT (shot fired, hit landed, spawn, kill, wave), not
## one per physics tick. At real combat tempo that is hundreds of lines next
## to the flight recorder's 21 MB, and it is what lets a session review report
## an actual hit rate instead of inferring "buzzing, not crashing" from
## position data alone (the v1.29 read-back's stated limit).
##
## Emitters call the STATIC `Blackbox.log_event(...)` — null-safe, the
## SoundBank precedent — so combat code never holds a reference and headless
## bench runs (where no file is ever open) drop events for free.

const DIR_PATH: String = "user://blackbox"
## Flush cadence in ticks (1 s at 240 Hz) so data survives an abrupt quit.
const FLUSH_EVERY: int = 240

## The instance events route to. One live game drone in practice; a bench
## drone that registers itself is harmless because its file never opens.
static var _active: Blackbox = null

@onready var _drone: FlightController = get_parent() as FlightController

var _file: FileAccess
var _events: FileAccess
var _event_rows: int = 0
var _time: float = 0.0
var _rows: int = 0


## Record a combat event. `at` is the position the event happened at (impact
## point, spawn point) — deliberately NOT the drone's position, which the
## flight file already carries at the same timestamp; omit it for events with
## no place of their own. Safe to call from anywhere, any time: without an
## open recording it is a no-op.
static func log_event(kind: StringName, detail: String = "", value: float = 0.0,
		at: Vector3 = Vector3.INF) -> void:
	if _active == null or not is_instance_valid(_active) \
			or _active._events == null:
		return
	_active._write_event(kind, detail, value, at)


func _ready() -> void:
	set_physics_process(DisplayServer.get_name() != "headless")
	_active = self


func _exit_tree() -> void:
	if _active == self:
		_active = null


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


## flight_YYYYMMDD_HHMMSS.csv, local time. The old name used ticks since
## engine start, which restarted at zero every session — so a log's number
## said "6 seconds after launch", sorted meaninglessly, and collided across
## runs. Time-of-day sorts chronologically by name and says when you flew.
func _next_path() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system(false)
	var stamp: String = "%04d%02d%02d_%02d%02d%02d" % [
		now["year"], now["month"], now["day"],
		now["hour"], now["minute"], now["second"],
	]
	var path: String = "%s/flight_%s.csv" % [DIR_PATH, stamp]
	# Two arms inside one second would otherwise overwrite the first log.
	var attempt: int = 2
	while FileAccess.file_exists(path):
		path = "%s/flight_%s_%d.csv" % [DIR_PATH, stamp, attempt]
		attempt += 1
	return path


func _open() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_PATH))
	var path: String = _next_path()
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
	# The companion event log shares the flight file's stamp, so a session's
	# pair sorts together and reviews join them on the shared `t` clock.
	var events_path: String = path.replace("/flight_", "/events_")
	_events = FileAccess.open(events_path, FileAccess.WRITE)
	if _events == null:
		push_warning("[blackbox] cannot open %s" % events_path)
		return
	_event_rows = 0
	_events.store_csv_line(PackedStringArray([
		"t", "kind", "detail", "value", "x", "y", "z",
	]))


func _write_event(kind: StringName, detail: String, value: float,
		at: Vector3) -> void:
	var placed: bool = at.x != INF
	_events.store_csv_line(PackedStringArray([
		"%.4f" % _time, String(kind), detail, "%.2f" % value,
		"%.2f" % at.x if placed else "",
		"%.2f" % at.y if placed else "",
		"%.2f" % at.z if placed else "",
	]))
	_event_rows += 1
	# Sparse by design (hundreds per session), so flushing every line is cheap
	# and the log survives the crash it will most often be read to explain.
	_events.flush()


func _close() -> void:
	_file.flush()
	print("[blackbox] closed (%d rows)" % _rows)
	_file = null
	if _events != null:
		_events.flush()
		print("[blackbox] events closed (%d events)" % _event_rows)
		_events = null
