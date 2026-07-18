class_name DamageConfig
extends TunableConfig

## The damage model's tunables (GAMEPLAY-DESIGN Iteration 7 / D8): live-editable
## in the overlay's DAMAGE section like every other config. Damage is a
## flight-model event, not only a health-bar event (D1) — these knobs decide how
## a hit degrades the WAY the quad flies, and the severity dial (D3) ramps the
## whole thing from arcade (integrity only) to sim (the wounded quad).

@export_group("Severity")
## Master arcade<->sim dial: 0 = a hit only drains integrity (today's model,
## the newbie floor); 1 = full subsystem degradation (flying the wounded quad).
## Scales every subsystem effect below. The combat twin of the rate-preset
## ladder (D3) — sim-leaning default, generous arcade floor, never a wall.
@export var severity: float = 0.6

@export_group("Motors")
## Motor capability lost per point of integrity damage, before severity. A
## raider bolt (~8) at severity 0.6 strips ~0.05 capability; heavier hits bite
## deeper. Hit LOCATION picks which motor takes it (D2) — asymmetric thrust the
## rate loop must fight, felt through the sticks.
@export var motor_damage_scale: float = 0.010
## Cap on capability a single hit can strip — one bolt frays a motor, it never
## kills one outright (burst-knockout is a later refinement, D6).
@export var motor_damage_max: float = 0.5
## Residual thrust a fully-failed motor still produces (D2 / Dq2): above zero
## keeps a motor-out flyable-but-punishing; drive toward 0 for lethal realism.
## 0.30 = a dead corner still pulls its weight enough to fight home to a pad.
@export var motor_min_thrust: float = 0.30
## How much of a CRASH's (directionless) damage each motor takes. Crashes fray
## all four at once, so this is kept low — a rough landing must not spiral all
## engines to nothing; the repair pad is the recovery, this is the price.
@export var crash_motor_scale: float = 0.4

@export_group("Video")
## FPV feed breakup punched in on each hit (scaled by hit size and severity),
## which then decays fast — the abrupt, sudden telegraph (D4 / Dq4).
@export var video_glitch_on_hit: float = 0.85
## Per-second decay of the on-hit glitch spike — high, so it snaps then clears.
@export var video_glitch_decay: float = 2.8
## Sustained breakup floor as integrity falls (scaled by damage and severity):
## a badly hurt feed stays noisy. Kept modest — the wound informs, never blinds.
@export var video_glitch_sustained: float = 0.45


const SAVE_PATH: String = "user://damage_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_damage_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
