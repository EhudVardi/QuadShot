class_name AudioConfig
extends TunableConfig

## Audio levels, live-tunable in the overlay like everything else.
## Linear gains [0, 1]: master drives the Master bus, the rest scale their
## category relative to it.

@export_group("Volume")
@export var master_volume: float = 0.1
@export var sfx_volume: float = 1.0
## Baked to 0.5 on 2026-08-15, on the human's call once the four-emitter rework
## was signed off: *"burn motor_volume to 0.5, now that it works good. its now
## def too low."* It had shipped at 0.05, a tenth of this.
##
## THE SCRIPT DEFAULT IS KEPT IN STEP WITH `default_audio_config.tres` ON
## PURPOSE. It was 1.0 against a .tres of 0.05, and that gap is exactly the
## silent desync the `user://` leak fix warned about: a saved override that names
## other fields loads THIS value, not the .tres one, so the two disagreeing means
## a config can arrive twenty times too loud depending on which path it took.
@export var motor_volume: float = 0.5
@export var wind_volume: float = 1.0

@export_group("Pause")
## Low-pass cutoff (Hz) applied to the Master bus while pause/slow-mo is
## active — the "stepped out of the club" muffle. 0 disables.
@export var pause_muffle_hz: float = 600.0


const SAVE_PATH: String = "user://audio_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_audio_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH


## -80 dB floor instead of linear_to_db(0) = -inf.
static func gain_to_db(gain: float) -> float:
	return linear_to_db(maxf(gain, 0.0001))
