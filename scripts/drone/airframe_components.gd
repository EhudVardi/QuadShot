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
	## Can a LOCATED hit be assigned to this component? Rotors only, today.
	##
	## This is a narrower thing than `located`, and the two are separate on
	## purpose. The transmitter is located — it rides the lens at the frame's
	## `fpv_offset` — but it is not routed, because it already takes a share of
	## EVERY hit in `main._on_player_damaged` regardless of where that hit came
	## from. Routing hits to it as well would both double-count it and change a
	## signed-off model (v1.41/v1.42), and E10 step 2 forbids new failure modes.
	## When a component becomes routable it flips this flag and joins the
	## selection; no code in `FlightController` moves.
	var routed: bool = false
	## What losing it costs.
	var cost: Cost = Cost.INTEGRITY
	## Plating over THIS component (E4.2), from `FrameConfig.component_armor`.
	## Flat: subtracted from the capability a single hit can strip, in the same
	## 0-to-1 units as `health`. Zero on every shipped frame so far.
	var armor: float = 0.0
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
	{"kind": &"rotor", "count": -1, "built": true, "routed": true,
			"cost": Cost.FLIGHT},
	{"kind": &"vtx", "count": 1, "built": true, "routed": false,
			"cost": Cost.FEED},
	{"kind": &"structure", "count": 1, "built": true, "routed": false,
			"cost": Cost.INTEGRITY},
	{"kind": &"prop", "count": -1, "built": false, "routed": false,
			"cost": Cost.VIBRATION},
	{"kind": &"power", "count": 1, "built": false, "routed": false,
			"cost": Cost.POWER},
	{"kind": &"gyro", "count": 1, "built": false, "routed": false,
			"cost": Cost.CONTROL},
	{"kind": &"weapon_mount", "count": 1, "built": false, "routed": false,
			"cost": Cost.GUNS},
	{"kind": &"magazine", "count": 1, "built": false, "routed": false,
			"cost": Cost.ORDNANCE},
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

## HOW BIG A PLATE OVER EACH COMPONENT IS: the radius of the plated disc, as a
## fraction of `body_m` (E.q7's mass loop). Fractions for the same reason MOUNTS
## uses them — a motor pod on a 3 m aircraft is not the size of one on a 5-inch
## quad, and a constant here would be the size-ladder scar again.
##
## The rotor's 0.10 is a pod rather than a bare motor can: what you would actually
## armour to keep a corner making thrust is the motor and its speed controller
## together. On the Kestrel that is a 56 mm disc, which is a 2207 motor and an
## ESC; on the Roc it is 600 mm, which is a motor a 500 kg aircraft would carry.
##
## EVERY KIND HAS AN ENTRY, including the four that cannot be damaged yet, so that
## authoring plating over an unbuilt component is never silently FREE. A missing
## entry would price at zero and the mistake would look like a working feature.
const PLATE_RADIUS: Dictionary = {
	&"rotor": 0.10,
	&"prop": 0.10,
	&"vtx": 0.04,
	&"power": 0.09,
	&"gyro": 0.05,
	&"weapon_mount": 0.07,
	&"magazine": 0.08,
	&"structure": 0.0,
}


## WHAT THIS AIRFRAME'S PLATING WEIGHS, in kg (E.q7, the human's shell model:
## *"the mass is roughly thickness times the shell plan area"*).
##
## Pure and static on purpose — it takes the two resources and a rotor count
## rather than a live drone, so it can be computed BEFORE the node is configured
## and so a bench can price a frame without building one.
##
## **THE SQUARE-CUBE LAW IS WHY E4.2 IS TRUE RATHER THAN MERELY ASSERTED.** Plate
## mass goes as area, which is `S²`; an airframe's own mass goes as volume, `S³`.
## So the SAME thickness costs a big frame a far smaller fraction of itself, which
## is exactly *"a 500 kg airframe can carry plating over its power bus and its
## gyro; a 650 g quad carries nothing"* arriving as arithmetic instead of as a
## design statement. Measured on this roster: plating a Kestrel to the Roc's
## standard would cost 14.3% of the Kestrel's mass and 2.1% of the Roc's.
static func plate_mass(frame: FrameConfig, config: FlightConfig,
		rotor_count: int) -> float:
	if frame == null or config == null:
		return 0.0
	var total: float = 0.0
	for row: Dictionary in TABLE:
		var kind: StringName = row["kind"]
		var armor: float = float(frame.component_armor.get(kind, 0.0))
		if armor <= 0.0:
			continue
		var radius: float = float(PLATE_RADIUS.get(kind, 0.0)) * config.body_m
		if radius <= 0.0:
			continue
		var area: float = PI * radius * radius
		# "one per rotor" means one plate per rotor THIS airframe has, so a hexa
		# pays for six and the count is never assumed.
		var count: int = rotor_count if int(row["count"]) < 0 else int(row["count"])
		total += frame.plate_areal_density * armor * area * float(count)
	return total


## The live component list for one airframe.
##
## `video_damage` is passed IN rather than read, because the transmitter's health
## lives in `main` and this file deliberately owns no state. 0 = a clean feed.
## `only_routed` skips the rest of the table before allocating anything, because
## this runs on the HIT path: `apply_hit_to_motors` calls it once per hit that
## lands, and building eleven objects to throw eight away is the kind of cost
## that is invisible until a swarm is in the air.
static func of(drone: FlightController, video_damage: float = 0.0,
		only_routed: bool = false) -> Array[Part]:
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
	# Plating is a property of the FRAME, not of the component list (E4.2): the
	# same rotor is bare on a Kestrel and armoured on something that can carry the
	# weight, so the table stays universal and the airframe says what it protects.
	var plating: Dictionary = {}
	if drone.frame != null:
		plating = drone.frame.component_armor
	for row: Dictionary in TABLE:
		var kind: StringName = row["kind"]
		if only_routed and not bool(row["routed"]):
			continue
		if int(row["count"]) < 0:
			# "one per rotor" means one per rotor THIS AIRFRAME HAS (E.q1): a hexa
			# gets six rotor rows and six prop rows without this table changing.
			for i: int in motors.rotor_count:
				var part := Part.new()
				part.kind = kind
				part.index = i
				part.id = StringName("%s%d" % [kind, i])
				# ONE ARM GEOMETRY IN THE PROJECT. Read, never re-authored, so a
				# six-rotor frame moves this table without touching this file.
				part.position = motors.motor_position(i, config)
				part.built = bool(row["built"])
				part.routed = bool(row["routed"])
				part.cost = row["cost"]
				part.armor = float(plating.get(kind, 0.0))
				part.health = drone.motor_health(i) if kind == &"rotor" else 1.0
				parts.append(part)
			continue
		var single := Part.new()
		single.kind = kind
		single.id = kind
		single.built = bool(row["built"])
		single.routed = bool(row["routed"])
		single.cost = row["cost"]
		single.armor = float(plating.get(kind, 0.0))
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


## The components a LOCATED hit can be assigned to (E.q2, answered `derived`).
##
## Today this is exactly the rotors, so `apply_hit_to_motors` selects over the
## same four things it always did and its behaviour is unchanged to the decimal.
## What moved is that the SET is now data: a component joins the selection by
## flipping `routed` in `TABLE`, not by anyone editing the picker.
static func targetable(drone: FlightController,
		video_damage: float = 0.0) -> Array[Part]:
	var out: Array[Part] = []
	for part: Part in of(drone, video_damage, true):
		if part.built and part.located and part.routed:
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
