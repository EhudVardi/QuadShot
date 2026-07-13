class_name FlightPresets
extends Object

## Named rate-loop tunes (physics tuning session, roadmap M4 tail). Each
## preset is a full snapshot of the five knobs rate_tune_sweep.gd measured
## (rate_p/i/d/ff, angular_damping), so selecting one is one atomic swap,
## never a partial edit. "Custom" isn't a stored state — the overlay just
## compares the live config against every preset each time a relevant
## slider moves, so it can never drift out of sync.
##
## Ordered softest → sharpest so the dropdown reads as a feel spectrum.
## Default reproduces the original baked feel (bench-verified: it never
## reaches the commanded rate before angular_damping eats it — see
## rate_tune_sweep.gd's t63/sustained columns). Cinematic is a softer point
## still; Freestyle and Race are the two bench-clean fast candidates; Cruise
## and Sport bridge the wide Default→Freestyle gap (bench @100ms/sustained
## step monotonically between them) — responsive without the twitch, planted
## without the float.

const POOL: Array[Dictionary] = [
	{
		"name": "Cinematic",
		"rate_p": Vector3(0.003, 0.003, 0.003),
		"rate_i": Vector3(0.002, 0.002, 0.002),
		"rate_d": Vector3(0.00003, 0.00003, 0.00003),
		"rate_ff": Vector3.ZERO,
		"angular_damping": 0.03,
	},
	{
		"name": "Default",
		"rate_p": Vector3(0.004, 0.004, 0.004),
		"rate_i": Vector3(0.002, 0.002, 0.002),
		"rate_d": Vector3(0.00003, 0.00003, 0.00003),
		"rate_ff": Vector3.ZERO,
		"angular_damping": 0.02,
	},
	{
		"name": "Cruise",
		"rate_p": Vector3(0.007, 0.007, 0.007),
		"rate_i": Vector3(0.002, 0.002, 0.002),
		"rate_d": Vector3(0.00003, 0.00003, 0.00003),
		"rate_ff": Vector3(0.0008, 0.0008, 0.0008),
		"angular_damping": 0.013,
	},
	{
		"name": "Sport",
		"rate_p": Vector3(0.009, 0.009, 0.009),
		"rate_i": Vector3(0.002, 0.002, 0.002),
		"rate_d": Vector3(0.00003, 0.00003, 0.00003),
		"rate_ff": Vector3(0.001, 0.001, 0.001),
		"angular_damping": 0.010,
	},
	{
		"name": "Freestyle",
		"rate_p": Vector3(0.012, 0.012, 0.012),
		"rate_i": Vector3(0.002, 0.002, 0.002),
		"rate_d": Vector3(0.00003, 0.00003, 0.00003),
		"rate_ff": Vector3(0.001, 0.001, 0.001),
		"angular_damping": 0.008,
	},
	{
		"name": "Race",
		"rate_p": Vector3(0.02, 0.02, 0.02),
		"rate_i": Vector3(0.002, 0.002, 0.002),
		"rate_d": Vector3(0.00003, 0.00003, 0.00003),
		"rate_ff": Vector3(0.0005, 0.0005, 0.0005),
		"angular_damping": 0.002,
	},
]

const _MATCH_EPS: float = 0.0000001


static func apply(preset: Dictionary, config: FlightConfig) -> void:
	config.rate_p = preset["rate_p"]
	config.rate_i = preset["rate_i"]
	config.rate_d = preset["rate_d"]
	config.rate_ff = preset["rate_ff"]
	config.angular_damping = preset["angular_damping"]


## Name of the preset the live config exactly matches, or "Custom" once any
## of the five fields has drifted from all of them.
static func active_name(config: FlightConfig) -> String:
	for preset: Dictionary in POOL:
		if _matches(preset, config):
			return preset["name"]
	return "Custom"


static func _matches(preset: Dictionary, config: FlightConfig) -> bool:
	return _vec_close(preset["rate_p"], config.rate_p) \
			and _vec_close(preset["rate_i"], config.rate_i) \
			and _vec_close(preset["rate_d"], config.rate_d) \
			and _vec_close(preset["rate_ff"], config.rate_ff) \
			and absf(preset["angular_damping"] - config.angular_damping) < _MATCH_EPS


static func _vec_close(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < _MATCH_EPS and absf(a.y - b.y) < _MATCH_EPS \
			and absf(a.z - b.z) < _MATCH_EPS
