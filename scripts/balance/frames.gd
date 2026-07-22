class_name Frames
extends RefCounted

## The measured frame roster, and the one way a bench builds a drone
## (GAMEPLAY-DESIGN P3.4/P3.7: frame x enemy is the harness's second axis).
##
## Every bench goes through `build()` rather than instantiating drone.tscn
## itself, for two reasons that are easy to get wrong once per file:
##
##  1. The frame must be assigned BEFORE the node enters the tree, because
##     FlightController._ready resolves the flight model, the mass and the hull
##     from it. Set it after add_child and you have measured a Kestrel wearing
##     the Atlas's name.
##  2. User overrides must be OFF. The benches used to inherit whatever the
##     human had tuned into user://flight_config.tres, which made every
##     committed delivery factor a measurement of one machine (see
##     FlightController.load_user_overrides).
##
## THE KESTREL IS THE DATUM, not merely the first entry: P3.3 defines its P4.4
## column as all zeros on purpose ("the frame you fly when intel is stale"), so
## the frame axis bands every other frame as a DELTA against it. That makes the
## design's own statement the ruler's origin instead of an extra assumption.

const KESTREL: String = "kestrel"
const ATLAS: String = "atlas"

## The slice's two frames (P3.10). Dart and Shade join when falx and the intel
## war arrive to justify them.
const ROSTER: Array[String] = [KESTREL, ATLAS]


static func config(frame_id: String) -> FrameConfig:
	return load("res://resources/default_frame_%s.tres" % frame_id) as FrameConfig


## An un-parented drone on `frame_id`. The caller adds it to the tree.
static func build(frame_id: String) -> FlightController:
	var drone: FlightController = (load("res://scenes/drone/drone.tscn")
			as PackedScene).instantiate() as FlightController
	drone.frame = config(frame_id)
	drone.load_user_overrides = false
	return drone


## Every frame's stat block, for the delivery stamp. Loaded from the roster so a
## new frame joins the stamp the day it lands (the v1.27 rule).
static func all_configs() -> Array[FrameConfig]:
	var configs: Array[FrameConfig] = []
	for frame_id: String in ROSTER:
		configs.append(config(frame_id))
	return configs
