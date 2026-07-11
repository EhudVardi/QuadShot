class_name RunMods
extends RefCounted

## Run-scoped upgrade modifiers (roadmap M4). Upgrades NEVER mutate the
## tunable configs — those are the human-calibrated baseline. Combat code
## multiplies config values by the current mods; a new run resets to neutral.

static var current: RunMods = RunMods.new()

var fire_rate_mult: float = 1.0
var damage_mult: float = 1.0
var missile_cooldown_mult: float = 1.0
var lock_time_mult: float = 1.0
var lock_cone_mult: float = 1.0
var max_health_bonus: float = 0.0
var regen_rate: float = 0.0
var score_mult: float = 1.0


static func reset() -> void:
	current = RunMods.new()
