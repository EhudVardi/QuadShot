class_name LookController
extends Node

## Applies a LookConfig onto the scene's Environment and Sun every frame
## (pre-M5 look pass), so the debug overlay tunes the whole mood live — same
## contract as FlightController re-reading fov/uptilt. Owns no look values
## itself; the shared default_look_config.tres is the source of truth, so the
## overlay's LOOK sliders and this controller stay in lockstep.

const TONEMAP_AGX: int = 4  # Environment.TONE_MAPPER_AGX

@export var look_config: LookConfig

@onready var _world_env: WorldEnvironment = get_node_or_null(^"../WorldEnvironment")
@onready var _sun: DirectionalLight3D = get_node_or_null(^"../Sun")


func _ready() -> void:
	if _world_env == null or _world_env.environment == null or look_config == null:
		push_warning("[look] missing WorldEnvironment/Sun/config — disabled")
		set_process(false)
		return
	if look_config.load_from_user():
		print("[look] loaded %s" % look_config.save_path())
	_enable_features()


func _process(_delta: float) -> void:
	_apply()


## Feature toggles are set once; the numeric mood lives in the config and is
## re-applied each frame so live tuning takes effect immediately.
func _enable_features() -> void:
	var env: Environment = _world_env.environment
	env.tonemap_mode = TONEMAP_AGX
	env.glow_enabled = true
	env.ssao_enabled = true
	env.fog_enabled = true
	env.adjustment_enabled = true


func _apply() -> void:
	var env: Environment = _world_env.environment
	env.tonemap_exposure = look_config.exposure
	env.glow_intensity = look_config.glow_intensity
	env.glow_strength = look_config.glow_strength
	env.glow_bloom = look_config.glow_bloom
	env.glow_hdr_threshold = look_config.glow_hdr_threshold
	env.ssao_intensity = look_config.ssao_intensity
	env.ssao_radius = look_config.ssao_radius
	env.fog_density = look_config.fog_density
	env.fog_aerial_perspective = look_config.fog_aerial_perspective
	env.fog_sky_affect = look_config.fog_sky_affect
	env.adjustment_brightness = look_config.brightness
	env.adjustment_contrast = look_config.contrast
	env.adjustment_saturation = look_config.saturation
	env.ambient_light_energy = look_config.ambient_energy
	if _sun != null:
		_sun.light_energy = look_config.sun_energy
		# Directional light shines along local -Z; negative pitch tilts it
		# down from the horizon, yaw swings the compass direction.
		_sun.rotation = Vector3(
				deg_to_rad(-look_config.sun_pitch_deg),
				deg_to_rad(look_config.sun_yaw_deg),
				0.0)
