class_name DesertLandmarks
extends Node3D

## Landmarks for the desert biome (GAMEPLAY-DESIGN P1.9): a stepped pyramid and
## scattered ruins, planted on whatever the terrain does underneath them.
##
## THEY EXIST BECAUSE VAST PLUS PROCEDURAL EQUALS EMPTY. Ten kilometres of one
## noise function is ten kilometres of nothing — Delta Force's maps were
## authored, and the reason they played well is that somebody put that ridge
## there on purpose. The user's own answer was the right one: *"we wont have to
## proceduraly generate everything. we can still handcraft a few cells."*
##
## So these are placed from a SHORT AUTHORED TABLE rather than scattered by
## noise. That is the point of them: a landmark you can navigate by has to be
## somewhere a person chose, or it is just more texture. The generator's job is
## the ground between them.
##
## THEY READ BY SILHOUETTE, because that is what survives distance in a vast map.
## A stepped pyramid against haze is legible from kilometres out where surface
## detail is long gone, which is the whole job of a landmark.
##
## Every piece asks `TerrainMesh.height_at` for its footing, which makes this
## the second consumer of the query the whole game will grow to depend on, and a
## useful rehearsal for phase 2's much larger version of the same job.

## (x, z, base half-width, step height count) for each pyramid.
const PYRAMIDS: Array[Array] = [
	[420.0, -680.0, 62.0, 15],
	[-1150.0, 900.0, 38.0, 10],
]
## (x, z, seed) for each ruin field. The seed decides the arrangement, so a ruin
## is reproducible without being authored brick by brick.
const RUINS: Array[Array] = [
	[-380.0, -240.0, 11],
	[880.0, 640.0, 29],
	[-90.0, 1180.0, 47],
	[1320.0, -1260.0, 63],
]

@export var terrain: TerrainMesh
@export var stone: Material
## Height of one course of masonry. Matched to the terrain's own step by default
## so the two share a grammar.
@export var course_m: float = 6.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if terrain == null:
		push_warning("[landmarks] no terrain to stand on")
		return
	# The terrain's `_ready` has already run — Godot readies children before
	# parents and this node is placed after it — so `height_at` is live.
	for pyramid: Array in PYRAMIDS:
		_build_pyramid(float(pyramid[0]), float(pyramid[1]), float(pyramid[2]),
				int(pyramid[3]))
	for ruin: Array in RUINS:
		_build_ruin(float(ruin[0]), float(ruin[1]), int(ruin[2]))


## A stepped pyramid, each course inset from the one below. Built as ONE mesh
## rather than as a pile of MeshInstance3Ds: a 15-course pyramid is 15 boxes, and
## fifteen draw calls for one landmark is how a vast map dies by a thousand cuts.
func _build_pyramid(x: float, z: float, half: float, courses: int) -> void:
	var base: float = _lowest_corner(x, z, half)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i: int in courses:
		var inset: float = half * (float(i) / float(courses))
		var w: float = half - inset
		var y0: float = base + float(i) * course_m
		# Each course sinks slightly into the one below so no hairline of sky
		# shows through the seam at a distance.
		_add_box(vertices, normals, Vector3(x, y0, z), w, course_m * 1.02)
	_emit(vertices, normals, "Pyramid")
	# A pyramid is a landmark you navigate by AND a thing you can crash into.
	var body := StaticBody3D.new()
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# One box for the whole silhouette rather than per course: it is a solid mass
	# either way, and a fifteen-shape collider for scenery is not worth the tick.
	box.size = Vector3(half * 2.0, float(courses) * course_m, half * 2.0)
	shape.shape = box
	body.add_child(shape)
	body.global_position = Vector3(x, base + float(courses) * course_m * 0.5, z)


## A ruin field: broken wall segments on a rough rectangle, some fallen. Seeded,
## so the same ruin is the same ruin every time you fly past it — a landmark that
## rearranged itself would be worse than no landmark.
func _build_ruin(x: float, z: float, ruin_seed: int) -> void:
	_rng.seed = ruin_seed
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var half: float = _rng.randf_range(26.0, 44.0)
	var segments: int = _rng.randi_range(10, 18)
	for i: int in segments:
		# Walk the perimeter, leaving gaps: a complete rectangle reads as a
		# building, and a ruin is what is LEFT of one.
		if _rng.randf() < 0.28:
			continue
		var t: float = float(i) / float(segments) * TAU
		var wall_x: float = x + cos(t) * half
		var wall_z: float = z + sin(t) * half
		var courses: int = _rng.randi_range(1, 4)
		var w: float = _rng.randf_range(3.0, 7.0)
		var ground: float = terrain.height_at(wall_x, wall_z)
		for c: int in courses:
			_add_box(vertices, normals,
					Vector3(wall_x, ground + float(c) * course_m, wall_z),
					w * (1.0 - 0.12 * float(c)), course_m * 1.02)
	# A fallen column or two, lying where it dropped.
	for i: int in _rng.randi_range(1, 3):
		var cx: float = x + _rng.randf_range(-half, half)
		var cz: float = z + _rng.randf_range(-half, half)
		_add_box(vertices, normals,
				Vector3(cx, terrain.height_at(cx, cz) + course_m * 0.3, cz),
				_rng.randf_range(4.0, 9.0), course_m * 0.6)
	_emit(vertices, normals, "Ruin")


## The lowest ground under a footprint's four corners. A landmark planted at its
## CENTRE height floats on one side of a dune and buries itself on the other;
## planting at the lowest corner means it is only ever partly buried, which is
## what a real ruin looks like anyway.
func _lowest_corner(x: float, z: float, half: float) -> float:
	var lowest: float = INF
	for dx: float in [-half, half]:
		for dz: float in [-half, half]:
			lowest = minf(lowest, terrain.height_at(x + dx, z + dz))
	return lowest


func _add_box(vertices: PackedVector3Array, normals: PackedVector3Array,
		centre: Vector3, half: float, height: float) -> void:
	var x0: float = centre.x - half
	var x1: float = centre.x + half
	var z0: float = centre.z - half
	var z1: float = centre.z + half
	var y0: float = centre.y
	var y1: float = centre.y + height
	_add_quad(vertices, normals, Vector3(x0, y1, z0), Vector3(x0, y1, z1),
			Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.UP)
	_add_quad(vertices, normals, Vector3(x0, y0, z0), Vector3(x0, y1, z0),
			Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.LEFT)
	_add_quad(vertices, normals, Vector3(x1, y0, z1), Vector3(x1, y1, z1),
			Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.RIGHT)
	_add_quad(vertices, normals, Vector3(x1, y0, z0), Vector3(x1, y1, z0),
			Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3.FORWARD)
	_add_quad(vertices, normals, Vector3(x0, y0, z1), Vector3(x0, y1, z1),
			Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.BACK)


func _add_quad(vertices: PackedVector3Array, normals: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for point: Vector3 in [a, b, c, a, c, d]:
		vertices.append(point)
		normals.append(normal)


func _emit(vertices: PackedVector3Array, normals: PackedVector3Array,
		label: String) -> void:
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	if stone != null:
		instance.material_override = stone
	add_child(instance)
