class_name GameHud
extends CanvasLayer

## Minimal in-flight HUD (roadmap M1/M2): reticle, score, health, damage
## flash, death message. Function over beauty; every control ignores the
## mouse so the tuning overlay stays fully clickable.

@onready var _score_label: Label = $ScoreLabel


func set_score(total: int) -> void:
	_score_label.text = "SCORE %d" % total
