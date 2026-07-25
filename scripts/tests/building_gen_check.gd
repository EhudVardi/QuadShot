extends SceneTree

## Headless check for the seeded building generator (B3/B4, v1.46 step 2):
## determinism plus the placement guarantees the menu relies on — every
## required leaf gets exactly one open floor, in order, and the height is
## honored. Pure function, so no scene: run the asserts and quit.
##
## Run: <godot> --headless -s scripts/tests/building_gen_check.gd --path .


func _initialize() -> void:
	var leaves: Array = [
		{"leaf": &"one", "label": "ONE",
				"window": Vector2(4.0, 2.4), "sill": 0.6, "pixel": 0.1},
		{"leaf": &"two", "label": "TWO",
				"window": Vector2(4.0, 2.4), "sill": 0.6, "pixel": 0.1},
	]

	# Determinism: same seed + inputs = the same building, every time.
	var a: Array = BuildingGenerator.generate(4242, leaves, 6)
	var b: Array = BuildingGenerator.generate(4242, leaves, 6)
	if str(a) != str(b):
		return _fail("same seed produced different buildings")

	# Height honored, and every floor is a known state.
	if a.size() != 6:
		return _fail("expected 6 floors, got %d" % a.size())
	var open_order: Array = []
	for spec: Dictionary in a:
		var st: StringName = spec.get("state", MenuFloorFrame.STATE_OPEN)
		if st == MenuFloorFrame.STATE_OPEN:
			open_order.append(spec["leaf"])
		elif st != MenuFloorFrame.STATE_SEALED \
				and st != MenuFloorFrame.STATE_UNDER_CONSTRUCTION:
			return _fail("floor has unknown state '%s'" % st)

	# Each required leaf gets exactly one open floor, in the given order.
	if open_order != [&"one", &"two"]:
		return _fail("open floors must be the required leaves in order, got %s"
				% str(open_order))

	# A height that cannot hold every leaf clamps up to the leaf count.
	var tight: Array = BuildingGenerator.generate(7, leaves, 1)
	if tight.size() != 2:
		return _fail("target below leaf count should clamp up, got %d"
				% tight.size())

	# The seed must actually feed the RNG: a few seeds should diverge.
	var differs: bool = false
	for s: int in range(1, 12):
		if str(BuildingGenerator.generate(s, leaves, 6)) != str(a):
			differs = true
			break
	if not differs:
		return _fail("seed does not affect the building (11 seeds identical)")

	# crown_at_top: any under-construction floors form a contiguous crown at the
	# very top (a world building is built bottom-up — nothing floats mid-air).
	var any_crown: bool = false
	for s: int in range(1, 30):
		var crowned: Array = BuildingGenerator.generate(s, leaves, 12, true)
		var seen_uc: bool = false
		for spec: Dictionary in crowned:  # bottom -> top
			var st: StringName = spec.get("state", MenuFloorFrame.STATE_OPEN)
			if st == MenuFloorFrame.STATE_UNDER_CONSTRUCTION:
				seen_uc = true
				any_crown = true
			elif seen_uc:
				return _fail("crown_at_top: under-construction must be a top "
						+ "crown, seed %d put a %s above it" % [s, st])
	if not any_crown:
		return _fail("crown_at_top produced no crowns across 29 seeds")

	print("[building_gen_check] determinism, guarantees, seed + crown — all ok")
	print("[building_gen_check] PASS")
	quit(0)


func _fail(message: String) -> void:
	print("[building_gen_check] FAIL: %s" % message)
	quit(1)
