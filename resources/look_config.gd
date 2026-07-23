class_name LookConfig
extends TunableConfig

## Post-processing / atmosphere mood (pre-M5 "look-lite" pass). Live-tunable
## exactly like FlightConfig: a LookController reads these each frame and
## writes them onto the scene's Environment and Sun, so the overlay tunes the
## whole mood while the gamepad flies. Tonemapper is fixed to AgX (filmic,
## gentle highlight desaturation — kind to emissive/neon); exposure and the
## rest are the knobs. Defaults are already dialed for a dusk mood, not
## neutral — the point of the pass is that it looks good on open.

@export_group("Exposure")
@export var exposure: float = 1.0

@export_group("Auto Exposure")
## The "darker inside" moment (GAMEPLAY-DESIGN B2): the camera's eye adapting,
## not the world changing. Scene luminance drives exposure between the min/max
## sensitivity clamps at adapt speed; scale biases the metered target.
## auto_exposure is a 0/1 switch kept as a float — the overlay rows and the
## preset system only speak float, and a half-on eye means nothing.
@export var auto_exposure: float = 1.0
@export var auto_exposure_scale: float = 0.4
@export var auto_exposure_speed: float = 0.5
@export var auto_exposure_min_sensitivity: float = 0.0
@export var auto_exposure_max_sensitivity: float = 800.0

@export_group("Glow")
## Only pixels brighter than glow_hdr_threshold bloom, so emissive/neon and
## the sun glow while flat surfaces stay crisp. glow_bloom adds a little
## threshold-independent softness on top.
@export var glow_intensity: float = 0.9
@export var glow_strength: float = 1.0
@export var glow_bloom: float = 0.1
@export var glow_hdr_threshold: float = 1.0

@export_group("Ambient Occlusion")
@export var ssao_intensity: float = 2.5
@export var ssao_radius: float = 1.2

@export_group("Fog")
@export var fog_density: float = 0.006
@export var fog_aerial_perspective: float = 0.6
@export var fog_sky_affect: float = 0.4

@export_group("Color Grade")
@export var brightness: float = 1.0
@export var contrast: float = 1.08
@export var saturation: float = 1.12

@export_group("Lighting")
@export var ambient_energy: float = 1.0
@export var sun_energy: float = 1.4
## Sun elevation (deg above the horizon) and compass angle — the time-of-day
## and shadow-direction knobs.
@export var sun_pitch_deg: float = 40.0
@export var sun_yaw_deg: float = 30.0


const SAVE_PATH: String = "user://look_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_look_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
