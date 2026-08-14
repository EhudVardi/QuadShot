extends AudioStreamPlayer

## Wind rush: non-positional looping noise, volume/pitch driven by airspeed.
## Placeholder aesthetics constants, exempt from the config rule.

@export var audio_config: AudioConfig

var _drone: FlightController


func _ready() -> void:
	# Headless (tests): see motor_audio.gd.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_drone = owner as FlightController
	stream = SoundBank.make_wind_loop()
	volume_db = -60.0
	play()


func _process(_delta: float) -> void:
	# Scaled to THIS airframe's envelope rather than to a constant 35 m/s: the
	# Kestrel tops out near 31 m/s and the Roc near 131, so a fixed reference
	# pinned the big frames' wind at maximum through four fifths of their speed
	# range and stopped conveying anything (see FlightConfig.terminal_speed).
	var intensity: float = clampf(
			_drone.linear_velocity.length() / _drone.config.terminal_speed(), 0.0, 1.0)
	volume_db = lerpf(-50.0, -12.0, intensity) \
			+ AudioConfig.gain_to_db(audio_config.wind_volume)
	pitch_scale = 0.8 + 0.7 * intensity
