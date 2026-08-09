class_name TerrainEnvironment
extends Node3D

## Puts the things that stand on the ground ON the ground (P1.9, phase 1).
##
## SMALL, AND THE POINT IS THAT IT IS THE FIRST CONSUMER OF `height_at`. Phase 2
## is teaching the whole game to stop assuming the ground is a flat plane at
## y = 0 — enemies, bombs, sortie placement, the ingress, the city. This is that
## pattern written once, on the two easiest cases, so the shape is established
## before it has to be applied to things that can be broken by getting it wrong.
##
## It also makes the map FLYABLE, which is the actual deliverable: without it the
## drone spawns at y = 0.8 and the landscape's origin can easily be a hillside,
## so the human would open the map inside a rock and reasonably conclude the
## terrain is broken.

## Clearance above the ground for the spawn pad's underside.
const PAD_LIFT: float = 0.06
## How high above the pad the drone is placed.
const DRONE_LIFT: float = 0.8

@onready var _terrain: TerrainMesh = $Terrain
@onready var _pad: Node3D = $SpawnPad
@onready var _spawn_point: Node3D = $SpawnPoint


func _ready() -> void:
	# `_terrain._ready` has already run: Godot readies children before parents,
	# so the field exists and the mesh is built by the time this is called.
	#
	# THE RINGS FOLLOW THE PILOT, and they are told who that is from here rather
	# than finding it themselves — the terrain should not know what a player is,
	# and a headless check wants rings centred on the origin instead.
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player is Node3D:
		_terrain.follow = player as Node3D
	_settle()
	_terrain.rebuilt.connect(_on_rebuilt)


## The overlay can rebuild the landscape under a parked drone. Re-settling the
## pad on every rebuild is what stops the human's sliders burying it — but the
## DRONE is deliberately left alone, because moving a flying pilot because a
## slider moved would be worse than the hole it prevents.
func _on_rebuilt(_cells: int, _triangles: int) -> void:
	_settle()


func _settle() -> void:
	var ground: float = _terrain.height_at(0.0, 0.0)
	_pad.global_position = Vector3(0.0, ground + PAD_LIFT, 0.0)
	_spawn_point.global_position = Vector3(0.0, ground + DRONE_LIFT, 0.0)
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method("place_at"):
		return
	# `place_at` rather than setting the transform: it also re-bases the drone's
	# reset point, so pressing reset returns the pilot to the pad rather than to
	# wherever y = 0 happens to be inside the landscape.
	var landed := Transform3D((player as Node3D).global_transform.basis,
			Vector3(0.0, ground + DRONE_LIFT, 0.0))
	player.call("place_at", landed)
