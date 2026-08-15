class_name FrameConfig
extends TunableConfig

## Per-airframe stat block (GAMEPLAY-DESIGN P3.9): one .tres per frame in the
## P3.3 roster. This is the config that was missing while the game had exactly
## one drone — the player's hull lived on CombatConfig and the airframe's mass
## lived on a FlightConfig nobody owned, so "which frame am I flying" was not a
## question the code could ask.
##
## Like EnemyConfig (and unlike every other config here) this class has MANY
## instances, so its save and defaults paths derive from `frame_id` rather than
## being class constants: kestrel -> user://frame_kestrel.tres.
##
## **A frame IS its FlightConfig** (P3.9, from P3 v1). The whole overlay FLIGHT
## section, the preset ladder and the tuning loop therefore work per-frame with
## no new machinery — the frame just hands out a different `.tres`.
##
## Deliberately NOT here yet, though P3.9 lists them:
##  - `mass`. It is already a FlightConfig field, and the motor model reads it
##    from there every tick. Mirroring it would give one physics number two
##    homes and no rule for which wins.
##  - The hardpoint block (slot list, mass budget) and the signature block.
##    Nothing reads them until P3.8's loadout loop and the sensor model land,
##    and this project does not ship dead tunables (FlightConfig's own header
##    rule). They arrive with the systems that consume them.

@export_group("Identity")
## Slug used for the save/defaults paths and the overlay label. Must match the
## `frame_id` of `flight_config` — see `flight_config_matches()`.
@export var frame_id: StringName = &"kestrel"
## Human-readable name (P3.3 gives frames proper names, weapons functional ones).
@export var display_name: String = "Kestrel"

@export_group("Airframe")
## This frame's flight model. Swapping frames is swapping this resource.
@export var flight_config: FlightConfig

@export_group("Durability")
## Hit points. Moved off CombatConfig.player_max_health, which described "the
## player" back when there was only one airframe to be.
@export var hull: float = 100.0
## Flat damage subtracted from every hit that reaches the hull (P4.1's "armored"
## grammar, applied to the player's side). The Atlas is the one frame in the P3.3
## roster that carries any; 0 for everyone else.
@export var armor: float = 0.0
## PLATING OVER NAMED COMPONENTS (GAMEPLAY-DESIGN Iteration 17 / E4.2), keyed by
## the component kind in `AirframeComponents.TABLE` — `{&"rotor": 0.04}` and so
## on. Absent kinds carry nothing.
##
## E4.2's whole argument is that this is NOT a flat pool: *"A 500 kg airframe can
## carry plating over its power bus and its gyro; a 650 g quad carries nothing.
## Armour that protects a NAMED thing is legible in a way a hull number never is
## — 'they got my power bus through the plating' is a sentence a pilot can learn
## from."*
##
## The value is a FLAT reduction in the capability a single hit can strip from
## that component, in the same 0-to-1 units the component's health uses, and the
## flatness is deliberate — the same grammar `armor` above already uses. It is
## worth most against many small hits and least against few big ones, so plating
## answers chip fire and does nothing about a missile, which is the character the
## stat should have.
##
## **EMPTY ON EVERY SHIPPED FRAME**, so this field changes nothing until values
## are authored. E.q7 governs how they get authored when they are: armour follows
## from a frame's VALUE and its EXPOSURE — *"say the Roc is heavy AND powerful, so
## i would equip it with medium armor, because it may be more expensive so i
## would protect it more"* — and never from a ratio against another frame.
@export var component_armor: Dictionary = {}
## WHAT A UNIT OF PLATING WEIGHS, in kg per square metre of plate per unit of
## `component_armor` (GAMEPLAY-DESIGN Iteration 17 / E.q7, the human's own model):
##
##   *"since we agreed that armor is simply something that reduces damage taken,
##   we can say its equivalent to the thickness of the shell. so the mass is
##   roughly thickness times the shell plan area."*
##
## So an armour value IS a plate thickness, and plate mass is `density x thickness
## x area`. Density and thickness only ever appear multiplied together and neither
## is separately measurable from anything in this game, so they are ONE number
## here rather than two that would invite tuning against each other.
##
## THE ANCHOR, so the number is not arbitrary: armour 1.0 means no hit can ever
## damage that component, which is "immune to anything the bestiary fires" — call
## that 50 mm of steel. 7850 kg/m3 x 0.05 m = 392.5 kg/m2 per unit of armour, and
## the Roc's 0.024 is then a 1.2 mm plate. Halving or doubling the anchor moves
## every mass below by the same factor and changes none of the conclusions, which
## is worth knowing before anyone tunes it.
##
## IT IS PER FRAME because plate material is an airframe decision — a stealth
## frame would plausibly buy composite and pay less per unit — but nothing on the
## roster differs today, and a frame that wanted to differ would say so here.
@export var plate_areal_density: float = 392.5

## Break, settle, fire, break — the PILOT_VERSION 5 tactical jink. Dodge while
## under fire, hold the line while the gun is on the target.
const STYLE_JINK: StringName = &"jink"
## Hold the line and eat it. The heavy frame's answer: its survival comes from
## hull and armor, not from throwing 1.9x the mass around on softer rates.
const STYLE_HOLD: StringName = &"hold"
const EVASION_STYLES: Array[StringName] = [STYLE_JINK, STYLE_HOLD]

@export_group("Evasion")
## HOW THIS AIRFRAME DODGES — a roster identity trait (P3.3), not a tuning knob.
##
## Measured, not assumed (v1.81, three cells per frame in one run): the tactical
## jink beats both extremes for the Kestrel on BOTH axes at once — fewest rounds
## taken and the most shots at the best accuracy. For the Atlas it does neither:
## the same rounds land whether it dodges or not (0.11 either way) while its gun
## falls from 0.11-0.17 to 0.03. **Dodging buys the heavy frame nothing and costs
## it nearly all of its output**, even at a 23% duty.
##
## The user's reading, which this field is: *"the atlas, and any heavy moving
## frame cannot use jink as an evading means. maybe it should not even try."* So
## evasion style stops being one behaviour for every airframe and becomes part of
## what a frame IS — the same move P3.9 already made for the flight model.
##
## WHO READS IT: `ReferencePilot`, the measuring brain (BALANCE.md's pinned
## ruler), and any future AI that flies a player frame. It is deliberately NOT in
## the overlay: the human's evasion is the human's hands, and a slider that moved
## nothing under a human pilot would be a dead tunable (FlightConfig's own rule).
@export var evasion_style: StringName = STYLE_JINK


## Does this airframe dodge at all? One place asks the question, so an unknown
## style reads as "does not dodge" rather than as whatever a string comparison
## happened to do at the call site.
func jinks() -> bool:
	return evasion_style == STYLE_JINK


## FrameConfig is the third many-instance config and was the only one that never
## declared its identity, which was survivable while `kestrel` and `atlas` were
## the whole roster and nothing swapped frames at runtime. The size ladder (V10)
## makes it reachable: save a FRAME preset on the Roc, load it onto the Kestrel,
## and `copy_from` renames the Kestrel to `roc` — which then saves its tuning over
## `user://frame_roc.tres`. Exactly the failure the FlightConfig and EnemyConfig
## versions of this function already prevent.
func identity_fields() -> PackedStringArray:
	return PackedStringArray(["frame_id", "display_name"])


func save_path() -> String:
	return "user://frame_%s.tres" % frame_id


func defaults_path() -> String:
	return "res://resources/default_frame_%s.tres" % frame_id


## The two resources carry the same id and must agree, or the frame would save
## its flight tuning under another frame's name. Cheap to check, and the failure
## it catches (a copy-pasted .tres for a new frame) is silent otherwise.
func flight_config_matches() -> bool:
	return flight_config != null and flight_config.frame_id == frame_id
