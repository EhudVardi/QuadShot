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
## window (Vector2), sill (float), pixel (float).

signal floor_entered(frame: MenuFloorFrame)
signal floor_committed(frame: MenuFloorFrame)
signal floor_canceled(frame: MenuFloorFrame)

const FLOOR_PITCH: float = 4.0
const SLAB_SIZE: Vector3 = Vector3(12.6, 0.4, 12.6)
const LINER_SIZE: Vector3 = Vector3(12.4, 0.1, 12.4)

## Bottom→top, filled at _ready; the side view walks this.
var frames: Array[MenuFloorFrame] = []

var _floors: Array = []


static func create(floors: Array) -> MenuBuilding:
	var building: MenuBuilding = MenuBuilding.new()
	building._floors = floors
	return building


func height() -> float:
	return _floors.size() * FLOOR_PITCH + 0.4


func _ready() -> void:
	var slab_material: ShaderMaterial = ShaderMaterial.new()
	slab_material.shader = load("res://resources/neon_structure.gdshader") as Shader
	var void_material: StandardMaterial3D = StandardMaterial3D.new()
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_material.albedo_color = Color(0.008, 0.01, 0.015)
	var body: StaticBody3D = StaticBody3D.new()
	add_child(body)
	for k: int in _floors.size() + 1:
		_add_slab(body, k * FLOOR_PITCH + 0.2, slab_material, void_material)
	for k: int in _floors.size():
		var spec: Dictionary = _floors[k]
		var frame: MenuFloorFrame = MenuFloorFrame.new()
		frame.leaf_id = spec["leaf"]
		frame.label = spec["label"]
		frame.window_size = spec["window"]
		frame.sill = spec["sill"]
		frame.text_pixel = spec["pixel"]
		frame.position = Vector3(0.0, k * FLOOR_PITCH + 0.4, 0.0)
		add_child(frame)
		frames.append(frame)
		frame.entered.connect(func(_id: StringName) -> void:
				floor_entered.emit(frame))
		frame.committed.connect(func(_id: StringName) -> void:
				floor_committed.emit(frame))
		frame.canceled.connect(func(_id: StringName) -> void:
				floor_canceled.emit(frame))


func _add_slab(body: StaticBody3D, at_y: float, slab_material: Material,
		void_material: Material) -> void:
	var slab: MeshInstance3D = MeshInstance3D.new()
	var slab_mesh: BoxMesh = BoxMesh.new()
	slab_mesh.size = SLAB_SIZE
	slab_mesh.material = slab_material
	slab.mesh = slab_mesh
	slab.position = Vector3(0.0, at_y, 0.0)
	body.add_child(slab)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = SLAB_SIZE
	collision.shape = shape
	collision.position = Vector3(0.0, at_y, 0.0)
	body.add_child(collision)
	# The void liner (v1.42): a near-black skin nested inside the slab, so a
	# camera clipping the slab surface sees darkness, never the next floor.
	var liner: MeshInstance3D = MeshInstance3D.new()
	var liner_mesh: BoxMesh = BoxMesh.new()
	liner_mesh.size = LINER_SIZE
	liner_mesh.material = void_material
	liner.mesh = liner_mesh
	liner.position = Vector3(0.0, at_y, 0.0)
	body.add_child(liner)
