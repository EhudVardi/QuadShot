class_name MenuFloorFrame
extends StaticBody3D

## One floor of a building, built parametrically at _ready (GAMEPLAY-DESIGN
## B5 step 3; enterability states added for B3/B4). The `state` picks the
## geometry: OPEN is a fly-through window with a neon window-line — a menu
## leaf adds the label, exit chevrons and a MenuFloor commit zone, while a
## world building's leafless open floor stays just windowed and enterable
## (v1.47, the menu→world bridge); SEALED is a solid glazed facade (no
## opening, no zone — flown past, never into); UNDER_CONSTRUCTION is a bare
## amber scaffold frame (no facade, no entry). Closed floors fill a building's
## silhouette so a two-option submenu still reads as real architecture
## (v1.44). GlowText3D set the precedent for code-built meshes.
##
## Origin sits at the interior floor's top center; the interior spans local
## y 0..3.6 inside a 12x12 footprint with 0.4-thick walls. The entry window
## (front, +Z) carries the emissive window-line and the fly-through label;
## the far side gets the same opening for commit-on-exit; chevrons on the
## floor point the exit vector (checkpoint 2's ask).

signal entered(leaf_id: StringName)
signal committed(leaf_id: StringName)
signal canceled(leaf_id: StringName)

const WALL: float = 0.4
const BAR: float = 0.12
## Minimum wall pier beside a window; the window width is clamped so even a
## narrow footprint still frames its opening (B3 variety — footprints vary).
const MIN_PIER: float = 0.4
## Interior surfaces sit near-black so the flat ambient term cannot wash out
## the dark — the "genuinely dark inside" half of B2's drama (v1.38 verdict:
## more dramatic).
const INTERIOR_ALBEDO: Color = Color(0.03, 0.035, 0.045)
const LINE_COLOR: Color = Color(0.2, 0.7, 1.0)
const LINE_ENERGY: float = 3.5
const TEXT_ENERGY_IDLE: float = 3.5
const TEXT_ENERGY_SELECTED: float = 7.0
const LIGHT_ENERGY_IDLE: float = 0.4
const LIGHT_ENERGY_SELECTED: float = 1.4

## Enterability (B4): only OPEN floors get a window, a label and a commit
## zone; the closed states fill the silhouette (v1.44's "fill it, don't
## shrink the gap"). The floor-spec dict carries these as `&"..."`.
const STATE_OPEN: StringName = &"open"
const STATE_SEALED: StringName = &"sealed"
const STATE_UNDER_CONSTRUCTION: StringName = &"under_construction"

## Sealed = tinted dark glass, lights off. Under-construction = amber scaffold
## in the course/pylon palette; energy >1 so it clears the 1.0 bloom threshold.
const SEALED_ALBEDO: Color = Color(0.05, 0.08, 0.13)
const SCAFFOLD_ALBEDO: Color = Color(0.08, 0.06, 0.04)
const SCAFFOLD_COLOR: Color = Color(1.0, 0.55, 0.1)
const SCAFFOLD_ENERGY: float = 2.0
## Structural columns carry the load; beams are the belts/joists between them.
const SCAFFOLD_COLUMN: float = 0.3
const SCAFFOLD_BEAM: float = 0.12
const WORK_LIGHT_ENERGY: float = 0.35
## Load-bearing columns stand on a grid roughly this far apart (perimeter AND
## interior), so the slab above is visibly supported — nothing floats.
const SCAFFOLD_COLUMN_SPACING: float = 8.0
const SCAFFOLD_RINGS: int = 4
## Faint mullion grid on sealed glass so a closed floor reads as a glazed
## curtain wall, not a blank slab. Dim (energy <1 → no bloom), grid ~4 m.
const MULLION: float = 0.08
const MULLION_COLOR: Color = Color(0.3, 0.45, 0.6)
const MULLION_ENERGY: float = 0.9
const MULLION_SPACING: float = 4.0

## The four faces as [along_z, side] for per-side openings (v1.62), indexed to
## match open_sides: 0 front (+Z), 1 back (-Z), 2 right (+X), 3 left (-X).
const SIDES: Array = [[true, 1.0], [true, -1.0], [false, 1.0], [false, -1.0]]

@export var state: StringName = STATE_OPEN
@export var leaf_id: StringName = &""
@export var label: String = ""
@export var window_size: Vector2 = Vector2(3.0, 2.2)
## Window bottom above the interior floor; 0 makes it a door (no bottom bar).
@export var sill: float = 0.6
@export var text_pixel: float = 0.1
## Per-floor footprint (B3 variety, v1.48): MenuBuilding sets it from the floor
## spec so buildings vary in width and can set back. Default matches the menu.
@export var footprint: float = 12.0
## Openings on all four sides, not just front/back (v1.48). A world building
## floor is enterable from any direction; the menu keeps front-entry /
## back-commit with solid sides (false).
@export var cross_windows: bool = false
## Per-side openings (v1.62): 4 bools [front +Z, back -Z, right +X, left -X] —
## each side open (windowed) or solid. World buildings set this to open only the
## sides facing the downtown core (the "less central a side, the less entrance"
## rule). Empty = the legacy path below (front/back open, sides per cross_windows),
## which the menu uses.
@export var open_sides: Array = []
## Interior (floor-to-ceiling) height (v1.50): MenuBuilding sets it per floor
## and derives the floor pitch from it, so buildings vary in floor height.
## Default matches the menu.
@export var interior_height: float = 3.6
## Interior (B3): the InteriorGenerator spec + district for palette. Empty = no
## interior (menu floors, sealed/UC floors). When interior_lod_managed is true,
## WorldBuilding drives build_interior()/clear_interior() by distance (city LOD);
## when false, the interior builds at _ready (menu / dev-room specimen).
@export var interior: Dictionary = {}
@export var district: int = -1
@export var interior_lod_managed: bool = false

var _mat_dark: StandardMaterial3D
var _mat_line: StandardMaterial3D
var _text: GlowText3D
var _light: OmniLight3D
## Batches this floor's boxes into one mesh per material (v1.57 perf pass), so a
## floor is ~1–2 draw calls instead of dozens. Collision stays per box.
var _batch: BoxBatcher = BoxBatcher.new()
## The B3 interior subtree (one child, freeable for distance LOD); null until built.
var _interior_root: Node3D = null


func _ready() -> void:
	_mat_dark = StandardMaterial3D.new()
	_mat_dark.albedo_color = INTERIOR_ALBEDO
	_mat_dark.roughness = 0.9
	match state:
		STATE_SEALED:
			_build_sealed()
		STATE_UNDER_CONSTRUCTION:
			_build_under_construction()
		_:
			_build_open()
	_batch.commit_into(self)


## The side-view keyboard mode highlights the floor under the cursor: the
## glyphs flare and the interior wakes up. Closed floors have neither text nor
## light and are never selectable — the guards make set_selected a safe no-op.
func set_selected(on: bool) -> void:
	if _text != null:
		_text.glow_energy = TEXT_ENERGY_SELECTED if on else TEXT_ENERGY_IDLE
	if _light != null:
		_light.light_energy = LIGHT_ENERGY_SELECTED if on else LIGHT_ENERGY_IDLE


## True if this floor carries a B3 interior spec (open world-building floors).
func has_interior() -> bool:
	return not interior.is_empty()


## Build the interior subtree once (idempotent). Used at _ready and by the city
## LOD manager on approach.
func build_interior() -> void:
	if _interior_root != null or interior.is_empty():
		return
	_interior_root = InteriorBuilder.build(interior, district, self, interior_height)


## Free the interior subtree (LOD, out of range). Deterministic to rebuild.
func clear_interior() -> void:
	if _interior_root != null:
		_interior_root.queue_free()
		_interior_root = null


func _build_open() -> void:
	_mat_line = StandardMaterial3D.new()
	_mat_line.albedo_color = Color(0.05, 0.15, 0.25)
	_mat_line.emission_enabled = true
	_mat_line.emission = LINE_COLOR
	_mat_line.emission_energy_multiplier = LINE_ENERGY
	# A narrow footprint can't fit a wide window and still leave piers — clamp
	# the width so the opening always has a wall either side.
	window_size.x = minf(window_size.x, footprint - 2.0 * (WALL + MIN_PIER))
	_build_walls()
	_build_window_line()
	# Menu furniture — only on a real menu leaf. A world building's open floor
	# (no leaf) is a plain windowed, enterable floor: no label, commit zone or
	# exit chevrons. It also skips the per-floor interior light (that scales to
	# many open floors), lit instead by the environment through its openings;
	# the menu keeps its dramatic light for selection feedback.
	if leaf_id != &"":
		_build_light()
		_build_chevrons()
		_build_label()
		_build_zone()
	# B3 interior: build now unless the city LOD manager will drive it by distance.
	if not interior.is_empty() and not interior_lod_managed:
		build_interior()


## SEALED (B4): a closed glass box — flown past, never into. All four faces
## are glazed and carry a faint mullion grid so a closed floor reads as a
## curtain wall, not a blank slab (the user's "make closed floors interesting").
## No light — dark glass.
func _build_sealed() -> void:
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = SEALED_ALBEDO
	glass.metallic = 0.35
	glass.roughness = 0.45
	var grid: StandardMaterial3D = StandardMaterial3D.new()
	grid.albedo_color = MULLION_COLOR
	grid.emission_enabled = true
	grid.emission = MULLION_COLOR
	grid.emission_energy_multiplier = MULLION_ENERGY
	var mid_y: float = interior_height * 0.5
	var wall: float = footprint * 0.5 - WALL * 0.5
	var side_len: float = footprint - 2.0 * WALL
	# Front / back span the full width; sides fit between them.
	for side: float in [1.0, -1.0]:
		_add_box(_axis_size(true, footprint, interior_height, WALL),
				_axis_pos(true, 0.0, mid_y, wall * side), glass, true)
		_add_box(_axis_size(false, side_len, interior_height, WALL),
				_axis_pos(false, 0.0, mid_y, wall * side), glass, true)
		_build_facade_grid(true, side, footprint, grid)
		_build_facade_grid(false, side, side_len, grid)


## A curtain-wall grid on one sealed face: vertical mullions every ~4 m plus a
## horizontal band at mid height, laid just outside the glass.
func _build_facade_grid(along_z: bool, side: float, span: float,
		mat: Material) -> void:
	var depth: float = (footprint * 0.5 + 0.05) * side
	var divisions: int = maxi(2, int(round(span / MULLION_SPACING)))
	for i: int in range(1, divisions):
		var a: float = -span * 0.5 + span * float(i) / float(divisions)
		_add_box(_axis_size(along_z, MULLION, interior_height, MULLION),
				_axis_pos(along_z, a, interior_height * 0.5, depth), mat, false)
	_add_box(_axis_size(along_z, span, MULLION, MULLION),
			_axis_pos(along_z, 0.0, interior_height * 0.5, depth), mat, false)


## UNDER CONSTRUCTION (B4): an amber structural skeleton over the slab. A full
## GRID of floor-to-ceiling columns (perimeter AND interior) carries the slab
## above, with ring beams up the height and a joist grid just under the ceiling
## where that slab lands — so the mass above is visibly SUPPORTED, never
## floating (the user's ask). No facade, no entry.
func _build_under_construction() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = SCAFFOLD_ALBEDO
	mat.emission_enabled = true
	mat.emission = SCAFFOLD_COLOR
	mat.emission_energy_multiplier = SCAFFOLD_ENERGY
	var px: float = footprint * 0.5 - WALL
	var mid_y: float = interior_height * 0.5
	var segments: int = maxi(2, int(round(2.0 * px / SCAFFOLD_COLUMN_SPACING)))
	# Load-bearing columns on a full grid — the vertical load path, and the
	# blockers (nothing enters a floor under construction).
	for ix: int in segments + 1:
		var gx: float = -px + 2.0 * px * float(ix) / float(segments)
		for iz: int in segments + 1:
			var gz: float = -px + 2.0 * px * float(iz) / float(segments)
			_add_box(Vector3(SCAFFOLD_COLUMN, interior_height, SCAFFOLD_COLUMN),
					Vector3(gx, mid_y, gz), mat, true)
	# Perimeter ring beams (belts) up the height.
	for level: int in range(1, SCAFFOLD_RINGS + 1):
		var ry: float = interior_height * float(level) / float(SCAFFOLD_RINGS)
		for side: float in [1.0, -1.0]:
			_add_box(Vector3(2.0 * px, SCAFFOLD_BEAM, SCAFFOLD_BEAM),
					Vector3(0.0, ry, px * side), mat, false)
			_add_box(Vector3(SCAFFOLD_BEAM, SCAFFOLD_BEAM, 2.0 * px),
					Vector3(px * side, ry, 0.0), mat, false)
	# Joists across the column grid just under the ceiling, where the slab above
	# lands — the load path made legible.
	var top_y: float = interior_height - SCAFFOLD_BEAM
	for ix: int in segments + 1:
		var g: float = -px + 2.0 * px * float(ix) / float(segments)
		_add_box(Vector3(SCAFFOLD_BEAM, SCAFFOLD_BEAM, 2.0 * px),
				Vector3(g, top_y, 0.0), mat, false)
		_add_box(Vector3(2.0 * px, SCAFFOLD_BEAM, SCAFFOLD_BEAM),
				Vector3(0.0, top_y, g), mat, false)
	# A dim amber work-light so the skeleton reads at night.
	var work: OmniLight3D = OmniLight3D.new()
	work.position = Vector3(0.0, mid_y, 0.0)
	work.light_color = SCAFFOLD_COLOR
	work.light_energy = WORK_LIGHT_ENERGY
	work.omni_range = 7.0
	add_child(work)


func _build_walls() -> void:
	# Directional (world buildings, v1.62): open the core-facing sides, seal the
	# rest — the "less central a side, the less entrance" rule.
	if not open_sides.is_empty():
		for i: int in SIDES.size():
			if open_sides[i]:
				_build_opened_wall(SIDES[i][0], SIDES[i][1])
			else:
				_build_solid_wall(SIDES[i][0], SIDES[i][1])
		return
	# Legacy (menu): front and back always open (entry + commit crossing); the
	# crossed sides open only with cross_windows, else stay solid.
	_build_opened_wall(true, 1.0)
	_build_opened_wall(true, -1.0)
	if cross_windows:
		_build_opened_wall(false, 1.0)
		_build_opened_wall(false, -1.0)
	else:
		_build_solid_wall(false, 1.0)
		_build_solid_wall(false, -1.0)


## A solid wall on one face (no opening). Front/back (along_z) span the full
## footprint; the side walls fit between them (inset by a wall thickness each
## end), so faces meet cleanly at the corners.
func _build_solid_wall(along_z: bool, side: float) -> void:
	var span: float = footprint if along_z else footprint - 2.0 * WALL
	var depth: float = (footprint * 0.5 - WALL * 0.5) * side
	_add_box(_axis_size(along_z, span, interior_height, WALL),
			_axis_pos(along_z, 0.0, interior_height * 0.5, depth), _mat_dark, true)


## One wall with a centered window opening: two flanking piers, a sill below
## and a header above. `along_z` walls run along X (their face is ±Z); else
## they run along Z (face ±X). `side` is which of the two faces.
func _build_opened_wall(along_z: bool, side: float) -> void:
	var w: float = window_size.x
	var h: float = window_size.y
	var pier_w: float = (footprint - w) * 0.5
	var depth: float = (footprint * 0.5 - WALL * 0.5) * side
	var mid_y: float = interior_height * 0.5
	for pier: float in [1.0, -1.0]:
		_add_box(_axis_size(along_z, pier_w, interior_height, WALL),
				_axis_pos(along_z, (w * 0.5 + pier_w * 0.5) * pier, mid_y, depth),
				_mat_dark, true)
	if sill > 0.01:
		_add_box(_axis_size(along_z, w, sill, WALL),
				_axis_pos(along_z, 0.0, sill * 0.5, depth), _mat_dark, true)
	var header_h: float = interior_height - sill - h
	if header_h > 0.01:
		_add_box(_axis_size(along_z, w, header_h, WALL),
				_axis_pos(along_z, 0.0, sill + h + header_h * 0.5, depth),
				_mat_dark, true)


func _build_window_line() -> void:
	# Directional (v1.62): frame exactly the open sides.
	if not open_sides.is_empty():
		for i: int in SIDES.size():
			if open_sides[i]:
				_build_window_line_side(SIDES[i][0], SIDES[i][1])
		return
	# Legacy: front always framed; a cross-windowed floor frames all four.
	_build_window_line_side(true, 1.0)
	if cross_windows:
		_build_window_line_side(true, -1.0)
		_build_window_line_side(false, 1.0)
		_build_window_line_side(false, -1.0)


func _build_window_line_side(along_z: bool, side: float) -> void:
	var w: float = window_size.x
	var h: float = window_size.y
	var depth: float = (footprint * 0.5 + 0.08) * side
	var center_y: float = sill + h * 0.5
	_add_box(_axis_size(along_z, w + 2.0 * BAR, BAR, BAR),
			_axis_pos(along_z, 0.0, sill + h + BAR * 0.5, depth), _mat_line, false)
	if sill > 0.01:
		_add_box(_axis_size(along_z, w + 2.0 * BAR, BAR, BAR),
				_axis_pos(along_z, 0.0, sill - BAR * 0.5, depth), _mat_line, false)
	for bar: float in [1.0, -1.0]:
		_add_box(_axis_size(along_z, BAR, h, BAR),
				_axis_pos(along_z, (w * 0.5 + BAR * 0.5) * bar, center_y, depth),
				_mat_line, false)


## Box size for a wall-aligned member: `span` runs along the wall, `height` is
## vertical, `thick` is the depth through the wall. Swaps X/Z by orientation.
func _axis_size(along_z: bool, span: float, height: float, thick: float) -> Vector3:
	return Vector3(span, height, thick) if along_z else Vector3(thick, height, span)


## Position for a wall-aligned member: `along` is the offset down the wall, `y`
## vertical, `depth` the placement on the wall's outward axis.
func _axis_pos(along_z: bool, along: float, y: float, depth: float) -> Vector3:
	return Vector3(along, y, depth) if along_z else Vector3(depth, y, along)


## Chevrons marching toward the far window on the floor AND the ceiling
## (v1.42 — the arrow experiment retired at the user's call): the exit
## vector is readable whichever surface the pilot's eye hugs. Runway
## markings in the navigation palette, flat, never obstacles.
func _build_chevrons() -> void:
	for surface_y: float in [0.05, interior_height - 0.05]:
		for tip_z: float in [2.0, 0.0, -2.0]:
			for arm: float in [1.0, -1.0]:
				_add_box(Vector3(BAR, 0.04, 1.2),
						Vector3(0.42 * arm, surface_y, tip_z + 0.42), _mat_line, false,
						arm * deg_to_rad(45.0))


## The interior light — every open floor gets one so the window reads as lit
## ingress. Cyan (navigation palette); flares when a menu floor is selected.
func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, interior_height * 0.78, 0.0)
	_light.light_color = Color(0.35, 0.8, 1.0)
	_light.light_energy = LIGHT_ENERGY_IDLE
	_light.omni_range = 8.0
	add_child(_light)


## The neon fly-through label above the window — menu floors only.
func _build_label() -> void:
	_text = GlowText3D.new()
	_text.text = label
	_text.pixel_size = text_pixel
	_text.position = Vector3(0.0, sill + window_size.y * 0.5,
			footprint * 0.5 - WALL * 0.5)
	add_child(_text)


func _build_zone() -> void:
	var zone: MenuFloor = MenuFloor.new()
	zone.leaf_id = leaf_id
	zone.position = Vector3(0.0, interior_height * 0.5, 0.0)
	var shape: BoxShape3D = BoxShape3D.new()
	var side_len: float = footprint - 2.0 * WALL
	shape.size = Vector3(side_len, interior_height, side_len)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	zone.add_child(collision)
	add_child(zone)
	zone.entered.connect(func(id: StringName) -> void: entered.emit(id))
	zone.committed.connect(func(id: StringName) -> void: committed.emit(id))
	zone.canceled.connect(func(id: StringName) -> void: canceled.emit(id))


func _add_box(size: Vector3, at: Vector3, material: Material, solid: bool,
		yaw: float = 0.0) -> void:
	# Visual mesh is batched by material (committed once in _ready); only the
	# collision shape is a per-box node.
	_batch.add(size, at, material, yaw)
	if solid:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		collision.position = at
		collision.rotation = Vector3(0.0, yaw, 0.0)
		add_child(collision)
