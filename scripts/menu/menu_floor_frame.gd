class_name MenuFloorFrame
extends StaticBody3D

## One open floor of the menu tower, built parametrically at _ready
## (GAMEPLAY-DESIGN B5, step 3). NOT the B3 generator — no seeds, no rooms,
## no furniture: five of these sit in menu_tower.tscn with hand-chosen
## window sizes (the v1.38 ESCALATING GAPS steering), and the parameters
## keep the .tscn diff-readable where five copies of box-and-collision
## soup would not be. GlowText3D set the precedent for code-built meshes.
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
## The volumetric exit arrow's gentle pulse — a guide reads as light, not
## as a solid you might clip.
const ARROW_ENERGY_BASE: float = 2.6
const ARROW_ENERGY_SWING: float = 0.8
const ARROW_PULSE_HZ: float = 0.6

@export var leaf_id: StringName = &""
@export var label: String = ""
@export var window_size: Vector2 = Vector2(3.0, 2.2)
## Window bottom above the interior floor; 0 makes it a door (no bottom bar).
@export var sill: float = 0.6
@export var text_pixel: float = 0.1

var _mat_dark: StandardMaterial3D
var _mat_line: StandardMaterial3D
var _mat_arrow: StandardMaterial3D
var _text: GlowText3D
var _light: OmniLight3D
var _pulse_t: float = 0.0


func _ready() -> void:
	_mat_dark = StandardMaterial3D.new()
	_mat_dark.albedo_color = INTERIOR_ALBEDO
	_mat_dark.roughness = 0.9
	_mat_line = StandardMaterial3D.new()
	_mat_line.albedo_color = Color(0.05, 0.15, 0.25)
	_mat_line.emission_enabled = true
	_mat_line.emission = LINE_COLOR
	_mat_line.emission_energy_multiplier = LINE_ENERGY
	_build_walls()
	_build_window_line()
	_build_chevrons()
	_build_arrow()
	_build_text_and_light()
	_build_zone()


func _process(delta: float) -> void:
	_pulse_t += delta
	_mat_arrow.emission_energy_multiplier = ARROW_ENERGY_BASE \
			+ ARROW_ENERGY_SWING * sin(_pulse_t * TAU * ARROW_PULSE_HZ)


## The side-view keyboard mode highlights the floor under the cursor: the
## glyphs flare and the interior wakes up.
func set_selected(on: bool) -> void:
	_text.glow_energy = TEXT_ENERGY_SELECTED if on else TEXT_ENERGY_IDLE
	_light.light_energy = LIGHT_ENERGY_SELECTED if on else LIGHT_ENERGY_IDLE


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


## Floor chevrons marching toward the far window — the exit-vector hint the
## checkpoint 2 flight asked for. In the navigation palette, low and flat so
## they read as runway markings, not obstacles.
func _build_chevrons() -> void:
	for tip_z: float in [2.0, 0.0, -2.0]:
		for arm: float in [1.0, -1.0]:
			_add_box(Vector3(BAR, 0.04, 1.2),
					Vector3(0.42 * arm, 0.05, tip_z + 0.42), _mat_line, false,
					arm * deg_to_rad(45.0))


## The volumetric exit arrow (v1.40, moved INTO the window at v1.41 — the
## user's correction): it hangs in the aperture itself, tail at the window
## plane, body reaching inward along the exit trajectory — so just LOOKING
## at the window from outside names the line to fly, before ingress. The
## label glyphs float in front of it at the plane; both are flown through.
## No collision; it pulses so it reads as light, not a solid.
func _build_arrow() -> void:
	_mat_arrow = StandardMaterial3D.new()
	_mat_arrow.albedo_color = Color(0.04, 0.1, 0.16)
	_mat_arrow.emission_enabled = true
	_mat_arrow.emission = LINE_COLOR
	_mat_arrow.emission_energy_multiplier = ARROW_ENERGY_BASE
	var arrow_y: float = sill + window_size.y * 0.5
	var plane_z: float = FOOTPRINT * 0.5 - WALL
	var shaft: MeshInstance3D = MeshInstance3D.new()
	var shaft_mesh: BoxMesh = BoxMesh.new()
	shaft_mesh.size = Vector3(0.3, 0.3, 2.2)
	shaft_mesh.material = _mat_arrow
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, arrow_y, plane_z - 1.1)
	add_child(shaft)
	var head: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.7
	head_mesh.height = 1.0
	head_mesh.material = _mat_arrow
	head.mesh = head_mesh
	# Cylinder axis is +Y; -90 deg about X points the tip down local -Z, the
	# exit direction.
	head.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	head.position = Vector3(0.0, arrow_y, plane_z - 2.2 - 0.5)
	add_child(head)


func _build_text_and_light() -> void:
	_text = GlowText3D.new()
	_text.text = label
	_text.pixel_size = text_pixel
	_text.position = Vector3(0.0, sill + window_size.y * 0.5,
			FOOTPRINT * 0.5 - WALL * 0.5)
	add_child(_text)
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 2.8, 0.0)
	_light.light_color = Color(0.35, 0.8, 1.0)
	_light.light_energy = LIGHT_ENERGY_IDLE
	_light.omni_range = 8.0
	add_child(_light)


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
