class_name WeatherConfig
extends TunableConfig

## ⚠ TODO STUB — none of these fields are wired into the simulation yet.
## This group exists to shape the work (GAMEPLAY-DESIGN.md P1.6: weather as
## per-sector battlefield modifier packs). Planned order: dynamic wind first
## (honest external forces on the airframe — never bending the flight model),
## then precipitation/fog/heat as visibility, sensor and thermal modifiers.

@export_group("Wind (TODO)")
## Compass heading the wind blows FROM, degrees.
@export var wind_heading_deg: float = 0.0
## Steady wind speed, m/s.
@export var wind_speed_ms: float = 0.0
## Gust amplitude on top of the steady wind, m/s.
@export var wind_gust_ms: float = 0.0

@export_group("Conditions (TODO)")
## 0 = dry … 1 = downpour (visibility, lens, sensor penalties).
@export var precipitation: float = 0.0
## 0 = clear … 1 = soup (visual + missile-lock range compression).
@export var fog_amount: float = 0.0
## 0 = mild … 1 = heat wave (motor thermal pressure at sustained throttle).
@export var heat_wave: float = 0.0


const SAVE_PATH: String = "user://weather_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_weather_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
