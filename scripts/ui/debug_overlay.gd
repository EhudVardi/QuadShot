extends CanvasLayer

## Debug & tuning overlay (handoff §8). Function over beauty: telemetry up
## top, sliders bound live to every FlightConfig field below, save/load to
## user://flight_config.tres. Rows are generated from the spec tables so a
## new config field only needs a table entry.
##
## Every control uses FOCUS_NONE: without focus, Godot's built-in ui_*
## joypad navigation can never grab the flight sticks — the mouse tunes
## while the gamepad keeps flying.

@export var drone: FlightController

@onready var _telemetry: Label = $Panel/VBox/TelemetryText
@onready var _motors_box: VBoxContainer = $Panel/VBox/Motors
@onready var _tuning: VBoxContainer = $Panel/VBox/Scroll/Tuning

var _config: FlightConfig
var _motor_bars: Array[ProgressBar] = []
## One callable per generated control; re-reads the config after load/reset.
var _refreshers: Array[Callable] = []

const _MOTOR_NAMES: Array[String] = ["FL", "FR", "BL", "BR"]
const _AXIS_NAMES: Array[String] = ["roll", "pitch", "yaw"]

# Scalar config fields: property, slider min/max/step.
const _FLOAT_ROWS: Array[Array] = [
	["mass", 0.2, 2.0, 0.01],
	["arm_length", 0.05, 0.3, 0.005],
	["thrust_to_weight_ratio", 1.5, 8.0, 0.05],
	["motor_lag_tau", 0.0, 0.2, 0.005],
	["motor_idle", 0.0, 0.2, 0.005],
	["yaw_authority", 0.0, 5.0, 0.05],
	["integral_limit", 0.0, 0.5, 0.01],
	["stick_deadzone", 0.0, 0.3, 0.005],
	["max_angle_deg", 10.0, 80.0, 1.0],
	["angle_p", 0.0, 15.0, 0.1],
	["drag_coefficient", 0.0, 0.2, 0.001],
	["angular_damping", 0.0, 0.2, 0.001],
	["fpv_uptilt_deg", 0.0, 60.0, 1.0],
	["fpv_fov_deg", 60.0, 150.0, 1.0],
	["chase_distance", 1.0, 10.0, 0.1],
	["chase_height", 0.0, 5.0, 0.1],
	["chase_smoothing", 1.0, 20.0, 0.5],
	["arm_throttle_threshold", 0.0, 0.2, 0.01],
]

# Vector3 (per-axis) config fields: property, slider min/max/step.
const _VECTOR_ROWS: Array[Array] = [
	["max_rate_deg", 100.0, 1200.0, 10.0],
	["expo", 0.0, 1.0, 0.01],
	["rate_p", 0.0, 0.02, 0.0001],
	["rate_i", 0.0, 0.01, 0.0001],
	["rate_d", 0.0, 0.0003, 0.000005],
]


func _ready() -> void:
	_config = drone.config
	_build_motor_bars()
	_build_tuning_rows()
	$Panel/VBox/Buttons/SaveButton.pressed.connect(_on_save)
	$Panel/VBox/Buttons/LoadButton.pressed.connect(_on_load)
	$Panel/VBox/Buttons/DefaultsButton.pressed.connect(_on_defaults)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"overlay_toggle"):
		visible = not visible
	if visible:
		_update_telemetry()


func _update_telemetry() -> void:
	var target: Vector3 = drone.telemetry_target_rates
	var actual: Vector3 = drone.telemetry_measured_rates
	var speed: float = drone.linear_velocity.length()
	_telemetry.text = (
		"FPS %d | physics %d Hz\n" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second]
		+ "%s | %s | throttle %3.0f%%\n" % [
			"ARMED" if drone.armed else "disarmed",
			FlightController.FlightMode.keys()[drone.flight_mode],
			drone.collective * 100.0,
		]
		+ "alt %6.1f m | speed %5.1f m/s (%4.0f km/h)\n" % [
			drone.global_position.y, speed, speed * 3.6,
		]
		+ "rates deg/s      target    actual\n"
		+ " roll        %9.1f %9.1f\n" % [rad_to_deg(target.x), rad_to_deg(actual.x)]
		+ " pitch       %9.1f %9.1f\n" % [rad_to_deg(target.y), rad_to_deg(actual.y)]
		+ " yaw         %9.1f %9.1f" % [rad_to_deg(target.z), rad_to_deg(actual.z)]
	)
	for i: int in _motor_bars.size():
		_motor_bars[i].value = drone.motor_output(i)


func _build_motor_bars() -> void:
	for motor_name: String in _MOTOR_NAMES:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = motor_name
		label.custom_minimum_size.x = 30.0
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 14.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.focus_mode = Control.FOCUS_NONE
		row.add_child(label)
		row.add_child(bar)
		_motor_bars.append(bar)
		_motors_box.add_child(row)


func _build_tuning_rows() -> void:
	_add_throttle_curve_row()
	for spec: Array in _FLOAT_ROWS:
		_add_slider(_tuning, str(spec[0]), spec[1], spec[2], spec[3],
				func() -> float: return _config.get(str(spec[0])),
				func(v: float) -> void: _config.set(str(spec[0]), v))
	for spec: Array in _VECTOR_ROWS:
		var header := Label.new()
		header.text = str(spec[0])
		_tuning.add_child(header)
		for axis: int in 3:
			_add_slider(_tuning, "  " + _AXIS_NAMES[axis], spec[1], spec[2], spec[3],
					func() -> float:
						var vec: Vector3 = _config.get(str(spec[0]))
						return vec[axis],
					func(v: float) -> void:
						var vec: Vector3 = _config.get(str(spec[0]))
						vec[axis] = v
						_config.set(str(spec[0]), vec))


func _add_throttle_curve_row() -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "throttle_curve"
	label.custom_minimum_size.x = 180.0
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	for curve_name: String in FlightConfig.ThrottleCurve.keys():
		option.add_item(curve_name.to_lower())
	option.selected = _config.throttle_curve
	option.item_selected.connect(func(index: int) -> void:
		_config.throttle_curve = index as FlightConfig.ThrottleCurve)
	_refreshers.append(func() -> void: option.selected = _config.throttle_curve)
	row.add_child(label)
	row.add_child(option)
	_tuning.add_child(row)


func _add_slider(parent: Container, label_text: String, min_value: float,
		max_value: float, step: float, getter: Callable, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size.x = 180.0
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 64.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = getter.call()
	value_label.text = _format_value(getter.call(), step)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		value_label.text = _format_value(v, step))
	_refreshers.append(func() -> void:
		slider.set_value_no_signal(getter.call())
		value_label.text = _format_value(getter.call(), step))
	row.add_child(name_label)
	row.add_child(slider)
	row.add_child(value_label)
	parent.add_child(row)


static func _format_value(value: float, step: float) -> String:
	var decimals: int = 0
	if step < 1.0:
		decimals = int(ceilf(-log(step) / log(10.0)))
	return String.num(value, decimals)


func _refresh_all() -> void:
	for refresher: Callable in _refreshers:
		refresher.call()


func _on_save() -> void:
	var err: Error = _config.save_to_user()
	print("[config] save to %s: %s" % [FlightConfig.SAVE_PATH,
			"OK" if err == OK else error_string(err)])


func _on_load() -> void:
	if _config.load_from_user():
		_refresh_all()
		print("[config] loaded %s" % FlightConfig.SAVE_PATH)
	else:
		print("[config] no saved config at %s" % FlightConfig.SAVE_PATH)


func _on_defaults() -> void:
	_config.reset_to_defaults()
	_refresh_all()
	print("[config] reset to defaults")
