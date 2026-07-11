extends AudioStreamPlayer3D

## Motor whine: looping synth tone, pitch and volume driven by the mean
## |motor output| every frame. Silent while disarmed. Placeholder aesthetics
## constants, exempt from the config rule (see sound_bank.gd).

var _drone: FlightController


func _ready() -> void:
	# Headless (tests): active playbacks leak at quit() under the Dummy
	# audio driver, and nothing hears them anyway.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_drone = owner as FlightController
	stream = SoundBank.make_motor_loop()
	volume_db = -60.0
	play()


func _process(_delta: float) -> void:
	var average: float = 0.0
	for i: int in MotorModel.MOTOR_COUNT:
		average += absf(_drone.motor_output(i))
	average /= float(MotorModel.MOTOR_COUNT)
	if not _drone.armed or average < 0.01:
		volume_db = -60.0
		return
	pitch_scale = 0.75 + 1.6 * average
	volume_db = lerpf(-36.0, -10.0, clampf(average, 0.0, 1.0))
