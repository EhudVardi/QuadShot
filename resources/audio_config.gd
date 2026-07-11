class_name AudioConfig
extends TunableConfig

## Audio levels, live-tunable in the overlay like everything else.
## Linear gains [0, 1]: master drives the Master bus, the rest scale their
## category relative to it.

@export_group("Volume")
@export var master_volume: float = 0.1
@export var sfx_volume: float = 1.0
@export var motor_volume: float = 1.0
@export var wind_volume: float = 1.0


const SAVE_PATH: String = "user://audio_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_audio_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH


## -80 dB floor instead of linear_to_db(0) = -inf.
static func gain_to_db(gain: float) -> float:
	return linear_to_db(maxf(gain, 0.0001))
