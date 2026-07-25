class_name MenuBuilding
extends Node3D

## A menu building assembled at runtime (GAMEPLAY-DESIGN B5 step 4): a stack
## of MenuFloorFrame floors between neon slab lips, with void liners (v1.42)
## nested in every slab and a roof on top. The root tower and every
## dynamically spawned sub-menu building are the SAME construction — one
## code path, nothing drifts. NOT the B3 generator: no seeds, no rooms; the
## floor list is authored data handed in by the tower script.
##
## Floor spec dictionaries: leaf (StringName), label (String),
## window (Vector2), sill (float), pixel (float), state (StringName). Every
## key is optional — a closed floor (B4 enterability) is just {"state":
## &"sealed"} or {"state": &"under_construction"}, and the open-floor fields
## default to a sensible window when absent.

signal floor_entered(frame: MenuFloorFrame)
signal floor_committed(frame: MenuFloorFrame)
signal floor_canceled(frame: MenuFloorFrame)

const SLAB_THICK: float = 0.4
const LINER_THICK: float = 0.1
## The slab plate overhangs its floor footprint by this lip; the void liner
## sits just inside the plate. Per-floor footprints (B3 variety) size each
## slab, so a narrower floor above a wider one leaves a setback ledge.
const SLAB_LIP: float = 0.6
const LINER_LIP: float = 0.4
const DEFAULT_FOOTPRINT: float = 12.0
## Floor pitch = interior height + slab thickness (v1.50): the slab exactly
## fills the gap between one floor's ceiling and the next floor's deck, so the
## stack stays sound at any interior height. Buildings vary floor height (B3).
const DEFAULT_INTERIOR_HEIGHT: float = 3.6

## Bottom→top, filled at _ready; the side view walks this.
var frames: Array[MenuFloorFrame] = []

var _floors: Array = []


static func create(floors: Array) -> MenuBuilding:
	var building: MenuBuilding = MenuBuilding.new()
	building._floors = floors
	return building


func height() -> float:
	return _floors.size() * _pitch() + SLAB_THICK


## Uniform per building: all floors carry the same stamped interior height, so
## floor 0's value sets the pitch for the whole stack.
func _interior_height() -> float:
	if _floors.is_empty():
		return DEFAULT_INTERIOR_HEIGHT
	return _floors[0].get("interior_height", DEFAULT_INTERIOR_HEIGHT)


func _pitch() -> float:
	return _interior_height() + SLAB_THICK


func _ready() -> void:
	var slab_material: ShaderMaterial = ShaderMaterial.new()
	slab_material.shader = load("res://resources/neon_structure.gdshader") as Shader
	var void_material: StandardMaterial3D = StandardMaterial3D.new()
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_material.albedo_color = Color(0.008, 0.01, 0.015)
	var body: StaticBody3D = StaticBody3D.new()
	add_child(body)
	var pitch: float = _pitch()
	for k: int in _floors.size() + 1:
		_add_slab(body, k * pitch + SLAB_THICK * 0.5, _slab_footprint(k),
				slab_material, void_material)
	for k: int in _floors.size():
		var spec: Dictionary = _floors[k]
		var frame: MenuFloorFrame = MenuFloorFrame.new()
		frame.state = spec.get("state", MenuFloorFrame.STATE_OPEN)
		frame.leaf_id = spec.get("leaf", &"")
		frame.label = spec.get("label", "")
		frame.window_size = spec.get("window", Vector2(3.0, 2.2))
		frame.sill = spec.get("sill", 0.6)
		frame.text_pixel = spec.get("pixel", 0.1)
		frame.footprint = spec.get("footprint", DEFAULT_FOOTPRINT)
		frame.cross_windows = spec.get("cross_windows", false)
		frame.interior_height = spec.get("interior_height", DEFAULT_INTERIOR_HEIGHT)
		frame.position = Vector3(0.0, k * pitch + SLAB_THICK, 0.0)
		add_child(frame)
		frames.append(frame)
		frame.entered.connect(func(_id: StringName) -> void:
				floor_entered.emit(frame))
		frame.committed.connect(func(_id: StringName) -> void:
				floor_committed.emit(frame))
		frame.canceled.connect(func(_id: StringName) -> void:
				floor_canceled.emit(frame))


## Slab k sits below floor k; size it to the WIDER of the floors it touches so
## a setback (a narrower floor above) leaves a ledge on the roof of the wider
## floor below. The bottom plate and roof clamp to the end floors.
func _slab_footprint(k: int) -> float:
	return maxf(_floor_footprint(k - 1), _floor_footprint(k))


func _floor_footprint(k: int) -> float:
	var idx: int = clampi(k, 0, _floors.size() - 1)
	return _floors[idx].get("footprint", DEFAULT_FOOTPRINT)


func _add_slab(body: StaticBody3D, at_y: float, fp: float,
		slab_material: Material, void_material: Material) -> void:
	var slab_size: Vector3 = Vector3(fp + SLAB_LIP, SLAB_THICK, fp + SLAB_LIP)
	var slab: MeshInstance3D = MeshInstance3D.new()
	var slab_mesh: BoxMesh = BoxMesh.new()
	slab_mesh.size = slab_size
	slab_mesh.material = slab_material
	slab.mesh = slab_mesh
	slab.position = Vector3(0.0, at_y, 0.0)
	body.add_child(slab)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = slab_size
	collision.shape = shape
	collision.position = Vector3(0.0, at_y, 0.0)
	body.add_child(collision)
	# The void liner (v1.42): a near-black skin nested inside the slab, so a
	# camera clipping the slab surface sees darkness, never the next floor.
	var liner: MeshInstance3D = MeshInstance3D.new()
	var liner_mesh: BoxMesh = BoxMesh.new()
	liner_mesh.size = Vector3(fp + LINER_LIP, LINER_THICK, fp + LINER_LIP)
	liner_mesh.material = void_material
	liner.mesh = liner_mesh
	liner.position = Vector3(0.0, at_y, 0.0)
	body.add_child(liner)
