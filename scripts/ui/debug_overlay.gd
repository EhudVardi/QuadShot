extends CanvasLayer

## Debug & tuning overlay (handoff §8). Function over beauty: telemetry up
## top, sliders bound live to every tunable config field below, save/load to
## user:// per config. Rows are generated from the spec tables so a new
## config field only needs a table entry.
##
## Every control uses FOCUS_NONE: without focus, Godot's built-in ui_*
## joypad navigation can never grab the flight sticks — the mouse tunes
## while the gamepad keeps flying.

@export var drone: FlightController
@export var combat_config: CombatConfig
@export var audio_config: AudioConfig

@onready var _telemetry: Label = $Panel/VBox/TelemetryText
@onready var _motors_box: VBoxContainer = $Panel/VBox/Motors
@onready var _tuning: VBoxContainer = $Panel/VBox/Scroll/Tuning

var _configs: Array[TunableConfig] = []
var _motor_bars: Array[ProgressBar] = []
## One callable per generated control; re-reads the config after load/reset.
var _refreshers: Array[Callable] = []

const _MOTOR_NAMES: Array[String] = ["FL", "FR", "BL", "BR"]
const _AXIS_NAMES: Array[String] = ["roll", "pitch", "yaw"]

# Scalar FlightConfig fields: property, slider min/max/step.
const _FLIGHT_FLOAT_ROWS: Array[Array] = [
	["mass", 0.2, 2.0, 0.01],
	["arm_length", 0.05, 0.3, 0.005],
	["thrust_to_weight_ratio", 1.5, 8.0, 0.05],
	["motor_lag_tau", 0.0, 0.2, 0.005],
	["motor_idle", 0.0, 0.2, 0.005],
	["yaw_authority", 0.0, 5.0, 0.05],
	["reverse_thrust_scale", 0.0, 1.0, 0.01],
	["integral_limit", 0.0, 0.5, 0.01],
	["crash_iterm_decay", 0.0, 1.0, 0.05],
	["iterm_error_gate_deg", 0.0, 1000.0, 10.0],
	["gyro_lpf_hz", 0.0, 120.0, 1.0],
	["dterm_lpf_hz", 0.0, 120.0, 1.0],
	["rc_smoothing_hz", 0.0, 120.0, 1.0],
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

# Vector3 (per-axis) FlightConfig fields: property, slider min/max/step.
const _FLIGHT_VECTOR_ROWS: Array[Array] = [
	["max_rate_deg", 100.0, 1200.0, 10.0],
	["expo", 0.0, 1.0, 0.01],
	["rate_p", 0.0, 0.02, 0.0001],
	["rate_i", 0.0, 0.01, 0.0001],
	["rate_d", 0.0, 0.0003, 0.000005],
]

const _COMBAT_FLOAT_ROWS: Array[Array] = [
	["fire_rate", 1.0, 30.0, 0.5],
	["muzzle_speed", 20.0, 200.0, 5.0],
	["projectile_damage", 1.0, 100.0, 1.0],
	["projectile_lifetime", 0.5, 8.0, 0.1],
	["projectile_gravity_scale", 0.0, 1.0, 0.05],
	["inherit_velocity", 0.0, 1.0, 0.05],
	["player_max_health", 10.0, 500.0, 10.0],
	["crash_damage_speed", 2.0, 40.0, 1.0],
	["crash_damage_scale", 0.0, 20.0, 0.5],
	["respawn_delay", 0.0, 10.0, 0.5],
	["turret_health", 10.0, 300.0, 10.0],
	["turret_range", 10.0, 120.0, 5.0],
	["turret_fire_rate", 0.2, 10.0, 0.2],
	["turret_muzzle_speed", 10.0, 120.0, 5.0],
	["turret_damage", 1.0, 50.0, 1.0],
	["turret_turn_speed_deg", 10.0, 360.0, 10.0],
	["turret_respawn_delay", 0.0, 60.0, 5.0],
	["turret_points", 0.0, 1000.0, 10.0],
	["target_points", 0.0, 500.0, 10.0],
	["target_respawn_delay", 0.0, 30.0, 1.0],
	["enemy_health", 5.0, 300.0, 5.0],
	["enemy_points", 0.0, 1000.0, 10.0],
	["enemy_speed", 2.0, 40.0, 1.0],
	["enemy_accel", 2.0, 60.0, 1.0],
	["enemy_sight_range", 10.0, 150.0, 5.0],
	["enemy_preferred_range", 5.0, 60.0, 1.0],
	["enemy_fire_rate", 0.2, 8.0, 0.1],
	["enemy_muzzle_speed", 10.0, 120.0, 5.0],
	["enemy_damage", 1.0, 50.0, 1.0],
	["enemy_aim_jitter_deg", 0.0, 15.0, 0.5],
	["missile_lock_range", 10.0, 150.0, 5.0],
	["missile_lock_cone_deg", 2.0, 45.0, 1.0],
	["missile_lock_time", 0.1, 4.0, 0.1],
	["missile_speed", 10.0, 120.0, 5.0],
	["missile_turn_rate_deg", 30.0, 720.0, 10.0],
	["missile_damage", 5.0, 200.0, 5.0],
	["missile_cooldown", 0.0, 10.0, 0.5],
	["missile_prox_radius", 0.5, 8.0, 0.5],
	["missile_lifetime", 1.0, 15.0, 0.5],
	["wave_base_enemies", 1.0, 10.0, 1.0],
	["wave_growth", 0.0, 5.0, 0.5],
	["wave_intermission", 0.0, 30.0, 1.0],
	["sortie_waves", 1.0, 10.0, 1.0],
	["sortie_enemy_bonus", 0.0, 5.0, 0.5],
	["combo_window", 0.5, 15.0, 0.5],
	["combo_max", 1.0, 10.0, 1.0],
]

const _AUDIO_FLOAT_ROWS: Array[Array] = [
	["master_volume", 0.0, 1.0, 0.01],
	["sfx_volume", 0.0, 1.0, 0.01],
	["motor_volume", 0.0, 1.0, 0.01],
	["wind_volume", 0.0, 1.0, 0.01],
]


func _ready() -> void:
	_configs = [drone.config, combat_config, audio_config]
	_build_motor_bars()
	_add_section_header("FLIGHT")
	_add_throttle_curve_row(drone.config)
	_add_config_rows(drone.config, _FLIGHT_FLOAT_ROWS, _FLIGHT_VECTOR_ROWS)
	_add_section_header("COMBAT")
	_add_config_rows(combat_config, _COMBAT_FLOAT_ROWS, [])
	_add_section_header("AUDIO")
	_add_config_rows(audio_config, _AUDIO_FLOAT_ROWS, [])
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
		_motor_bars[i].value = absf(drone.motor_output(i))


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


func _add_section_header(title: String) -> void:
	_tuning.add_child(HSeparator.new())
	var header := Label.new()
	header.text = "— %s —" % title
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tuning.add_child(header)


func _add_config_rows(config: TunableConfig, float_rows: Array[Array],
		vector_rows: Array[Array]) -> void:
	for spec: Array in float_rows:
		_add_slider(_tuning, str(spec[0]), spec[1], spec[2], spec[3],
				func() -> float: return config.get(str(spec[0])),
				func(v: float) -> void: config.set(str(spec[0]), v))
	for spec: Array in vector_rows:
		var header := Label.new()
		header.text = str(spec[0])
		_tuning.add_child(header)
		for axis: int in 3:
			_add_slider(_tuning, "  " + _AXIS_NAMES[axis], spec[1], spec[2], spec[3],
					func() -> float:
						var vec: Vector3 = config.get(str(spec[0]))
						return vec[axis],
					func(v: float) -> void:
						var vec: Vector3 = config.get(str(spec[0]))
						vec[axis] = v
						config.set(str(spec[0]), vec))


func _add_throttle_curve_row(config: FlightConfig) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "throttle_curve"
	label.custom_minimum_size.x = 180.0
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	for curve_name: String in FlightConfig.ThrottleCurve.keys():
		option.add_item(curve_name.to_lower())
	option.selected = config.throttle_curve
	option.item_selected.connect(func(index: int) -> void:
		config.throttle_curve = index as FlightConfig.ThrottleCurve)
	_refreshers.append(func() -> void: option.selected = config.throttle_curve)
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
	for config: TunableConfig in _configs:
		var err: Error = config.save_to_user()
		print("[config] save to %s: %s" % [config.save_path(),
				"OK" if err == OK else error_string(err)])


func _on_load() -> void:
	for config: TunableConfig in _configs:
		if config.load_from_user():
			print("[config] loaded %s" % config.save_path())
		else:
			print("[config] no saved config at %s" % config.save_path())
	_refresh_all()


func _on_defaults() -> void:
	for config: TunableConfig in _configs:
		config.reset_to_defaults()
	_refresh_all()
	print("[config] reset to defaults")
