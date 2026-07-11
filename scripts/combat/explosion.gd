class_name ExplosionEffect
extends Node3D

## One-shot explosion: fire + smoke particle bursts and a light flash, then
## self-frees. Spawn via Effects.explosion()/impact().

@onready var _fire: CPUParticles3D = $Fire
@onready var _smoke: CPUParticles3D = $Smoke
@onready var _flash: OmniLight3D = $Flash


func detonate(size: float = 1.0) -> void:
	scale = Vector3.ONE * size
	_fire.emitting = true
	_smoke.emitting = true
	_flash.light_energy = 6.0 * size
	_flash.omni_range = 10.0 * size
	var tween: Tween = create_tween()
	tween.tween_property(_flash, "light_energy", 0.0, 0.35)
	SoundBank.play_at(&"explosion", global_position,
			lerpf(-20.0, 0.0, clampf(size, 0.0, 1.0)), 0.15)
	get_tree().create_timer(2.0).timeout.connect(queue_free)
