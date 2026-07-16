class_name InputBindings
extends TunableConfig

## Configurable action bindings — keyboard keys, joypad buttons, and joypad
## AXES acting as switches/triggers — persisted like every other config.
## apply() rewrites the InputMap at runtime, so gameplay code keeps calling
## Input.is_action_* untouched. The axis kind is what makes radio switches
## bindable: EdgeTX/OpenTX joystick mode delivers switches as axes snapping
## between -1 and +1, and Godot natively treats an axis-with-direction event
## as a pressable action (deadzone 0.5).

## Bindable actions, in overlay display order. arm_switch is FPV-style
## stateful arming (switch position = armed state) as opposed to the
## momentary arm_toggle; it ships unbound.
const ACTIONS: Array[StringName] = [
	&"arm_toggle", &"arm_switch", &"reset_drone", &"flight_mode_toggle",
	&"camera_toggle", &"fire", &"fire_missile", &"overlay_toggle",
]

enum Kind { KEY, JOY_BUTTON, JOY_AXIS }

## action name (String) -> Array of {"kind": int, "code": int, "sign": float}.
## sign is the trigger direction for JOY_AXIS bindings, unused otherwise.
@export var bindings: Dictionary = {}


func _init() -> void:
	bindings = factory_defaults()


## Defaults mirror the project.godot gamepad layout and add keyboard
## fallbacks, so a radio-only desk can still do everything.
static func factory_defaults() -> Dictionary:
	return {
		"arm_toggle": [make_key(KEY_ENTER), make_button(JOY_BUTTON_A)],
		"arm_switch": [],
		"reset_drone": [make_key(KEY_R), make_button(JOY_BUTTON_B)],
		"flight_mode_toggle": [make_key(KEY_M), make_button(JOY_BUTTON_Y)],
		"camera_toggle": [make_key(KEY_C), make_button(JOY_BUTTON_X)],
		"fire": [make_key(KEY_SPACE), make_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"fire_missile": [make_key(KEY_F), make_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"overlay_toggle": [make_key(KEY_TAB), make_button(JOY_BUTTON_START)],
	}


static func make_key(code: int) -> Dictionary:
	return {"kind": Kind.KEY, "code": code, "sign": 1.0}


static func make_button(code: int) -> Dictionary:
	return {"kind": Kind.JOY_BUTTON, "code": code, "sign": 1.0}


static func make_axis(code: int, sign: float) -> Dictionary:
	return {"kind": Kind.JOY_AXIS, "code": code, "sign": signf(sign)}


## Rewrites the live InputMap from the stored bindings. Actions missing from
## the project (e.g. arm_switch) are created on the fly.
func apply() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		InputMap.action_erase_events(action)
		for binding: Dictionary in bindings.get(String(action), []):
			InputMap.action_add_event(action, _to_event(binding))


func add_binding(action: StringName, binding: Dictionary) -> void:
	var list: Array = bindings.get(String(action), [])
	if not list.has(binding):
		list.append(binding)
	bindings[String(action)] = list
	apply()


func clear_action(action: StringName) -> void:
	bindings[String(action)] = []
	apply()


## Short human-readable summary for the overlay row.
func describe(action: StringName) -> String:
	var parts: PackedStringArray = []
	for binding: Dictionary in bindings.get(String(action), []):
		match int(binding.get("kind", Kind.KEY)):
			Kind.JOY_BUTTON:
				parts.append("btn%d" % int(binding.get("code", 0)))
			Kind.JOY_AXIS:
				parts.append("ax%d%s" % [int(binding.get("code", 0)),
						"+" if float(binding.get("sign", 1.0)) > 0.0 else "-"])
			_:
				parts.append(OS.get_keycode_string(int(binding.get("code", 0)) as Key))
	return " | ".join(parts) if parts.size() > 0 else "(unbound)"


static func _to_event(binding: Dictionary) -> InputEvent:
	match int(binding.get("kind", Kind.KEY)):
		Kind.JOY_BUTTON:
			var button := InputEventJoypadButton.new()
			button.button_index = int(binding.get("code", 0)) as JoyButton
			return button
		Kind.JOY_AXIS:
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(binding.get("code", 0)) as JoyAxis
			motion.axis_value = signf(float(binding.get("sign", 1.0)))
			return motion
		_:
			var key := InputEventKey.new()
			key.physical_keycode = int(binding.get("code", 0)) as Key
			return key


const SAVE_PATH: String = "user://input_bindings.tres"
const DEFAULTS_PATH: String = "res://resources/default_input_bindings.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
