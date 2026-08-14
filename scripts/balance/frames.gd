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
## THE SIZE LADDER (GAMEPLAY-DESIGN V10), and it is a different axis from the
## Kestrel/Atlas one. Those two differ in hull, mass and rates at ONE size; these
## differ in SIZE at one hull — 0.28 m, 1.2 m, 3.0 m — which is what makes them
## worth flying back to back in the scale yard.
const CONDOR: String = "condor"
const ROC: String = "roc"
## THE REDUNDANCY EXPERIMENT (E.q1), and a THIRD axis again: the Kestrel in every
## respect except that it carries six rotors instead of four. Held identical on
## purpose — a hexa that also changed mass, TWR or rates would be an interesting
## aircraft and a useless experiment, because nothing it did could be attributed
## to the layout.
const HEXA: String = "hexa"

## The slice's frames (P3.10). Dart and Shade join when falx and the intel war
## arrive to justify them.
##
## THE TWO NEW FRAMES ARE IN THE ROSTER ON PURPOSE, and it costs something worth
## naming: `all_configs()` feeds the delivery stamp, so adding them changes it and
## the committed delivery factors stop being considered current. That is the
## correct outcome — the roster genuinely moved — and it is this file's own stated
## rule (*"a new frame joins the stamp the day it lands"*). It also puts them in
## front of `hover_check`, which flies every roster entry, so a size ladder that
## cannot hold a hover fails the board rather than surprising a pilot.
##
## They are deliberately NOT in `Hangar.FRAMES` or the menu tower's leaf list:
## those are the CAMPAIGN's frames, and an experimental airframe on a branch has
## no business in the game's front door — which at 3 m it could not fly through
## anyway (V.q6).
const ROSTER: Array[String] = [KESTREL, ATLAS, CONDOR, ROC, HEXA]


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
