class_name AirframeComponents
extends RefCounted

## E3'S COMPONENT TABLE AS DATA (GAMEPLAY-DESIGN Iteration 17 / E10 step 2).
##
## IT DESCRIBES, IT DOES NOT STORE, and that is the whole design of this file.
## Every component's health already lives somewhere: a rotor's in
## `MotorModel._health`, the transmitter's in `main._video_damage`, the airframe's
## in the `Health` node. Moving any of them here would be a behaviour change
## wearing a refactor's clothes — and E10 step 2 is explicitly *"a pure refactor
## with an unchanged board"*, whose honesty test is that `motor_damage_check` and
## `repair_check` pass UNMODIFIED. So this is a descriptor layer: it says what the
## components ARE, where they sit, how to read each one, and what losing it costs.
##
## What it buys is that components become ADDRESSABLE. `apply_hit_to_motors`
## already picks a rotor by dot product against each rotor's position, and that
## selection is count-agnostic and layout-agnostic; over this table it becomes
## "nearest component" instead of "nearest rotor" without a second mechanism.
##
## FOUR OF THE EIGHT ROWS ARE REAL AND FOUR ARE DESCRIPTION ONLY. The built ones
## report live health and can be damaged; the rest report 1.0 forever, because
## nothing damages them yet. That is deliberate rather than unfinished — E10 step
## 2 asks for *"every component present, only the built ones doing anything"*, so
## that the shape is settled before any new failure mode is added to it.
##
## MOUNTS ARE FRACTIONS OF `body_m`, NEVER METRES. A component's position on the
## airframe scales with the airframe, and this file is being written five days
## after the fourth instance of *a constant that was correct for one airframe is a
## bug on a size ladder*. A rotor's mount is not authored here at all — it is read
## from `MotorModel.motor_position`, so there is one arm geometry in the project
## and a six-rotor frame (E.q1) moves this table for free.

## What the pilot loses when a component fails. The ranking is the user's, from
## E.q8: *"bad rotors with great vtx and good weapons is not very effective, good
## rotor with damaged vtx and good weapons is medium effective because a player
## can blind shot more and he can be more stable."* Rotors dominate; the feed is
## survivable. Components are NOT equal and should not be priced as if they were.
enum Cost {
	FLIGHT,     ## thrust and attitude — the wound you feel through the sticks
	VIBRATION,  ## noise the gyro filters must fight, not thrust lost
	POWER,      ## available thrust sags; the frame's TWR droops
	CONTROL,    ## a noisier rate loop and a wider gun-director window
	FEED,       ## the FPV picture degrades; you fly and shoot blind
	GUNS,       ## that weapon stops working; you keep flying
	ORDNANCE,   ## rounds lost
	INTEGRITY,  ## the coarse "how close to death" pool; zero = the airframe broke
}

## One live component on one airframe.
class Part:
	extends RefCounted

	## Unique on the airframe: "rotor0", "vtx", "structure".
	var id: StringName
	## The E3 row this came from.
	var kind: StringName
	## Which one, for the per-rotor families; -1 for the singletons.
	var index: int = -1
	## Mount point in BODY space (drone front is -Z, thrust is +Y).
	var position: Vector3 = Vector3.ZERO
	## 1 = healthy, 0 = failed. Always 1 for the rows nothing damages yet.
	var health: float = 1.0
	## False for the four rows that are description only.
	var built: bool = false
	## What losing it costs.
	var cost: Cost = Cost.INTEGRITY
	## LOCATED components can be picked by where a hit came from. The structure
	## pool cannot — it is the whole airframe, which is why E5 keeps it as a pool
	## beside the components rather than as one of them.
	var located: bool = true

	func failed() -> bool:
		return health <= 0.0


## E3's eight rows, in E3's order. `count` is -1 for "one per rotor".
##
## This is the table a designer reads. The live list comes from `of()`, which is
## the only place it meets an actual airframe.
const TABLE: Array[Dictionary] = [
	{"kind": &"rotor", "count": -1, "built": true, "cost": Cost.FLIGHT},
	{"kind": &"vtx", "count": 1, "built": true, "cost": Cost.FEED},
	{"kind": &"structure", "count": 1, "built": true, "cost": Cost.INTEGRITY},
	{"kind": &"prop", "count": -1, "built": false, "cost": Cost.VIBRATION},
	{"kind": &"power", "count": 1, "built": false, "cost": Cost.POWER},
	{"kind": &"gyro", "count": 1, "built": false, "cost": Cost.CONTROL},
	{"kind": &"weapon_mount", "count": 1, "built": false, "cost": Cost.GUNS},
	{"kind": &"magazine", "count": 1, "built": false, "cost": Cost.ORDNANCE},
]

## Provisional mounts for the singleton rows, as fractions of `body_m`. The two
## BUILT singletons do not appear here: the transmitter rides the camera at the
## frame's authored `fpv_offset`, and the structure pool has no location at all.
##
## The rest are placed where the part would actually sit on a multirotor — the
## pack low and aft of centre, the flight controller at the centre of mass, the
## gun forward with the lens, the magazine low and aft with the pack — and they
## are provisional precisely because nothing reads them yet.
const MOUNTS: Dictionary = {
	&"power": Vector3(0.0, -0.05, 0.15),
	&"gyro": Vector3(0.0, 0.0, 0.0),
	&"weapon_mount": Vector3(0.0, 0.05, -0.30),
	&"magazine": Vector3(0.0, -0.08, 0.22),
}


## The live component list for one airframe.
##
## `video_damage` is passed IN rather than read, because the transmitter's health
## lives in `main` and this file deliberately owns no state. 0 = a clean feed.
static func of(drone: FlightController, video_damage: float = 0.0) -> Array[Part]:
	var parts: Array[Part] = []
	if drone == null or drone.config == null:
		return parts
	var config: FlightConfig = drone.config
	var body: float = config.body_m
	# Reached through the node rather than statically ON PURPOSE. `motor_position`
	# is pure and could be a static, but making it one would mean editing
	# `MotorModel` and every caller inside a task whose stated honesty test is
	# that nothing else moved. Borrowing the instance costs one lookup per call
	# and leaves the diff where it belongs.
	var motors: MotorModel = drone.get_node_or_null("MotorModel") as MotorModel
	if motors == null:
		return parts
	for row: Dictionary in TABLE:
		var kind: StringName = row["kind"]
		if int(row["count"]) < 0:
			for i: int in MotorModel.MOTOR_COUNT:
				var part := Part.new()
				part.kind = kind
				part.index = i
				part.id = StringName("%s%d" % [kind, i])
				# ONE ARM GEOMETRY IN THE PROJECT. Read, never re-authored, so a
				# six-rotor frame moves this table without touching this file.
				part.position = motors.motor_position(i, config)
				part.built = bool(row["built"])
				part.cost = row["cost"]
				part.health = drone.motor_health(i) if kind == &"rotor" else 1.0
				parts.append(part)
			continue
		var single := Part.new()
		single.kind = kind
		single.id = kind
		single.built = bool(row["built"])
		single.cost = row["cost"]
		match kind:
			&"vtx":
				single.position = config.fpv_offset
				single.health = clampf(1.0 - video_damage, 0.0, 1.0)
			&"structure":
				# The one row with no location: a crash, splash or blast is not
				# aimed anywhere (E5), and neither is the pool that takes it.
				single.located = false
				var health: Health = drone.get_node_or_null("Health") as Health
				if health != null and health.max_health > 0.0:
					single.health = clampf(health.current / health.max_health,
							0.0, 1.0)
			_:
				single.position = (MOUNTS[kind] as Vector3) * body
		parts.append(single)
	return parts


## Just the components a hit can currently be routed to — the located, built
## ones. This is what generalises `apply_hit_to_motors` beyond rotors (E.q2).
static func targetable(drone: FlightController,
		video_damage: float = 0.0) -> Array[Part]:
	var out: Array[Part] = []
	for part: Part in of(drone, video_damage):
		if part.built and part.located:
			out.append(part)
	return out


## Every component's health in one array, in `TABLE` order — the shape the HUD's
## pip widget wants (E.q5) without it having to know what an airframe is built
## from.
static func healths(drone: FlightController,
		video_damage: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part: Part in of(drone, video_damage):
		out.append(part.health)
	return out
