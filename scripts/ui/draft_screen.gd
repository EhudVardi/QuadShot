class_name DraftScreen
extends CanvasLayer

## Between-sortie upgrade draft (roadmap M4). Opening it pauses the game and
## offers three picks; choosing one resumes flight. The layer runs while
## paused (WHEN_PAUSED in the scene) so the buttons stay clickable, and the
## first option grabs focus so the gamepad can pick with the d-pad too.

signal picked(id: StringName)

@onready var _options_box: HBoxContainer = $Center/Panel/Box/Options

var _option_ids: Array[StringName] = []


func open(options: Array[Dictionary]) -> void:
	_option_ids.clear()
	for stale: Node in _options_box.get_children():
		stale.queue_free()
	for option: Dictionary in options:
		var index: int = _option_ids.size()
		_option_ids.append(option["id"])
		var button := Button.new()
		button.text = "%s\n\n%s" % [option["title"], option["desc"]]
		button.custom_minimum_size = Vector2(220.0, 110.0)
		button.pressed.connect(_on_pressed.bind(index))
		_options_box.add_child(button)
	visible = true
	get_tree().paused = true
	if _options_box.get_child_count() > 0:
		(_options_box.get_child(0) as Button).grab_focus()


## Test hook: choose an option without UI interaction.
func pick(index: int) -> void:
	_on_pressed(index)


func _on_pressed(index: int) -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	picked.emit(_option_ids[index])
