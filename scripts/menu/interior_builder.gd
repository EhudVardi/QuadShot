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
		_emit(batch, body, p, mats, interior_height)
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
	guide.emission_energy_multiplier = MenuFloorFrame.LINE_ENERGY * 1.3
	var w: float = 0.45   # wide + bright so the flight line reads at speed
	for ch: Dictionary in spec.get("channels", []):
		var a: Vector2 = ch["a"]           # window centre; hub is the origin
		var mid: Vector2 = a * 0.5
		var length: float = a.length()
		if absf(a.x) < 0.001:              # front/back window -> strip along Z
			batch.add(Vector3(w, 0.05, length), Vector3(mid.x, 0.03, mid.y), guide)
		else:                              # right/left window -> strip along X
			batch.add(Vector3(length, 0.05, w), Vector3(mid.x, 0.03, mid.y), guide)


## Interior palette by district. The outdoor zonal base colours are too dark to
## read unlit indoors, so props get a purpose-made mid grey (clearly above the
## near-black walls even before the lighting pass), lightly district-tinted;
## accents keep the zonal glow colour but clearly clear the 1.0 bloom threshold.
static func _palette(district: int) -> Dictionary:
	# Structure (columns): a legible concrete grey, clearly above the near-black wall.
	var structure := StandardMaterial3D.new()
	structure.albedo_color = Color(0.13, 0.14, 0.16)
	structure.roughness = 0.9
	# Prop (furniture): a mid grey that reads against the dark interior.
	var prop := StandardMaterial3D.new()
	prop.roughness = 0.85
	# Accent (screens / signage / greenery): emissive, district-coloured, energy
	# well above 1.0 so glowing things unmistakably glow.
	var accent := StandardMaterial3D.new()
	accent.emission_enabled = true
	match district:
		BuildingProgram.CYBER:
			prop.albedo_color = Color(0.28, 0.32, 0.38)
			accent.albedo_color = CityLayout.CYBER_GLOW_COLOR
			accent.emission = CityLayout.CYBER_GLOW_COLOR
			accent.emission_energy_multiplier = CityLayout.CYBER_GLOW_ENERGY
		BuildingProgram.URBAN:
			prop.albedo_color = Color(0.34, 0.33, 0.31)
			accent.albedo_color = CityLayout.HARDSCAPE_SIGN_COLOR
			accent.emission = CityLayout.HARDSCAPE_SIGN_COLOR
			accent.emission_energy_multiplier = 2.6
		_:
			prop.albedo_color = Color(0.33, 0.35, 0.35)
			accent.albedo_color = CityLayout.TREE_LEAF_COLOR
			accent.emission = CityLayout.TREE_LEAF_COLOR
			accent.emission_energy_multiplier = 2.6
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


## Expand a piece into boxes. Positions are local to `at`; the piece's yaw rotates
## each box. Tall pieces are capped to leave flyover headroom under the ceiling
## (`head`), so a low floor never fully blocks you above the furniture.
static func _emit(batch: BoxBatcher, body: StaticBody3D, p: Dictionary,
		mats: Dictionary, interior_height: float) -> void:
	var kind: StringName = p["kind"]
	var at: Vector3 = p["pos"]
	var yaw: float = p["yaw"]
	var e: Vector2 = p["extent"]
	var head: float = interior_height * 0.62   # tallest a piece may reach
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
			var sh: float = minf(2.2, head)
			_box(batch, body, Vector3(e.x, sh, e.y), at + Vector3(0, sh * 0.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_COUNTER:
			_box(batch, body, Vector3(e.x, 1.1, e.y), at + Vector3(0, 0.55, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x, 0.12, e.y), at + Vector3(0, 1.12, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_RACKING:
			# Tall shelving run — the warehouse aisle-former (capped to leave headroom).
			var rh: float = minf(3.0, head)
			_box(batch, body, Vector3(e.x, rh, e.y), at + Vector3(0, rh * 0.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_PALLET:
			_box(batch, body, Vector3(e.x, 0.2, e.y), at + Vector3(0, 0.1, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.8, 1.0, e.y * 0.8), at + Vector3(0, 0.7, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CRATE:
			var cr: float = e.x * 0.9
			_box(batch, body, Vector3(e.x, cr, e.y), at + Vector3(0, cr * 0.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CONTAINER:
			var coh: float = minf(2.4, head)
			_box(batch, body, Vector3(e.x, coh, e.y), at + Vector3(0, coh * 0.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_PLANTER:
			_box(batch, body, Vector3(e.x, 0.5, e.y), at + Vector3(0, 0.25, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.7, 0.8, e.y * 0.7), at + Vector3(0, 0.9, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_BENCH:
			_box(batch, body, Vector3(e.x, 0.45, e.y), at + Vector3(0, 0.225, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_FEATURE:
			# Atrium centrepiece — a plinth + glowing stack (placed by scatter, never on the hub).
			_box(batch, body, Vector3(e.x, 0.4, e.y), at + Vector3(0, 0.2, 0), yaw, mats["prop"])
			var fh: float = minf(2.2, head - 0.4)
			_box(batch, body, Vector3(e.x * 0.5, fh, e.y * 0.5), at + Vector3(0, 0.4 + fh * 0.5, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_SERVER_RACK:
			var vh: float = minf(2.2, head)
			_box(batch, body, Vector3(e.x, vh, e.y), at + Vector3(0, vh * 0.5, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.9, vh * 0.9, 0.06), at + Vector3(0, vh * 0.5, e.y * 0.5), yaw, mats["accent"])
		_:
			# Fallback: a waist-high block the size of the reserved footprint.
			_box(batch, body, Vector3(e.x, 0.9, e.y), at + Vector3(0, 0.45, 0), yaw, mats["prop"])
