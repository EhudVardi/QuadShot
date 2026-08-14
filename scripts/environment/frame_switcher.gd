class_name FrameSwitcher
extends Node

## Swap airframe on the pad, mid-session, with a number key (GAMEPLAY-DESIGN
## V10). Built for the scale yard and useful in any test map.
##
## THE WHOLE VALUE IS THAT THE WORLD DOES NOT CHANGE BETWEEN THE TWO FLIGHTS.
## The user's own reasoning: *"being able to fly them both IN THE SAME EXACT ENV'
## will absolutely give me the sense of scale, especially when i'll fly our
## original small kestrel and the world should feel x10 larger, like i morphing
## from a hawk into a honeybird."* Two scene loads with a menu in between would
## measure the pilot's memory instead of the two airframes.
##
## A DEV AFFORDANCE, not the shipped picker — P3.8's briefing chain and the war
## room's hangar are where choosing an airframe belongs. This is the same
## exemption `--frame` already has, for the same reason: the human's hands are
## the only test of feel that counts, and they need the frame in front of them
## today.
##
## RAW KEYCODES rather than InputMap actions, deliberately. Every action here
## would have to be added to `InputBindings` and would then exist in the arena,
## the menu tower and the campaign, where nothing should be able to change
## airframe by leaning on a keyboard. The cost is that these keys are not
## rebindable, which for a dev map is the right trade.

## Number keys 1..N select the frame at that index.
const FIRST_KEY: Key = KEY_1

@export var drone: FlightController
## Frame ids, in key order. Left as ids rather than FrameConfigs so the scene
## file reads as a list of names.
@export var frame_ids: PackedStringArray = PackedStringArray(
		["kestrel", "condor", "roc"])
## Optional: told about every swap, so the pilot gets a line on screen rather
## than only in the console.
@export var hud: GameHud


func _unhandled_input(event: InputEvent) -> void:
	if drone == null or not (event is InputEventKey) or not event.is_pressed() \
			or event.is_echo():
		return
	var index: int = (event as InputEventKey).keycode - FIRST_KEY
	if index < 0 or index >= frame_ids.size():
		return
	_select(index)
	get_viewport().set_input_as_handled()


func _select(index: int) -> void:
	var config: FrameConfig = Frames.config(frame_ids[index])
	if config == null:
		push_error("[frames] no frame '%s'" % frame_ids[index])
		return
	if config.frame_id == drone.frame.frame_id:
		return
	drone.swap_frame(config)
	# Back to the pad, always. A swap that left the new airframe wherever the old
	# one happened to be would compare two different flights, and half the point
	# of the ladder is that both start from the same 16 m square.
	drone.reset_to_spawn()
	var flight: FlightConfig = config.flight_config
	var line: String = "%s — %.2f m, %.0f kg, TWR %.0f" % [config.display_name,
			flight.body_m, flight.mass, flight.thrust_to_weight_ratio]
	print("[frames] %s" % line)
	if hud != null:
		hud.add_kill_feed(line)
