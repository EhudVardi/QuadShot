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

const FOOTPRINT: float = 12.0
const INTERIOR_HEIGHT: float = 3.6
const WALL: float = 0.4
const BAR: float = 0.12
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
const SCAFFOLD_POST: float = 0.15
const SCAFFOLD_BEAM: float = 0.12
const WORK_LIGHT_ENERGY: float = 0.35

@export var state: StringName = STATE_OPEN
@export var leaf_id: StringName = &""
@export var label: String = ""
@export var window_size: Vector2 = Vector2(3.0, 2.2)
## Window bottom above the interior floor; 0 makes it a door (no bottom bar).
@export var sill: float = 0.6
@export var text_pixel: float = 0.1

var _mat_dark: StandardMaterial3D
var _mat_line: StandardMaterial3D
var _text: GlowText3D
var _light: OmniLight3D


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


## The side-view keyboard mode highlights the floor under the cursor: the
## glyphs flare and the interior wakes up. Closed floors have neither text nor
## light and are never selectable — the guards make set_selected a safe no-op.
func set_selected(on: bool) -> void:
	if _text != null:
		_text.glow_energy = TEXT_ENERGY_SELECTED if on else TEXT_ENERGY_IDLE
	if _light != null:
		_light.light_energy = LIGHT_ENERGY_SELECTED if on else LIGHT_ENERGY_IDLE


func _build_open() -> void:
	_mat_line = StandardMaterial3D.new()
	_mat_line.albedo_color = Color(0.05, 0.15, 0.25)
	_mat_line.emission_enabled = true
	_mat_line.emission = LINE_COLOR
	_mat_line.emission_energy_multiplier = LINE_ENERGY
	_build_walls()
	_build_window_line()
	_build_light()
	# Menu furniture — only on a real menu leaf. A world building's open floor
	# (no leaf) is a plain windowed, enterable floor: no label, commit zone or
	# exit chevrons, just an opening lit for ingress.
	if leaf_id != &"":
		_build_chevrons()
		_build_label()
		_build_zone()


## SEALED (B4): a full glazed facade with no opening. The silhouette stays
## solid so the pilot flies past, never into; the side walls match the open
## floors so a building's side profile is continuous. No light — glass, dark.
func _build_sealed() -> void:
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = SEALED_ALBEDO
	glass.metallic = 0.35
	glass.roughness = 0.45
	var mid_y: float = INTERIOR_HEIGHT * 0.5
	var z_wall: float = FOOTPRINT * 0.5 - WALL * 0.5
	for side: float in [1.0, -1.0]:
		_add_box(Vector3(FOOTPRINT, INTERIOR_HEIGHT, WALL),
				Vector3(0.0, mid_y, z_wall * side), glass, true)
	var side_len: float = FOOTPRINT - 2.0 * WALL
	for side: float in [1.0, -1.0]:
		_add_box(Vector3(WALL, INTERIOR_HEIGHT, side_len),
				Vector3((FOOTPRINT * 0.5 - WALL * 0.5) * side, mid_y, 0.0),
				_mat_dark, true)


## UNDER CONSTRUCTION (B4): no facade at all — a bare amber scaffold frame
## (corner posts + two perimeter rings) over the slab MenuBuilding already
## lays. Reads as honest texture, no entry (no window, label or zone).
func _build_under_construction() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = SCAFFOLD_ALBEDO
	mat.emission_enabled = true
	mat.emission = SCAFFOLD_COLOR
	mat.emission_energy_multiplier = SCAFFOLD_ENERGY
	var px: float = FOOTPRINT * 0.5 - WALL
	var mid_y: float = INTERIOR_HEIGHT * 0.5
	# Corner posts are the blockers; the ring beams are visual only.
	for sx: float in [1.0, -1.0]:
		for sz: float in [1.0, -1.0]:
			_add_box(Vector3(SCAFFOLD_POST, INTERIOR_HEIGHT, SCAFFOLD_POST),
					Vector3(px * sx, mid_y, px * sz), mat, true)
	for ring_y: float in [mid_y, INTERIOR_HEIGHT - SCAFFOLD_BEAM]:
		for sz: float in [1.0, -1.0]:
			_add_box(Vector3(2.0 * px, SCAFFOLD_BEAM, SCAFFOLD_BEAM),
					Vector3(0.0, ring_y, px * sz), mat, false)
		for sx: float in [1.0, -1.0]:
			_add_box(Vector3(SCAFFOLD_BEAM, SCAFFOLD_BEAM, 2.0 * px),
					Vector3(px * sx, ring_y, 0.0), mat, false)
	# A dim amber work-light so the skeleton reads at night.
	var work: OmniLight3D = OmniLight3D.new()
	work.position = Vector3(0.0, mid_y, 0.0)
	work.light_color = SCAFFOLD_COLOR
	work.light_energy = WORK_LIGHT_ENERGY
	work.omni_range = 7.0
	add_child(work)


func _build_walls() -> void:
	var w: float = window_size.x
	var h: float = window_size.y
	var pier_w: float = (FOOTPRINT - w) * 0.5
	var z_wall: float = FOOTPRINT * 0.5 - WALL * 0.5
	var mid_y: float = INTERIOR_HEIGHT * 0.5
	# Front and back walls carry the same opening — the far side is the
	# commit exit, crossed at full size.
	for side: float in [1.0, -1.0]:
		var z: float = z_wall * side
		_add_box(Vector3(pier_w, INTERIOR_HEIGHT, WALL),
				Vector3(-(w * 0.5 + pier_w * 0.5), mid_y, z), _mat_dark, true)
		_add_box(Vector3(pier_w, INTERIOR_HEIGHT, WALL),
				Vector3(w * 0.5 + pier_w * 0.5, mid_y, z), _mat_dark, true)
		if sill > 0.01:
			_add_box(Vector3(w, sill, WALL),
					Vector3(0.0, sill * 0.5, z), _mat_dark, true)
		var header_h: float = INTERIOR_HEIGHT - sill - h
		if header_h > 0.01:
			_add_box(Vector3(w, header_h, WALL),
					Vector3(0.0, sill + h + header_h * 0.5, z), _mat_dark, true)
	var side_len: float = FOOTPRINT - 2.0 * WALL
	for side: float in [1.0, -1.0]:
		_add_box(Vector3(WALL, INTERIOR_HEIGHT, side_len),
				Vector3((FOOTPRINT * 0.5 - WALL * 0.5) * side, mid_y, 0.0),
				_mat_dark, true)


func _build_window_line() -> void:
	var w: float = window_size.x
	var h: float = window_size.y
	var z: float = FOOTPRINT * 0.5 + 0.08
	var center_y: float = sill + h * 0.5
	_add_box(Vector3(w + 2.0 * BAR, BAR, BAR),
			Vector3(0.0, sill + h + BAR * 0.5, z), _mat_line, false)
	if sill > 0.01:
		_add_box(Vector3(w + 2.0 * BAR, BAR, BAR),
				Vector3(0.0, sill - BAR * 0.5, z), _mat_line, false)
	for side: float in [1.0, -1.0]:
		_add_box(Vector3(BAR, h, BAR),
				Vector3((w * 0.5 + BAR * 0.5) * side, center_y, z), _mat_line, false)


## Chevrons marching toward the far window on the floor AND the ceiling
## (v1.42 — the arrow experiment retired at the user's call): the exit
## vector is readable whichever surface the pilot's eye hugs. Runway
## markings in the navigation palette, flat, never obstacles.
func _build_chevrons() -> void:
	for surface_y: float in [0.05, INTERIOR_HEIGHT - 0.05]:
		for tip_z: float in [2.0, 0.0, -2.0]:
			for arm: float in [1.0, -1.0]:
				_add_box(Vector3(BAR, 0.04, 1.2),
						Vector3(0.42 * arm, surface_y, tip_z + 0.42), _mat_line, false,
						arm * deg_to_rad(45.0))


## The interior light — every open floor gets one so the window reads as lit
## ingress. Cyan (navigation palette); flares when a menu floor is selected.
func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 2.8, 0.0)
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
			FOOTPRINT * 0.5 - WALL * 0.5)
	add_child(_text)


func _build_zone() -> void:
	var zone: MenuFloor = MenuFloor.new()
	zone.leaf_id = leaf_id
	zone.position = Vector3(0.0, INTERIOR_HEIGHT * 0.5, 0.0)
	var shape: BoxShape3D = BoxShape3D.new()
	var side_len: float = FOOTPRINT - 2.0 * WALL
	shape.size = Vector3(side_len, INTERIOR_HEIGHT, side_len)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	zone.add_child(collision)
	add_child(zone)
	zone.entered.connect(func(id: StringName) -> void: entered.emit(id))
	zone.committed.connect(func(id: StringName) -> void: committed.emit(id))
	zone.canceled.connect(func(id: StringName) -> void: canceled.emit(id))


func _add_box(size: Vector3, at: Vector3, material: Material, solid: bool,
		yaw: float = 0.0) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = at
	mesh_instance.rotation = Vector3(0.0, yaw, 0.0)
	add_child(mesh_instance)
	if solid:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		collision.position = at
		collision.rotation = Vector3(0.0, yaw, 0.0)
		add_child(collision)
