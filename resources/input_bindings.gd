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
	&"camera_toggle", &"fire", &"fire_missile", &"fire_flak",
	&"missile_auto_switch",
	&"pause_toggle", &"pause_switch", &"overlay_toggle",
]

## Always bound from the flight (resumed) set, in BOTH contexts — pausing
## must never lock the player out of unpausing or the overlay.
const SYSTEM_ACTIONS: Array[StringName] = [
	&"pause_toggle", &"pause_switch", &"overlay_toggle",
]

## Stateful (position = state) switch actions. After every apply() their
## pressed state is re-derived from the raw hardware: Godot's action state is
## event-driven, so a switch held through an InputMap rebuild would otherwise
## read as released — which disarmed the drone on unpause. Momentary actions
## are deliberately NOT synced (that would fabricate just-pressed edges).
const STATEFUL_ACTIONS: Array[StringName] = [
	&"arm_switch", &"pause_switch", &"missile_auto_switch",
]

enum Kind { KEY, JOY_BUTTON, JOY_AXIS }

## action name (String) -> Array of {"kind": int, "code": int, "sign": float}.
## sign is the trigger direction for JOY_AXIS bindings, unused otherwise.
@export var bindings: Dictionary = {}
## Second mapping set, active during pause (slow-mo). Gameplay actions are
## unbound here by default, so typing in overlay fields while paused can't
## fire weapons; the player may deliberately bind slow-mo controls.
@export var bindings_paused: Dictionary = {}

## Which context apply() writes onto the InputMap (runtime state, not saved).
var paused_context_active: bool = false


func _init() -> void:
	bindings = factory_defaults()
	bindings_paused = {}


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
		# Both triggers are already spoken for (gun/missile), so the flak pod
		# takes the right bumper — it is a held-down auto weapon, not a snap
		# shot, so a button suits it better than a trigger anyway.
		"fire_flak": [make_key(KEY_G), make_button(JOY_BUTTON_RIGHT_SHOULDER)],
		"missile_auto_switch": [],
		"pause_toggle": [make_key(KEY_P)],
		"pause_switch": [],
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
## Switches the live InputMap between the flight and paused mapping sets.
func apply_context(paused: bool) -> void:
	paused_context_active = paused
	apply()


func apply() -> void:
	# 2026-07-16 rename: saved configs may still carry the old action name.
	if bindings.has("missile_auto"):
		var old: Array = bindings["missile_auto"]
		if not old.is_empty() and (bindings.get("missile_auto_switch", []) as Array).is_empty():
			bindings["missile_auto_switch"] = old
		bindings.erase("missile_auto")
	_adopt_new_actions()
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		InputMap.action_erase_events(action)
		for binding: Dictionary in _set_for(action, paused_context_active).get(String(action), []):
			InputMap.action_add_event(action, _to_event(binding))
	_sync_stateful_actions()


## Actions added to ACTIONS *after* the player last saved their bindings have no
## key in the saved dictionary, and apply() erases the project.godot events
## before writing the saved ones — so without this a new action ships silently
## UNBOUND to everyone who ever pressed Save, while working perfectly on a clean
## machine. Caught when the flak pod's `fire_flak` landed (v1.28).
##
## Only ever fills in a MISSING key. An action the player deliberately cleared is
## stored as an empty array, which is present, so their choice survives.
func _adopt_new_actions() -> void:
	var factory: Dictionary = factory_defaults()
	for action: StringName in ACTIONS:
		var name: String = String(action)
		if not bindings.has(name) and factory.has(name):
			bindings[name] = (factory[name] as Array).duplicate(true)


## See STATEFUL_ACTIONS: reconcile Godot's event-driven action state with the
## physical switch positions after the InputMap was rebuilt.
func _sync_stateful_actions() -> void:
	for action: StringName in STATEFUL_ACTIONS:
		var pressed: bool = _raw_pressed(action)
		if pressed == Input.is_action_pressed(action):
			continue
		if pressed:
			Input.action_press(action)
		else:
			Input.action_release(action)


## The action's pressed state read directly from hardware, ignoring Godot's
## action-state cache.
func _raw_pressed(action: StringName) -> bool:
	for binding: Dictionary in _set_for(action, paused_context_active).get(String(action), []):
		match int(binding.get("kind", Kind.KEY)):
			Kind.JOY_BUTTON:
				for device: int in Input.get_connected_joypads():
					if Input.is_joy_button_pressed(device, int(binding.get("code", 0)) as JoyButton):
						return true
			Kind.JOY_AXIS:
				var sign: float = signf(float(binding.get("sign", 1.0)))
				for device: int in Input.get_connected_joypads():
					if sign * Input.get_joy_axis(device,
							int(binding.get("code", 0)) as JoyAxis) > 0.5:
						return true
			_:
				if Input.is_physical_key_pressed(int(binding.get("code", 0)) as Key):
					return true
	return false


## The dict an action reads from in the given context: system actions always
## use the flight set, everything else uses the context's set.
func _set_for(action: StringName, paused: bool) -> Dictionary:
	if paused and not SYSTEM_ACTIONS.has(action):
		return bindings_paused
	return bindings


func add_binding(action: StringName, binding: Dictionary, paused: bool = false) -> void:
	var target: Dictionary = _set_for(action, paused)
	var list: Array = target.get(String(action), [])
	if not list.has(binding):
		list.append(binding)
	target[String(action)] = list
	apply()


func clear_action(action: StringName, paused: bool = false) -> void:
	_set_for(action, paused)[String(action)] = []
	apply()


## Short human-readable summary for the overlay row.
func describe(action: StringName, paused: bool = false) -> String:
	var parts: PackedStringArray = []
	for binding: Dictionary in _set_for(action, paused).get(String(action), []):
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
