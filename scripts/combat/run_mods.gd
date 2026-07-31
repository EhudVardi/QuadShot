class_name RunMods
extends RefCounted

## Run-scoped upgrade modifiers (roadmap M4). Upgrades NEVER mutate the
## tunable configs — those are the human-calibrated baseline. Combat code
## multiplies config values by the current mods; a new run resets to neutral.

static var current: RunMods = RunMods.new()

## Blaster only. These two were read by the flak pod as well until v1.86, so
## one card labelled "blaster" silently upgraded two weapons — and because the
## pod's cadence is its whole power curve, the free half of the buff was the
## larger half. The cards always said "blaster"; the fields were named
## generically and the pod, added later, simply reused them.
var fire_rate_mult: float = 1.0
var damage_mult: float = 1.0
## The blaster's duty cycle: how much heat the sink holds, and how fast it
## sheds. Upgradeable on purpose (R.q1) — the pace of your default weapon
## should be something you can spend a draft pick on.
var heat_capacity_mult: float = 1.0
var heat_cool_mult: float = 1.0
## Flak pod. Its own cards now, so the pod's power curve is something the
## player spends a draft pick on rather than something they inherit.
var flak_fire_rate_mult: float = 1.0
var flak_damage_mult: float = 1.0
var missile_cooldown_mult: float = 1.0
var lock_time_mult: float = 1.0
var lock_cone_mult: float = 1.0
var max_health_bonus: float = 0.0
var regen_rate: float = 0.0
var score_mult: float = 1.0


static func reset() -> void:
	current = RunMods.new()
