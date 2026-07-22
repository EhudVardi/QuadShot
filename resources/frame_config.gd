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


func save_path() -> String:
	return "user://frame_%s.tres" % frame_id


func defaults_path() -> String:
	return "res://resources/default_frame_%s.tres" % frame_id


## The two resources carry the same id and must agree, or the frame would save
## its flight tuning under another frame's name. Cheap to check, and the failure
## it catches (a copy-pasted .tres for a new frame) is silent otherwise.
func flight_config_matches() -> bool:
	return flight_config != null and flight_config.frame_id == frame_id
