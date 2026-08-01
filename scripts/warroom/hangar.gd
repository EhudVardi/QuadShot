class_name Hangar
extends RefCounted

## THE HANGAR (GAMEPLAY-DESIGN Iteration 13, C9 phase 5 — P1.8's "pilot roster
## and hangar"). Which airframe you take, chosen next to the intel that should
## decide it.
##
## This is the smallest honest version of P3: frames exist, they differ in hull,
## armor and mass, and the war room is where you pick one. Loadouts, hardpoints
## and the salvage economy are P3/P5 and are deliberately absent — the room will
## have obvious places to put them and must not grow them speculatively (C10).
##
## THE PICK RIDES `MenuLaunch.frame_id`, the same static the menu tower's frame
## tower already writes and `FlightController` already reads. A second mechanism
## for "which frame am I flying" is exactly the kind of duplicate the falx and
## the screamer taught this project about (v1.96): two lists that can disagree,
## in a spot no test looks at. `war_room_check` asserts this list against the
## tower's so they cannot drift apart.

## The frames the campaign can field. Hand-listed, like the menu tower's, and
## checked against it rather than trusted.
const FRAMES: Array[StringName] = [&"kestrel", &"atlas"]

const FRAME_PATH: String = "res://resources/default_frame_%s.tres"


static func config_for(frame_id: StringName) -> FrameConfig:
	return load(FRAME_PATH % frame_id) as FrameConfig


## The frame currently selected, defaulting to the first rather than to nothing:
## a campaign screen offering "no airframe" is a screen with a bug in it.
static func selected() -> StringName:
	if MenuLaunch.frame_id == &"" or not MenuLaunch.frame_id in FRAMES:
		return FRAMES[0]
	return MenuLaunch.frame_id


static func select(frame_id: StringName) -> void:
	if frame_id in FRAMES:
		MenuLaunch.frame_id = frame_id


## Step through the hangar. One key cycling a short list beats a submenu for two
## entries, and it stays honest when there are five.
static func cycle() -> StringName:
	var index: int = FRAMES.find(selected())
	select(FRAMES[(index + 1) % FRAMES.size()])
	return selected()


## What the hangar panel shows. Numbers come from the COMMITTED defaults, not
## from `user://` overrides — the same rule BALANCE.md's third ruler applies to
## the manifest, and for the same reason: the campaign is priced in the numbers
## that ship.
static func lines() -> PackedStringArray:
	var frame_id: StringName = selected()
	var frame: FrameConfig = config_for(frame_id)
	if frame == null:
		return PackedStringArray(["HANGAR: %s is missing" % frame_id])
	var flight: FlightConfig = frame.flight_config
	var out: PackedStringArray = [
		"HANGAR   %s" % frame.display_name.to_upper(),
		"hull %.0f   armor %.0f%s" % [frame.hull, frame.armor,
				"   mass %.2f kg" % flight.mass if flight != null else ""],
		"evasion %s" % frame.evasion_style,
	]
	if FRAMES.size() > 1:
		out.append("F to change airframe")
	return out


## The pilot roster (F1). A count rather than named pilots (C.q7): a roster gets
## interesting when pilots accumulate history, and history is a save-shape change
## this iteration ruled out. Drawn as marks because five of something reads
## faster than the numeral 5, and because losing one should be visible.
static func roster_line(pilots: int) -> String:
	if pilots <= 0:
		return "ROSTER   none left"
	return "ROSTER   %s   (%d)" % ["|".repeat(pilots), pilots]
