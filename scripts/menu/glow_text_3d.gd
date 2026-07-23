class_name GlowText3D
extends Node3D

## Neon glyphs built from primitives (GAMEPLAY-DESIGN B5's window text, and
## the seed of B8's word chains): a 5x7 dot-matrix font rendered as one
## MultiMesh of emissive cubes, centered on this node's origin, facing +Z.
## No font assets, no collision — text readable at range that the drone
## flies straight through. Multi-line via "\n". Unknown characters render as
## hollow boxes so a typo shows up on screen instead of vanishing.

const GLYPH_COLS: int = 5
const GLYPH_ROWS: int = 7
## Horizontal advance per character and vertical advance per line, in font
## pixels (glyph size plus one pixel of spacing).
const CHAR_PITCH: int = 6
const LINE_PITCH: int = 8
## Cube edge as a fraction of pixel_size — the gap makes letters read as
## dot-matrix neon instead of merged slabs.
const CUBE_FILL: float = 0.85

const UNKNOWN_GLYPH: Array = [0b11111, 0b10001, 0b10001, 0b10001, 0b10001,
		0b10001, 0b11111]

## 5x7 rows top-to-bottom, bit 4 = leftmost column.
const FONT: Dictionary = {
	" ": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000],
	"A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
	"B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
	"C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
	"D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
	"E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
	"F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
	"G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
	"H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
	"I": [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
	"J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
	"K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
	"L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
	"M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
	"N": [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
	"O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
	"P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
	"Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
	"R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
	"S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
	"T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
	"U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
	"V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
	"W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001],
	"X": [0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b01010, 0b10001],
	"Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
	"Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
}

@export var text: String = "":
	set(value):
		text = value
		if is_inside_tree():
			_rebuild()
@export var pixel_size: float = 0.1
@export var glow_color: Color = Color(0.2, 0.7, 1.0)
## Live-settable without a rebuild — the side-view selection highlight
## breathes through this.
@export var glow_energy: float = 3.5:
	set(value):
		glow_energy = value
		if _material != null:
			_material.emission_energy_multiplier = value

var _instance: MultiMeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _instance != null:
		_instance.queue_free()
		_instance = null
	var offsets: PackedVector3Array = _pixel_offsets()
	if offsets.is_empty():
		return
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.02, 0.05, 0.08)
	_material.emission_enabled = true
	_material.emission = glow_color
	_material.emission_energy_multiplier = glow_energy
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE * pixel_size * CUBE_FILL
	cube.material = _material
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cube
	multimesh.instance_count = offsets.size()
	for i: int in offsets.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, offsets[i]))
	_instance = MultiMeshInstance3D.new()
	_instance.multimesh = multimesh
	add_child(_instance)


func _pixel_offsets() -> PackedVector3Array:
	var offsets: PackedVector3Array = PackedVector3Array()
	var lines: PackedStringArray = text.split("\n")
	var total_rows: int = lines.size() * LINE_PITCH - 1
	for li: int in lines.size():
		var line: String = lines[li]
		if line.is_empty():
			continue
		var width_px: int = line.length() * CHAR_PITCH - 1
		for ci: int in line.length():
			var glyph: Array = FONT.get(line[ci].to_upper(), UNKNOWN_GLYPH)
			for row: int in GLYPH_ROWS:
				var bits: int = glyph[row]
				for col: int in GLYPH_COLS:
					if bits & (1 << (GLYPH_COLS - 1 - col)) == 0:
						continue
					var px: float = (ci * CHAR_PITCH + col - (width_px - 1) * 0.5) \
							* pixel_size
					var py: float = ((total_rows - 1) * 0.5 - (li * LINE_PITCH + row)) \
							* pixel_size
					offsets.append(Vector3(px, py, 0.0))
	return offsets
