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
## STAYS AT 0.6, and the decision is now a considered one rather than a pending
## one. E.q8 named 1.0 as the design target — *"my choice is absolutely '1 = full
## subsystem damage'"* — and it was offered for baking on 2026-08-15 once the
## human had actually flown it. They declined: *"severity can stay in 0.6."*
##
## Worth recording because 1.0 remains what the model is AUTHORED against; what
## the game SHIPS at is a separate call, and this is it. Raising it is a
## roster-wide change rather than a damage-model one — every enemy gets
## meaningfully more dangerous at once, and every counter-web band was measured
## here — so the shipped value moving is a balance event, not a tuning tweak.
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
## How much of a CRASH's damage each motor takes. Crashes fray every rotor at
## once, so this is kept low — a rough landing must not spiral all engines to
## nothing; the repair pad is the recovery, this is the price.
## Baked 0.4 -> 0.8 on 2026-08-15, after the human flew it and found crashes
## barely marked the rotors: *"i had to push the motor damage scale to close to
## max and the severity as well, to really see damage with head on collision."*
##
## The measurement behind the number, at the SHIPPED severity of 0.6 — leading
## rotor health after a head-on, which is what the pilot sees on the pips:
##
##     speed     hull lost     at 0.4      at 0.8
##     15 m/s        11.9        0.96        0.92
##     20 m/s        37.8        0.88        0.76
##     25 m/s        71.0        0.77        0.54
##     28.7 m/s     100.3        0.68        0.35   <- a crash that KILLS you
##
## The bottom row is the argument. At 0.4 a crash violent enough to kill you left
## the leading rotor at two thirds health, which is why the whole mechanic read
## as weak however hard you hit something.
##
## THE KNOB THE HUMAN REACHED FOR FIRST WAS `motor_damage_scale`, AND THAT WOULD
## HAVE BEEN A TRAP: it is shared with bullets, so five times the crash bite is
## also five times the bite of every enemy bolt in the game. This one is
## crash-only, which is why the tuning belongs here.
@export var crash_motor_scale: float = 0.8
## HOW LOPSIDED A CRASH IS. 0 = every rotor takes exactly the same (the model as
## it shipped until 2026-08-15); 1 = only the rotors that led the impact take
## anything at all.
##
## It exists because the even version was measured to be FREE. A crash and a
## bullet of the same size both took a real bite out of the rotors, but the crash
## spread it perfectly evenly — and a multirotor does not care about a symmetric
## loss, it just needs a little more throttle. Flown on the position-hold
## autopilot: a bullet produced 2.32 m/s of drift and 27.63 degrees of tilt, and
## the identical damage as a crash produced **0.00 and 0.00**. The user flew it
## and said so before the bench did: *"the props got damaged but way less, the
## quad is still absolutely flyable... taking damage from being shot makes the
## quad way WAY worse to fly."*
##
## THE WEIGHTS ARE NORMALISED so the MEAN is unchanged. Asymmetry redistributes a
## crash across the airframe, it does not make one bigger or smaller — which
## keeps this knob independent of `crash_motor_scale` and keeps E6's calibration
## intact. Every rotor still takes something at any value below 1, because a
## crash loading the WHOLE frame is E6's actual content.
@export var crash_asymmetry: float = 0.6

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
## Baked 3.0 -> 1.0 on 2026-08-15, on the human's call: *"i think it should be
## somewhere at 1.0."*
##
## At 3.0 the transmitter was the most fragile thing on the airframe by a wide
## margin — a hit worth a third of the hull destroyed it OUTRIGHT, so at any
## meaningful severity essentially every real hit blinded the pilot. Measured
## beside the rotors it was stark: 40 points of damage took the camera to 0.00
## while the rotors sat at 0.78, which is why a crash looked catastrophic on the
## feed and barely marked the props.
##
## At 1.0 the transmitter costs its share of the hull and no more: a hit worth a
## third of the hull takes a third of the camera. E.q8 ranks the components and
## the VTX is explicitly the survivable one — *"good rotor with damaged vtx and
## good weapons is medium effective because a player can blind shot more and he
## can be more stable"* — which 3.0 flatly contradicted.
@export var video_damage_scale: float = 1.0
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

@export_group("Electronic warfare")
## How loudly a screamer's jam reads on the video feed, at full jam strength
## (P4.2, user steering 2026-07-28: "the screamer should also jam the VTX").
##
## THIS LIVES ON THE DAMAGE CONFIG ON PURPOSE, and the placement is the design
## point rather than filing convenience: D6 predicted that "EW *and* battle damage
## both degrade FCS — one mechanism", and a jam that reuses the damaged-feed
## effect makes that literal. Being shot and being jammed look the same on the
## screen because they are the same failure — the link is degraded — and the
## pilot's answer to both is the same: fly it manually.
##
## Unlike the damage knobs it is NOT scaled by `severity`. Severity is the
## arcade<->sim dial for how much a HIT costs you, and a jam is not a hit; muting
## EW because someone wants a forgiving damage model would delete a whole roster
## type's readability.
##
## PROVISIONAL — a feel number, not a measured one. It wants hands: strong enough
## that entering a bubble is unmistakable, not so strong that the fight inside one
## is unreadable. 0.55 sits under a wrecked transmitter's hit spike (0.85) and
## above its permanent floor (0.45), so a jam reads as "the feed is going" without
## claiming to be worse than actual damage.
@export var jam_video_glitch: float = 0.55


const SAVE_PATH: String = "user://damage_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_damage_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
