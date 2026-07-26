extends SceneTree

## Headless check for the interior generators (B3, spec §4). Pure functions, so no
## scene: assert determinism + the flyability invariants + the program profile,
## then quit.
##
## Run: <godot> --headless -s scripts/tests/interior_gen_check.gd --path .

const FP: float = 24.0
const H: float = 4.0


func _initialize() -> void:
	_check_interior()
	_check_program()
	print("[interior_gen_check] determinism, channel flyability, min-clearance, profile — all ok")
	print("[interior_gen_check] PASS")
	quit(0)


func _fail(message: String) -> void:
	print("[interior_gen_check] FAIL: %s" % message)
	quit(1)


func _check_interior() -> void:
	var programs: Array = [InteriorGenerator.PROGRAM_OFFICE,
			InteriorGenerator.PROGRAM_WAREHOUSE, InteriorGenerator.PROGRAM_SERVER_FARM,
			InteriorGenerator.PROGRAM_DOCK, InteriorGenerator.PROGRAM_ATRIUM,
			InteriorGenerator.PROGRAM_LOBBY_ATRIUM]
	var side_masks: Array = [[], [true, false, false, false],
			[true, false, true, false], [true, true, true, true]]
	for prog: StringName in programs:
		for mask: Array in side_masks:
			for s: int in range(1, 6):
				_check_spec(prog, s * 17 + 3, mask)


func _check_spec(program: StringName, seed_value: int, mask: Array) -> void:
	var a: Dictionary = InteriorGenerator.generate(program, seed_value, FP, H, mask)
	var b: Dictionary = InteriorGenerator.generate(program, seed_value, FP, H, mask)
	if str(a) != str(b):
		return _fail("same seed produced different interiors (%s)" % program)
	var k: Dictionary = a["knobs"]
	var half_w: float = k["channel_width"] * 0.5
	var open_count: int = 4 if mask.is_empty() else mask.count(true)
	if a["channels"].size() != open_count:
		return _fail("expected %d channels, got %d (%s)"
				% [open_count, a["channels"].size(), program])
	# No column or piece intrudes the clear channel tube (flyability).
	for c: Vector2 in a["columns"]:
		if _nearest_channel(c, a["channels"]) < half_w:
			return _fail("a column sits in a flight channel (%s)" % program)
	var pieces: Array = a["pieces"]
	for p: Dictionary in pieces:
		var ctr := Vector2(p["pos"].x, p["pos"].z)
		if _nearest_channel(ctr, a["channels"]) < half_w:
			return _fail("a piece sits in a flight channel (%s)" % program)
	# Min-clearance holds between pieces (no overlaps).
	for i: int in pieces.size():
		for j: int in range(i + 1, pieces.size()):
			var ci := Vector2(pieces[i]["pos"].x, pieces[i]["pos"].z)
			var cj := Vector2(pieces[j]["pos"].x, pieces[j]["pos"].z)
			var ri: float = (pieces[i]["extent"] as Vector2).length() * 0.5
			var rj: float = (pieces[j]["extent"] as Vector2).length() * 0.5
			if ci.distance_to(cj) < ri + rj:
				return _fail("two pieces overlap (%s seed %d)" % [program, seed_value])


## Nearest-channel distance for a point (mirrors the generator's segment test).
func _nearest_channel(p: Vector2, channels: Array) -> float:
	var best: float = 1e9
	for ch: Dictionary in channels:
		var a: Vector2 = ch["a"]
		var b: Vector2 = ch["b"]
		var ab: Vector2 = b - a
		var t: float = 0.0
		var len2: float = ab.length_squared()
		if len2 > 0.0001:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _check_program() -> void:
	# Determinism + ground floor is a lobby-atrium + district restructures the mix.
	var nat_a: Array = BuildingProgram.programs_for(BuildingProgram.NATURAL, 4242, 20)
	var nat_b: Array = BuildingProgram.programs_for(BuildingProgram.NATURAL, 4242, 20)
	if str(nat_a) != str(nat_b):
		return _fail("same seed gave a different program profile")
	if nat_a[0] != InteriorGenerator.PROGRAM_LOBBY_ATRIUM:
		return _fail("ground floor should be a lobby-atrium, got %s" % nat_a[0])
	var cyb: Array = BuildingProgram.programs_for(BuildingProgram.CYBER, 4242, 20)
	if not cyb.has(InteriorGenerator.PROGRAM_SERVER_FARM):
		return _fail("a tall cyber tower should stack server-farm floors")
	if str(cyb) == str(nat_a):
		return _fail("district did not restructure the profile (cyber == natural)")
