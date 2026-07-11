class_name GameHud
extends CanvasLayer

## Minimal in-flight HUD (roadmap M1/M2): reticle, score, health, damage
## flash, death message. Function over beauty; every control ignores the
## mouse so the tuning overlay stays fully clickable.

@onready var _score_label: Label = $ScoreLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _death_label: Label = $DeathLabel


func set_score(total: int) -> void:
	_score_label.text = "SCORE %d" % total


func set_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func flash_damage() -> void:
	_damage_flash.color = Color(1, 0, 0, 0.3)
	create_tween().tween_property(_damage_flash, "color:a", 0.0, 0.4)


func show_death(dead: bool) -> void:
	_death_label.visible = dead
