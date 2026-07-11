extends AudioStreamPlayer

## Wind rush: non-positional looping noise, volume/pitch driven by airspeed.
## Placeholder aesthetics constants, exempt from the config rule.

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
	var intensity: float = clampf(_drone.linear_velocity.length() / 35.0, 0.0, 1.0)
	volume_db = lerpf(-50.0, -12.0, intensity)
	pitch_scale = 0.8 + 0.7 * intensity
