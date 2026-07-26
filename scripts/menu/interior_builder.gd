class_name InteriorBuilder
extends RefCounted

## Renders an InteriorGenerator spec into a fresh "Interior" child subtree under a
## MenuFloorFrame (spec §3/§6). Visual boxes batch by material (one BoxBatcher);
## collision is per box. Returned root is freeable for distance LOD. The furniture
## KIT lives here: each kind -> greybox boxes. Variety is combination, not assets.

const COLUMN_W: float = InteriorGenerator.COLUMN_W


## Build the spec under `parent`. Returns the "Interior" root so the caller can free
## it (LOD). Columns are full-height structure; pieces are the scatter.
static func build(spec: Dictionary, district: int, parent: Node3D,
		interior_height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Interior"
	var body := StaticBody3D.new()
	root.add_child(body)
	var batch := BoxBatcher.new()
	var mats: Dictionary = _palette(district)
	for c: Vector2 in spec.get("columns", []):
		_box(batch, body, Vector3(COLUMN_W, interior_height, COLUMN_W),
				Vector3(c.x, interior_height * 0.5, c.y), 0.0, mats["structure"])
	for p: Dictionary in spec.get("pieces", []):
		_emit(batch, body, p, mats)
	_wayfinding(batch, spec)
	batch.commit_into(body)
	parent.add_child(root)
	return root


## A faint emissive strip on the floor down each keep-clear channel — the neon line
## that "shines the way" (spec §8). Interior-local; visual only (no collision).
## Channels run window->hub and are axis-aligned, so no rotation is needed.
static func _wayfinding(batch: BoxBatcher, spec: Dictionary) -> void:
	var guide := StandardMaterial3D.new()
	guide.albedo_color = MenuFloorFrame.LINE_COLOR
	guide.emission_enabled = true
	guide.emission = MenuFloorFrame.LINE_COLOR
	guide.emission_energy_multiplier = MenuFloorFrame.LINE_ENERGY * 0.5
	for ch: Dictionary in spec.get("channels", []):
		var a: Vector2 = ch["a"]           # window centre; hub is the origin
		var mid: Vector2 = a * 0.5
		var length: float = a.length()
		if absf(a.x) < 0.001:              # front/back window -> strip along Z
			batch.add(Vector3(0.18, 0.04, length), Vector3(mid.x, 0.02, mid.y), guide)
		else:                              # right/left window -> strip along X
			batch.add(Vector3(length, 0.04, 0.18), Vector3(mid.x, 0.02, mid.y), guide)


## Interior palette by district — reuses CityLayout's zonal colours so inside and
## outside agree. Interior surfaces stay dark; accents glow (bloom > 1.0).
static func _palette(district: int) -> Dictionary:
	var structure := StandardMaterial3D.new()
	structure.albedo_color = MenuFloorFrame.INTERIOR_ALBEDO * 1.6
	structure.roughness = 0.9
	var prop := StandardMaterial3D.new()
	prop.roughness = 0.9
	var accent := StandardMaterial3D.new()
	accent.emission_enabled = true
	match district:
		BuildingProgram.CYBER:
			prop.albedo_color = CityLayout.CYBER_BASE_COLOR
			accent.albedo_color = CityLayout.CYBER_GLOW_COLOR
			accent.emission = CityLayout.CYBER_GLOW_COLOR
			accent.emission_energy_multiplier = CityLayout.CYBER_GLOW_ENERGY
		BuildingProgram.URBAN:
			prop.albedo_color = CityLayout.HARDSCAPE_COLOR
			accent.albedo_color = CityLayout.HARDSCAPE_SIGN_COLOR
			accent.emission = CityLayout.HARDSCAPE_SIGN_COLOR
			accent.emission_energy_multiplier = CityLayout.HARDSCAPE_SIGN_ENERGY
		_:
			prop.albedo_color = CityLayout.PLANTER_COLOR
			accent.albedo_color = CityLayout.TREE_LEAF_COLOR
			accent.emission = CityLayout.TREE_LEAF_COLOR
			accent.emission_energy_multiplier = 1.2
	return {"structure": structure, "prop": prop, "accent": accent}


## One box: batched visual + a per-box collision shape under `body`.
static func _box(batch: BoxBatcher, body: StaticBody3D, size: Vector3, at: Vector3,
		yaw: float, mat: Material) -> void:
	batch.add(size, at, mat, yaw)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at
	col.rotation = Vector3(0.0, yaw, 0.0)
	body.add_child(col)


## Expand a piece into boxes. OFFICE kit here (Beat 2); Beat 3 adds the rest.
## Positions are local to `at`; the piece's yaw rotates each box.
static func _emit(batch: BoxBatcher, body: StaticBody3D, p: Dictionary,
		mats: Dictionary) -> void:
	var kind: StringName = p["kind"]
	var at: Vector3 = p["pos"]
	var yaw: float = p["yaw"]
	var e: Vector2 = p["extent"]
	match kind:
		InteriorGenerator.KIND_DESK:
			_box(batch, body, Vector3(e.x, 0.75, e.y), at + Vector3(0, 0.375, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_DESK_CLUSTER:
			var dw: float = e.x * 0.45
			var dd: float = e.y * 0.42
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_box(batch, body, Vector3(dw, 0.75, dd),
							at + Vector3(sx * e.x * 0.25, 0.375, sz * e.y * 0.26), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.9, 1.2, 0.1), at + Vector3(0, 0.6, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CUBICLE:
			_box(batch, body, Vector3(e.x, 1.3, 0.1), at + Vector3(0, 0.65, e.y * 0.5), yaw, mats["prop"])
			_box(batch, body, Vector3(0.1, 1.3, e.y), at + Vector3(e.x * 0.5, 0.65, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.8, 0.75, e.y * 0.5), at + Vector3(0, 0.375, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CABINET:
			_box(batch, body, Vector3(e.x, 1.4, e.y), at + Vector3(0, 0.7, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_SHELVING:
			_box(batch, body, Vector3(e.x, 2.2, e.y), at + Vector3(0, 1.1, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_COUNTER:
			_box(batch, body, Vector3(e.x, 1.1, e.y), at + Vector3(0, 0.55, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x, 0.12, e.y), at + Vector3(0, 1.12, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_RACKING:
			# Tall shelving run — the warehouse aisle-former.
			_box(batch, body, Vector3(e.x, 3.0, e.y), at + Vector3(0, 1.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_PALLET:
			_box(batch, body, Vector3(e.x, 0.2, e.y), at + Vector3(0, 0.1, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.8, 1.0, e.y * 0.8), at + Vector3(0, 0.7, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CRATE:
			var cr: float = e.x * 0.9
			_box(batch, body, Vector3(e.x, cr, e.y), at + Vector3(0, cr * 0.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CONTAINER:
			_box(batch, body, Vector3(e.x, 2.4, e.y), at + Vector3(0, 1.2, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_PLANTER:
			_box(batch, body, Vector3(e.x, 0.5, e.y), at + Vector3(0, 0.25, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.7, 0.8, e.y * 0.7), at + Vector3(0, 0.9, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_BENCH:
			_box(batch, body, Vector3(e.x, 0.45, e.y), at + Vector3(0, 0.225, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_FEATURE:
			# Atrium centrepiece — a plinth + glowing stack (placed by scatter, never on the hub).
			_box(batch, body, Vector3(e.x, 0.4, e.y), at + Vector3(0, 0.2, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.5, 2.2, e.y * 0.5), at + Vector3(0, 1.3, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_SERVER_RACK:
			_box(batch, body, Vector3(e.x, 2.2, e.y), at + Vector3(0, 1.1, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.9, 2.0, 0.06), at + Vector3(0, 1.1, e.y * 0.5), yaw, mats["accent"])
		_:
			# Fallback: a waist-high block the size of the reserved footprint.
			_box(batch, body, Vector3(e.x, 0.9, e.y), at + Vector3(0, 0.45, 0), yaw, mats["prop"])
