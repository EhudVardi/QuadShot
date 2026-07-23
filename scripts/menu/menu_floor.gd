class_name MenuFloor
extends Area3D

## One open floor of the menu tower (GAMEPLAY-DESIGN B5): the fly-through
## selection verb. Entering through a window arms the floor; leaving decides
## — the FAR side commits the leaf, the side you came from cancels. Commit
## only ever happens deep on the other side of a full interior crossing, so
## a graze at speed is a scare, not a mis-pick (the v1.34 steering).
##
## The floor knows nothing about what its leaf launches; it only reports.
## The zone box is expected to span the interior exactly, so an exit
## position past either window plane names the verdict by its local z sign.

signal entered(leaf_id: StringName)
signal committed(leaf_id: StringName)
signal canceled(leaf_id: StringName)

## Half-depth of the interior in local z. Exits past -half are the far side
## (commit); past +half is the entry side (cancel). A respawn teleport lands
## outside the entry side, which reads as cancel — the honest verdict for a
## crash mid-decision.
const ROOM_HALF_DEPTH: float = 5.6

@export var leaf_id: StringName = &""


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is FlightController:
		entered.emit(leaf_id)


func _on_body_exited(body: Node3D) -> void:
	if not (body is FlightController):
		return
	var local_z: float = to_local(body.global_position).z
	if local_z <= -ROOM_HALF_DEPTH:
		committed.emit(leaf_id)
	elif local_z >= ROOM_HALF_DEPTH:
		canceled.emit(leaf_id)
