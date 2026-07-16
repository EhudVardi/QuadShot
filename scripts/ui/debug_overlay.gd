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
## Optional: only the dev-room testbed wires this (its LookController applies
## it). Null in main.tscn, where the LOOK section is simply skipped.
@export var look_config: LookConfig
## Action bindings (keys / joypad buttons / axis-switches). Applied onto the
## InputMap at ready and after every change/load/defaults.
@export var input_bindings: InputBindings

@onready var _telemetry: Label = $Panel/VBox/TelemetryText
@onready var _motors_box: VBoxContainer = $Panel/VBox/Motors
@onready var _tuning: VBoxContainer = $Panel/VBox/Scroll/Tuning

var _configs: Array[TunableConfig] = []
var _motor_bars: Array[ProgressBar] = []
## One callable per generated control; re-reads the config after load/reset.
var _refreshers: Array[Callable] = []
## Row target for the section being built: each collapsible section header
## swaps this to its own body container.
var _section: VBoxContainer
## Non-empty while the BINDINGS section is listening for the next input.
var _capture_action: StringName = &""
## device -> axis values at capture start (rest positions for switch capture).
var _capture_rest: Dictionary = {}

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
	["iterm_relax_hz", 0.0, 50.0, 1.0],
	["iterm_relax_threshold_deg", 5.0, 200.0, 5.0],
	["ff_lpf_hz", 0.0, 120.0, 1.0],
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
	["rate_ff", 0.0, 0.003, 0.00005],
]

const _COMBAT_FLOAT_ROWS: Array[Array] = [
	["fire_rate", 1.0, 30.0, 0.5],
	["muzzle_speed", 20.0, 200.0, 5.0],
	["projectile_damage", 1.0, 100.0, 1.0],
	["projectile_lifetime", 0.5, 8.0, 0.1],
	["projectile_gravity_scale", 0.0, 1.0, 0.05],
	["inherit_velocity", 0.0, 1.0, 0.05],
	["fire_assist_miss_m", 0.0, 5.0, 0.1],
	["fire_assist_range", 10.0, 150.0, 5.0],
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
	["missile_auto_hold_s", 0.0, 3.0, 0.05],
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

const _LOOK_FLOAT_ROWS: Array[Array] = [
	["exposure", 0.2, 3.0, 0.05],
	["glow_intensity", 0.0, 2.0, 0.05],
	["glow_strength", 0.0, 2.0, 0.05],
	["glow_bloom", 0.0, 1.0, 0.01],
	["glow_hdr_threshold", 0.0, 4.0, 0.05],
	["ssao_intensity", 0.0, 8.0, 0.1],
	["ssao_radius", 0.1, 4.0, 0.1],
	["fog_density", 0.0, 0.1, 0.001],
	["fog_aerial_perspective", 0.0, 1.0, 0.05],
	["fog_sky_affect", 0.0, 1.0, 0.05],
	["brightness", 0.5, 2.0, 0.01],
	["contrast", 0.5, 2.0, 0.01],
	["saturation", 0.0, 2.0, 0.01],
	["ambient_energy", 0.0, 4.0, 0.05],
	["sun_energy", 0.0, 4.0, 0.05],
	["sun_pitch_deg", 5.0, 85.0, 1.0],
	["sun_yaw_deg", -180.0, 180.0, 5.0],
]


func _ready() -> void:
	_configs = [drone.config, combat_config, audio_config]
	if look_config != null:
		_configs.append(look_config)
	_section = _tuning
	_build_motor_bars()
	_add_section_header("FLIGHT", true)
	_add_preset_bar("flight", drone.config)
	var preset_updater: Callable = _add_preset_row(drone.config)
	_add_input_profile_row(drone.config)
	_add_throttle_curve_row(drone.config)
	_add_config_rows(drone.config, _FLIGHT_FLOAT_ROWS, _FLIGHT_VECTOR_ROWS, preset_updater)
	_add_section_header("COMBAT")
	_add_preset_bar("combat", combat_config)
	_add_config_rows(combat_config, _COMBAT_FLOAT_ROWS, [])
	_add_section_header("AUDIO")
	_add_preset_bar("audio", audio_config)
	_add_config_rows(audio_config, _AUDIO_FLOAT_ROWS, [])
	if input_bindings != null:
		_configs.append(input_bindings)
		if input_bindings.load_from_user():
			print("[config] loaded %s" % input_bindings.save_path())
		input_bindings.apply()
		_add_section_header("BINDINGS")
		_add_preset_bar("bindings", input_bindings)
		_build_bindings_section()
	if look_config != null:
		_add_section_header("LOOK")
		_add_preset_bar("look", look_config)
		_add_config_rows(look_config, _LOOK_FLOAT_ROWS, [])
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


## Collapsible section: the header is a toggle button, the body is a VBox
## that subsequent rows land in (via _section). FLIGHT starts expanded, the
## rest collapsed — the menu reads as a compact list of groups.
func _add_section_header(title: String, start_expanded: bool = false) -> void:
	_tuning.add_child(HSeparator.new())
	var header := Button.new()
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var body := VBoxContainer.new()
	body.visible = start_expanded
	header.text = ("▼  %s" if start_expanded else "▶  %s") % title
	header.pressed.connect(func() -> void:
		body.visible = not body.visible
		header.text = ("▼  %s" if body.visible else "▶  %s") % title)
	_tuning.add_child(header)
	_tuning.add_child(body)
	_section = body


## Named per-group presets under user://presets/<kind>/ — save this group's
## current values under a name, recall or delete them any time. Loading
## touches only this group's config; the bottom Save/Load/Defaults buttons
## keep their global everything-at-once role.
func _add_preset_bar(kind: String, config: TunableConfig) -> void:
	var dir_path: String = "user://presets/%s" % kind
	var row := HBoxContainer.new()
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.custom_minimum_size.x = 120.0
	var refresh_list := func() -> void:
		option.clear()
		option.add_item("(preset)")
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir != null:
			for file: String in dir.get_files():
				if file.ends_with(".tres"):
					option.add_item(file.get_basename())
	var load_button := Button.new()
	load_button.text = "load"
	load_button.focus_mode = Control.FOCUS_NONE
	load_button.pressed.connect(func() -> void:
		if option.selected <= 0:
			return
		var path: String = "%s/%s.tres" % [dir_path, option.get_item_text(option.selected)]
		var loaded: TunableConfig = ResourceLoader.load(path, "",
				ResourceLoader.CACHE_MODE_IGNORE) as TunableConfig
		if loaded != null:
			config.copy_from(loaded)
			_refresh_all()
			print("[preset] %s <- %s" % [kind, path]))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "name"
	name_edit.custom_minimum_size.x = 84.0
	var save_button := Button.new()
	save_button.text = "save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(func() -> void:
		var preset_name: String = name_edit.text.validate_filename().strip_edges()
		if preset_name.is_empty():
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		var path: String = "%s/%s.tres" % [dir_path, preset_name]
		var err: Error = ResourceSaver.save(config, path)
		print("[preset] %s -> %s: %s" % [kind, path,
				"OK" if err == OK else error_string(err)])
		name_edit.text = ""
		name_edit.release_focus()
		refresh_list.call())
	var delete_button := Button.new()
	delete_button.text = "del"
	delete_button.focus_mode = Control.FOCUS_NONE
	delete_button.pressed.connect(func() -> void:
		if option.selected <= 0:
			return
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
				"%s/%s.tres" % [dir_path, option.get_item_text(option.selected)]))
		refresh_list.call())
	refresh_list.call()
	row.add_child(option)
	row.add_child(load_button)
	row.add_child(name_edit)
	row.add_child(save_button)
	row.add_child(delete_button)
	_section.add_child(row)


func _add_config_rows(config: TunableConfig, float_rows: Array[Array],
		vector_rows: Array[Array], on_change: Callable = Callable()) -> void:
	for spec: Array in float_rows:
		_add_slider(_section, str(spec[0]), spec[1], spec[2], spec[3],
				func() -> float: return config.get(str(spec[0])),
				func(v: float) -> void:
					config.set(str(spec[0]), v)
					if on_change.is_valid():
						on_change.call())
	for spec: Array in vector_rows:
		var header := Label.new()
		header.text = str(spec[0])
		_section.add_child(header)
		for axis: int in 3:
			_add_slider(_section, "  " + _AXIS_NAMES[axis], spec[1], spec[2], spec[3],
					func() -> float:
						var vec: Vector3 = config.get(str(spec[0]))
						return vec[axis],
					func(v: float) -> void:
						var vec: Vector3 = config.get(str(spec[0]))
						vec[axis] = v
						config.set(str(spec[0]), vec)
						if on_change.is_valid():
							on_change.call())


## Rate-preset selector: applying one is an atomic swap of the five rate-
## loop fields; hand-tuning any of them afterward falls through to "Custom"
## (detected live, not tracked — see FlightPresets.active_name). Returns
## the refresh callable so the caller can also fire it after any flight
## slider changes, keeping the dropdown honest without extra wiring.
func _add_preset_row(config: FlightConfig) -> Callable:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "rate_preset"
	label.custom_minimum_size.x = 180.0
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	for preset: Dictionary in FlightPresets.POOL:
		option.add_item(preset["name"])
	var custom_index: int = option.item_count
	option.add_item("Custom")
	var updater := func() -> void:
		var active: String = FlightPresets.active_name(config)
		for i: int in FlightPresets.POOL.size():
			if FlightPresets.POOL[i]["name"] == active:
				option.select(i)
				return
		option.select(custom_index)
	option.item_selected.connect(func(index: int) -> void:
		if index < FlightPresets.POOL.size():
			FlightPresets.apply(FlightPresets.POOL[index], config)
			_refresh_all()
		else:
			# "Custom" has no values of its own — picking it by hand is a
			# no-op; just restore whichever state is actually live.
			updater.call())
	_refreshers.append(updater)
	updater.call()
	row.add_child(label)
	row.add_child(option)
	_section.add_child(row)
	return updater


## One row per bindable action: name, current bindings, capture ("bind" adds
## the next key/button/switch-flip) and clear. Axis capture compares against
## a rest snapshot so switches parked at an extreme still register cleanly.
func _build_bindings_section() -> void:
	# Re-apply bindings whenever configs are reloaded/reset from the buttons.
	_refreshers.append(func() -> void: input_bindings.apply())
	for action: StringName in InputBindings.ACTIONS:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(action)
		name_label.custom_minimum_size.x = 180.0
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 150.0
		var bind_button := Button.new()
		bind_button.text = "bind"
		bind_button.focus_mode = Control.FOCUS_NONE
		var clear_button := Button.new()
		clear_button.text = "x"
		clear_button.focus_mode = Control.FOCUS_NONE
		var refresh := func() -> void:
			value_label.text = input_bindings.describe(action)
		bind_button.pressed.connect(func() -> void:
			_start_capture(action)
			value_label.text = "press key / flip switch… (Esc)")
		clear_button.pressed.connect(func() -> void:
			input_bindings.clear_action(action)
			refresh.call())
		_refreshers.append(refresh)
		refresh.call()
		row.add_child(name_label)
		row.add_child(value_label)
		row.add_child(bind_button)
		row.add_child(clear_button)
		_section.add_child(row)


func _start_capture(action: StringName) -> void:
	_capture_action = action
	_capture_rest.clear()
	for device: int in Input.get_connected_joypads():
		var axes := PackedFloat32Array()
		for axis: int in JOY_AXIS_MAX:
			axes.append(Input.get_joy_axis(device, axis as JoyAxis))
		_capture_rest[device] = axes


func _input(event: InputEvent) -> void:
	if _capture_action == &"":
		return
	if not visible:
		_capture_action = &""
		return
	var binding: Dictionary = {}
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_ESCAPE:
			_capture_action = &""
			_refresh_all()
			get_viewport().set_input_as_handled()
			return
		binding = InputBindings.make_key(event.physical_keycode)
	elif event is InputEventJoypadButton and event.pressed:
		binding = InputBindings.make_button(event.button_index)
	elif event is InputEventJoypadMotion:
		# A real actuation is a big move away from where the axis rested when
		# capture began — jitter and parked-at-extreme axes don't trigger.
		var rest: float = 0.0
		var rest_axes: PackedFloat32Array = _capture_rest.get(event.device,
				PackedFloat32Array())
		if event.axis < rest_axes.size():
			rest = rest_axes[event.axis]
		if absf(event.axis_value - rest) > 0.75:
			binding = InputBindings.make_axis(event.axis, signf(event.axis_value))
	if not binding.is_empty():
		input_bindings.add_binding(_capture_action, binding)
		_capture_action = &""
		_refresh_all()
	get_viewport().set_input_as_handled()


func _add_input_profile_row(config: FlightConfig) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "input_profile"
	label.custom_minimum_size.x = 180.0
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	for profile_name: String in FlightConfig.InputProfile.keys():
		option.add_item(profile_name.to_lower())
	option.selected = config.input_profile
	option.item_selected.connect(func(index: int) -> void:
		config.input_profile = index as FlightConfig.InputProfile)
	_refreshers.append(func() -> void: option.selected = config.input_profile)
	row.add_child(label)
	row.add_child(option)
	_section.add_child(row)


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
	_section.add_child(row)


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
