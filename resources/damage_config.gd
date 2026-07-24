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
## The video transmitter is EQUIPMENT with its own health (v1.41/v1.42, the
## user's model): each hit chips it alongside the motors — severity scales
## the CHIPPING, exactly as it scales motor damage — and the field patch
## (pads / gate / respawn) heals it with the rest of the airframe. This is
## the transmitter health lost per unit of relative hit size (hit / max
## hull), before severity. At 3.0 and severity 0.6, a raider bolt on a
## Kestrel costs ~14% of the transmitter.
@export var video_damage_scale: float = 3.0
## The two knobs below define how NOTICEABLE the effect is globally; the
## transmitter's health is the knob over the knobs — every one of them is
## multiplied by how wrecked the equipment is.
## Permanent breakup floor at a fully wrecked transmitter.
@export var video_glitch_sustained: float = 0.45
## Random breakup bursts between hits, per second, at a fully wrecked
## transmitter: a scratched feed stutters, a wrecked feed crackles.
@export var video_flicker_rate: float = 3.0
## Burst strength at a fully wrecked transmitter (with per-burst
## randomness); bursts decay through video_glitch_decay.
@export var video_flicker_strength: float = 0.6


const SAVE_PATH: String = "user://damage_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_damage_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
