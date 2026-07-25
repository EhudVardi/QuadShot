class_name BoxBatcher
extends RefCounted

## Batches unit boxes by material into merged ArrayMeshes, so a building's
## hundreds of per-box MeshInstance3D draw calls collapse to one per material
## (B3/B4 perf pass, v1.57). Static geometry only — the boxes never move after
## the build. Collision is unaffected: the caller still adds its own shapes;
## this batches only the VISUAL mesh.
##
## It works with the world-space neon_structure shader with NO visual change:
## append_from bakes each box's offset into the frame-local mesh, and the merged
## MeshInstance's transform still maps that to the same world position — so the
## world-space seams land exactly where they did per-box. Normals/UVs are copied
## transformed (no generate_normals, which would round the hard box edges).

var _by_material: Dictionary = {}


## Queue a box; its offset and yaw are baked into the shared, material-keyed mesh.
func add(size: Vector3, at: Vector3, material: Material, yaw: float = 0.0) -> void:
	var st: SurfaceTool = _by_material.get(material)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_by_material[material] = st
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	st.append_from(box, 0, Transform3D(Basis(Vector3.UP, yaw), at))


## Commit one merged MeshInstance3D per material under `parent`, then reset.
func commit_into(parent: Node) -> void:
	for material: Material in _by_material:
		var mesh: ArrayMesh = _by_material[material].commit()
		if mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, material)
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		parent.add_child(mesh_instance)
	_by_material.clear()
