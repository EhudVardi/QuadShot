class_name TerrainMesh
extends StaticBody3D

## The ground, in concentric detail RINGS (GAMEPLAY-DESIGN P1.9).
##
## Two triangles per grid cell, stretched between four samples of
## `TerrainField`, with normals taken analytically from the field. Smooth rolling
## ground — dunes and hills — over a reach measured in kilometres.
##
## ---------------------------------------------------------------------------
## LEVEL OF DETAIL, AND WHY VASTNESS IS THE CHEAP PART
## ---------------------------------------------------------------------------
##
## The user's founding pillar is *truly vast environments*, taken from Delta
## Force's sprawling outdoor maps. The instinct that a huge world must be
## expensive is exactly backwards, and this class is where that gets proved.
##
## Cost is world area divided by cell area, so a uniform grid over 8 km at 4 m
## cells would be 4 million cells and impossible. Instead the ground is a stack
## of CONCENTRIC RINGS centred on the pilot: the innermost is fine, and each ring
## outward doubles its cell size while covering four times the area. Every ring
## costs the SAME number of cells. So the reach grows exponentially while the
## budget grows linearly — five rings of 96 cells reach kilometres for about the
## price of one dense arena.
##
## It works at all because `TerrainField.height_at` is a pure FUNCTION of
## position with nothing stored. There is no heightmap in memory to run out of;
## a ring simply asks the function at its own resolution.
##
## RINGS REBUILD INDEPENDENTLY, and that is what keeps it smooth in flight. Each
## ring is re-centred only when the pilot crosses one of ITS OWN cells, so the
## coarse outer rings — the expensive ones to reach — rebuild very rarely, while
## the cheap inner ring rebuilds often. Motion cost is dominated by the smallest
## ring rather than by the size of the world.
##
## ---------------------------------------------------------------------------
## THE COLLISION IS THE SAME TRIANGLES AS THE PICTURE
## ---------------------------------------------------------------------------
##
## `HeightMapShape3D` is built in and would be cheaper, but it samples on its own
## fixed grid rather than on the ring's — so the collider and the picture would
## describe two slightly different landscapes, and a pilot would touch down on
## ground that is not where they can see it. A cue that disagrees with the
## mechanic teaches the wrong edge.
##
## Only the INNER rings get a collider (`collision_rings`), because collision is
## a thing that happens where the pilot is. Distant ground is a picture.
##
## Every vertex comes from `TerrainField`, so the surface and the query the rest
## of the game asks are the same function — asserted by `terrain_check` against
## the built mesh rather than trusted from this comment.

signal rebuilt(cells: int, triangles: int)

@export var terrain_config: TerrainConfig
## Seed for this instance's landscape. A theater node names its ground with this
## number rather than shipping a heightmap.
@export var terrain_seed: int = 0
@export var material: Material
## How many detail rings. Each doubles the cell size and quadruples the reach, so
## this is a REACH dial far more than a cost dial: at 96 cells and a 4 m base,
## 1 ring reaches 192 m, 4 rings reach 1.5 km, 6 reach 6.1 km.
@export var ring_count: int = 5
## Cells across one ring. The cost dial — every ring pays this squared.
@export var ring_cells: int = 96
## How many inner rings carry collision. Ground you can hit is ground near you.
@export var collision_rings: int = 2
## Node the rings centre on. Left empty, they centre on the origin, which is what
## a headless check wants.
@export var follow: Node3D

## How deep a ring's edge apron hangs, in multiples of that ring's cell size.
## Scaled rather than fixed because the mismatch it hides grows with cell size.
const SKIRT_CELLS: float = 1.2

var field: TerrainField

## One entry per ring: its mesh, its collider, its cell size and where it is
## currently centred (in units of its own cell).
var _rings: Array[Dictionary] = []


func _ready() -> void:
	if terrain_config == null:
		push_warning("[terrain] no TerrainConfig; nothing to build")
		return
	add_to_group(&"terrain")
	field = TerrainField.new(terrain_config, terrain_seed)
	_build_ring_nodes()
	rebuild()


## Ground height under a world point. The public face of `TerrainField` for
## anything holding the node rather than the field — which in phase 2 is most of
## the game. Always the FINE answer, whichever ring happens to be drawing there.
func height_at(x: float, z: float) -> float:
	if field == null:
		return 0.0
	return field.height_at(x, z)


## The size of the world, metres from the centre to a straight edge. Derived
## rather than configured: it is whatever the outermost ring reaches, so the map
## edge and the geometry can never disagree about where the world stops.
func reach_m() -> float:
	if field == null:
		return 0.0
	var cell: float = field.effective_cell_m()
	return 0.5 * float(ring_cells) * cell * pow(2.0, float(maxi(ring_count, 1) - 1))


func _physics_process(_delta: float) -> void:
	if field == null or follow == null:
		return
	_recentre(follow.global_position)


## Re-centres any ring the pilot has walked out of. THE WHOLE POINT IS THAT MOST
## RINGS DO NOTHING MOST OF THE TIME: a ring only moves when the pilot crosses
## one of its own cells, so a 64 m ring re-centres 16 times less often than a
## 4 m one and the cost of flying is dominated by the cheapest ring.
func _recentre(around: Vector3) -> void:
	for i: int in _rings.size():
		var ring: Dictionary = _rings[i]
		var cell: float = float(ring["cell"])
		# Snapped to TWO cells so the hole this ring cuts for its inner
		# neighbour stays aligned with that neighbour's own grid.
		var snap: float = cell * 2.0
		var centre := Vector2i(int(roundf(around.x / snap)),
				int(roundf(around.z / snap)))
		if centre == ring["centre"]:
			continue
		ring["centre"] = centre
		_build_ring(i)


func _build_ring_nodes() -> void:
	for child: Node in get_children():
		child.queue_free()
	_rings.clear()
	var base: float = field.effective_cell_m()
	for i: int in maxi(ring_count, 1):
		var mesh_instance := MeshInstance3D.new()
		add_child(mesh_instance)
		var collision: CollisionShape3D = null
		if i < collision_rings:
			collision = CollisionShape3D.new()
			add_child(collision)
		_rings.append({
			"mesh": mesh_instance,
			"collision": collision,
			"cell": base * pow(2.0, float(i)),
			# Deliberately impossible, so the first `_recentre` always builds.
			"centre": Vector2i(2147483647, 2147483647),
		})


## Rebuilds every ring from scratch. Used at startup and whenever a slider moves;
## flight uses `_recentre`, which rebuilds only what actually moved.
func rebuild() -> void:
	if field == null:
		return
	field.config = terrain_config
	field._configure()
	if _rings.is_empty() or not is_equal_approx(float(_rings[0]["cell"]),
			field.effective_cell_m()) or _rings.size() != maxi(ring_count, 1):
		_build_ring_nodes()
	var here: Vector3 = follow.global_position if follow != null else Vector3.ZERO
	var cells: int = 0
	var triangles: int = 0
	for i: int in _rings.size():
		var ring: Dictionary = _rings[i]
		var snap: float = float(ring["cell"]) * 2.0
		ring["centre"] = Vector2i(int(roundf(here.x / snap)),
				int(roundf(here.z / snap)))
		var built: Vector2i = _build_ring(i)
		cells += built.x
		triangles += built.y
	rebuilt.emit(cells, triangles)


## One ring: a square annulus of cells at this ring's resolution, with the middle
## left out because the finer ring inside covers it.
func _build_ring(index: int) -> Vector2i:
	var ring: Dictionary = _rings[index]
	var cell: float = float(ring["cell"])
	var centre: Vector2i = ring["centre"]
	var origin_x: float = float(centre.x) * cell * 2.0
	var origin_z: float = float(centre.y) * cell * 2.0
	var half: int = maxi(ring_cells, 4) / 2
	# The hole: the inner ring covers a square of ITS cells, which is half this
	# ring's width. Ring 0 has no hole.
	var hole: int = 0 if index == 0 else half / 2
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for ix: int in range(-half, half):
		for iz: int in range(-half, half):
			if index > 0 and absi(ix) < hole and absi(iz) < hole:
				continue
			var x0: float = origin_x + float(ix) * cell
			var z0: float = origin_z + float(iz) * cell
			_add_cell(vertices, normals, x0, z0, cell)
	# THE SEAM COVER. Deep enough to swallow the worst disagreement between this
	# ring and the coarser one outside it, which grows with cell size because a
	# coarser grid cuts more corners off the same landscape.
	var drop: float = cell * SKIRT_CELLS
	var edge: float = float(half) * cell
	for i: int in range(-half, half):
		var t0: float = float(i) * cell
		var t1: float = t0 + cell
		_add_skirt(vertices, normals, origin_x - edge, origin_z + t0,
				origin_x - edge, origin_z + t1, drop)
		_add_skirt(vertices, normals, origin_x + edge, origin_z + t1,
				origin_x + edge, origin_z + t0, drop)
		_add_skirt(vertices, normals, origin_x + t1, origin_z - edge,
				origin_x + t0, origin_z - edge, drop)
		_add_skirt(vertices, normals, origin_x + t0, origin_z + edge,
				origin_x + t1, origin_z + edge, drop)
	var mesh_instance: MeshInstance3D = ring["mesh"]
	if vertices.is_empty():
		mesh_instance.mesh = null
		return Vector2i.ZERO
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh
	if material != null:
		mesh_instance.material_override = material
		var shader_material := material as ShaderMaterial
		if shader_material != null:
			# Kept for any shader that wants to know the sampling scale.
			shader_material.set_shader_parameter(&"cell_size",
					field.effective_cell_m())
	var collision: CollisionShape3D = ring["collision"]
	if collision != null:
		var shape := ConcavePolygonShape3D.new()
		# The mesh's own triangles, not a re-derivation. See the header.
		shape.set_faces(vertices)
		collision.shape = shape
	return Vector2i(int(vertices.size() / 6), int(vertices.size() / 3))


## One grid cell: two triangles between four field samples, with per-vertex
## normals from the field itself. The surface is continuous, and the only reason
## a cell exists at all is that a triangle needs corners.
func _add_cell(vertices: PackedVector3Array, normals: PackedVector3Array,
		x0: float, z0: float, cell: float) -> void:
	var x1: float = x0 + cell
	var z1: float = z0 + cell
	var a := Vector3(x0, field.raw_height_at(x0, z0), z0)
	var b := Vector3(x0, field.raw_height_at(x0, z1), z1)
	var c := Vector3(x1, field.raw_height_at(x1, z1), z1)
	var d := Vector3(x1, field.raw_height_at(x1, z0), z0)
	var na: Vector3 = field.normal_at(x0, z0, cell)
	var nb: Vector3 = field.normal_at(x0, z1, cell)
	var nc: Vector3 = field.normal_at(x1, z1, cell)
	var nd: Vector3 = field.normal_at(x1, z0, cell)
	# THE WINDING WAS ESTABLISHED BY MEASUREMENT rather than by convention, after
	# an earlier build shipped with 40,912 faces inside-out and the map read as
	# unsealed from the cockpit. `terrain_check` holds it now.
	for point: Array in [[a, na], [b, nb], [c, nc], [a, na], [c, nc], [d, nd]]:
		vertices.append(point[0])
		normals.append(point[1])


## A vertical apron hanging off a ring's outer edge.
##
## LOD RINGS DO NOT MEET EXACTLY. A coarse ring samples the field half as often
## as the fine ring inside it, so along their shared boundary the two surfaces
## disagree by however much the landscape curves between samples — and the gap is
## a slit of sky right where the eye is drawn.
##
## A skirt is the standard fix and it is chosen over stitching the two grids
## together on purpose: stitching means the fine ring's boundary vertices have to
## be snapped to the coarse ring's, which couples every ring to its neighbour's
## resolution and has to be redone every time a ring re-centres. An apron is
## geometry nobody looks at that makes the question moot.
func _add_skirt(vertices: PackedVector3Array, normals: PackedVector3Array,
		ax: float, az: float, bx: float, bz: float, drop: float) -> void:
	var top_a := Vector3(ax, field.raw_height_at(ax, az), az)
	var top_b := Vector3(bx, field.raw_height_at(bx, bz), bz)
	var low_a := Vector3(ax, top_a.y - drop, az)
	var low_b := Vector3(bx, top_b.y - drop, bz)
	# SHADED AS GROUND, not as a wall. A skirt is crack filler that should never be
	# noticed, and giving it its true horizontal normal made it catch the light
	# differently from the surface it hides behind — measured by A/B, which showed
	# pale ribbons along the dune crests that vanished with the skirts disabled.
	# The lighting lie is the point: the geometry exists to be invisible.
	for point: Vector3 in [low_a, low_b, top_b, low_a, top_b, top_a]:
		vertices.append(point)
		normals.append(field.normal_at(point.x, point.z, 1.0))
