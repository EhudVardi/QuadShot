class_name ScaleYard
extends Node3D

## THE SCALE YARD (PLAN-FULL-SCALE phase 2): a neon-greybox world built for one
## job — telling the pilot how big they are.
##
## IT EXISTS BECAUSE THE DESERT COULD NOT ANSWER THE QUESTION. The user flew the
## 3 m Kestrel over 6 km of dunes and reported *"the desert is not good to feel
## the change"*, and they are right for a reason worth writing down: **a dune has
## no known size.** Neither does a noise function, a hill, or a horizon. Scale is
## not a property of a world — it is a COMPARISON, and a landscape made entirely
## of shapes nobody has ever stood next to offers nothing to compare against. A
## 3 m aircraft and a 30 m aircraft fly that desert identically.
##
## So this map is the opposite: **every object in it is a thing whose real size
## you already know**, built at that size to the centimetre. A person is 1.75 m.
## A car is 4.4 m. A shipping container is 12.19 m because that is what a 40-foot
## container is. A football pitch is 105 x 68 m. An A320 is 37.6 m long, which is
## the one that lands the whole decision: park a 3 m aircraft beside an airliner
## and D2 stops being a number in a config file.
##
## **The dimensions ARE the feature, so they are authored, sourced and commented
## rather than scaled from anything.** No multiplier was applied to any number in
## this file and none ever should be — the moment a reference object is scaled it
## stops being a reference. If the world scale changes again, this map does not.
##
## Everything is greybox primitives batched by material (BoxBatcher), the ground
## is the checker shader's two-tier grid (10 m minor, 100 m major), and nothing
## here shoots at you. Fly it, look at things, come back with a verdict on S.q8.

## Anchors are authored, not scattered: a scale reference you have to go looking
## for is a scale reference nobody uses. The apron is arranged so the ladder from
## human-sized to airliner-sized is a single sweep of the head from the pad.

# --- the spawn apron ---------------------------------------------------------
const PAD_SIZE := Vector3(16.0, 0.4, 16.0)
## Where the pilot is put down. Clear of the pad top (0.4) plus the airframe's
## own half-height (0.43) plus room to settle.
const PAD_LIFT: float = 1.2
## THE AIRFRAME LADDER, parked beside the pad: all three flyable frames at their
## true sizes, in a row, with a 1.75 m person standing at the end of it.
##
## This is the only group in the map whose sizes are NOT things you have stood
## next to — they are the answer rather than the ruler. That is why they are
## parked next to the person: the row says "here is what you are about to fly,
## and here is a human being, at the same range, to scale."
##
## (display name, body m, arm m, offset x, sign height). The sign heights are
## staggered on purpose, and under the L.q10 house rule that stagger stopped
## being a nicety and became the mechanism: signs no longer switch off, so three
## plates on frames 7 m apart WILL overlap unless they sit at three altitudes.
## This is the smallest example in the map of "solve the crowding physically".
const LADDER_AT := Vector3(-30.0, 0.0, -17.0)
const LADDER: Array[Array] = [
	["1 KESTREL 0.28M", 0.28, 0.12, 0.0, 2.4],
	["2 CONDOR 1.20M", 1.2, 0.5143, 7.0, 4.6],
	["3 ROC 3.00M", 3.0, 1.286, 16.0, 7.2],
]

# --- the ruler row: things you have stood next to ----------------------------
## AN ARC AROUND THE PAD, NOT A LINE, and the reason is the whole point of the
## row: everything on it sits at the SAME RANGE from the pilot, so apparent size
## is a fair comparison. Down a straight line the far end is smaller because it
## is further away, which is exactly the confusion this map exists to remove.
## Each object is turned broadside — you judge a 12 m bus by its side.
const ROW_RADIUS: float = 45.0
## Station bearings off the nose, small to large, left to right. Inside the FPV
## camera's horizontal field (about +/-62 deg at 94 deg vertical on 16:9), so the
## whole ladder is in one frame from the pad.
const ROW_BEARINGS_DEG: Array[float] = [-55.0, -33.0, -11.0, 11.0, 33.0, 55.0]
const PERSON_H: float = 1.75
const PERSON_SHOULDER: float = 0.45
## A saloon car and the bay it parks in — the bay is a ruler in its own right.
const CAR_L: float = 4.40
const CAR_W: float = 1.80
const CAR_H: float = 1.45
const BAY_L: float = 5.00
const BAY_W: float = 2.50
## City bus.
const BUS_L: float = 12.00
const BUS_W: float = 2.55
const BUS_H: float = 3.20
## Tractor unit plus semi-trailer, at the European legal maximum.
const TRUCK_L: float = 16.50
const TRUCK_W: float = 2.55
const TRUCK_H: float = 4.00
## ISO 40-foot container: the most standardised object on earth, and therefore
## the most honest ruler in this map.
const CONTAINER_L: float = 12.19
const CONTAINER_W: float = 2.44
const CONTAINER_H: float = 2.59
## Detached house: 10 x 8 m footprint, 5.5 m to the eaves, 8.5 m to the ridge.
const HOUSE_W: float = 10.0
const HOUSE_D: float = 8.0
const HOUSE_EAVES: float = 5.5
const HOUSE_RIDGE: float = 8.5

# --- the town: storeys, which is how humans read building height -------------
const TOWN_AT := Vector3(-330.0, 0.0, -430.0)
const STOREY_M: float = 3.0
## (footprint x, footprint z, storeys, offset x, offset z) per building.
const TOWN_BLOCKS: Array[Array] = [
	[10.0, 8.0, 2, -150.0, 60.0],
	[10.0, 8.0, 2, -120.0, 88.0],
	[12.0, 9.0, 2, -86.0, 62.0],
	[10.0, 8.0, 2, -150.0, 110.0],
	[24.0, 14.0, 6, -30.0, 70.0],
	[22.0, 14.0, 5, 10.0, 100.0],
	[26.0, 16.0, 7, 50.0, 62.0],
	[30.0, 20.0, 12, -40.0, -10.0],
	[40.0, 30.0, 17, 40.0, -30.0],
	[45.0, 45.0, 48, -10.0, -130.0],
]

# --- the airfield: the object that settles D2 --------------------------------
const RUNWAY_Z: float = -570.0
const RUNWAY_W: float = 45.0
const RUNWAY_L: float = 1200.0
## Standard runway centreline: 30 m of paint, 20 m of gap.
const DASH_L: float = 30.0
const DASH_GAP: float = 20.0
const DASH_W: float = 0.9
## Narrowbody (A320 class): 37.57 m long, 35.8 m span, 11.76 m to the fin tip.
const NARROW_L: float = 37.6
const NARROW_SPAN: float = 35.8
const NARROW_TAIL_H: float = 11.8
const NARROW_FUSELAGE_D: float = 4.0
const NARROW_AT := Vector3(150.0, 0.0, -470.0)
## Widebody (747 class): 70.6 m long, 64.4 m span, 19.4 m to the fin tip.
const WIDE_L: float = 70.6
const WIDE_SPAN: float = 64.4
const WIDE_TAIL_H: float = 19.4
const WIDE_FUSELAGE_D: float = 6.5
const WIDE_AT := Vector3(300.0, 0.0, -480.0)
## Maintenance hangar, mouth facing the pad — 60 m wide and 18 m high, so
## whether a 3 m aircraft can fly INTO a building is answerable rather than
## theoretical.
const HANGAR_AT := Vector3(-170.0, 0.0, -455.0)
const HANGAR_W: float = 70.0
const HANGAR_D: float = 50.0
const HANGAR_H: float = 22.0
const HANGAR_DOOR_W: float = 60.0
const HANGAR_DOOR_H: float = 18.0

# --- the pitch: 105 x 68 m, the reference nearly everyone owns ----------------
const PITCH_AT := Vector3(320.0, 0.0, -170.0)
const PITCH_L: float = 105.0
const PITCH_W: float = 68.0
const GOAL_W: float = 7.32
const GOAL_H: float = 2.44
const LINE_W: float = 0.12
const PENALTY_D: float = 16.5
const PENALTY_W: float = 40.32
const CENTRE_CIRCLE_R: float = 9.15

# --- infrastructure: the distance rulers -------------------------------------
## A transmission line marching east. A pylon is 45 m and the span between two
## of them is ~220 m, which makes the whole line a tape measure laid on the
## ground — count the towers and you know how far you have flown.
const PYLON_START := Vector3(520.0, 0.0, -80.0)
const PYLON_SPAN: float = 220.0
const PYLON_COUNT: int = 6
const PYLON_H: float = 45.0
const PYLON_BASE_W: float = 8.0
const PYLON_TOP_W: float = 3.0
## Utility-scale wind turbine: 90 m hub, 45 m blade, so 135 m at the tip.
const TURBINE_AT := Vector3(-720.0, 0.0, -880.0)
const TURBINE_HUB_H: float = 90.0
const TURBINE_BLADE_L: float = 45.0
const TURBINE_COUNT: int = 4
const TURBINE_SPACING: float = 160.0
## Guyed radio mast.
const MAST_AT := Vector3(640.0, 0.0, -700.0)
const MAST_H: float = 150.0
const MAST_W: float = 3.0
## Cable-stayed bridge: 240 m span, 32 m of clearance under the deck. The
## "can I fly under that" object.
const BRIDGE_AT := Vector3(760.0, 0.0, -300.0)
const BRIDGE_SPAN: float = 240.0
const BRIDGE_DECK_W: float = 14.0
const BRIDGE_CLEARANCE: float = 32.0
const BRIDGE_TOWER_H: float = 70.0

# --- the altitude ruler ------------------------------------------------------
## Behind the pad, so it is a thing you look BACK at rather than a forest in
## front of the apron. Altitude has never had a ruler in this game and a fast
## aircraft needs one more than a quad did.
const COMB_AT := Vector3(0.0, 0.0, 130.0)
const COMB_SPACING: float = 44.0
const COMB_HEIGHTS: Array[float] = [10.0, 25.0, 50.0, 100.0, 200.0, 400.0]
const COMB_POLE_W: float = 1.4

# --- the agility course ------------------------------------------------------
## Descending apertures, labelled, so the pilot finds their own limit instead of
## being told one. Solid bars: clipping a gate costs you, exactly as it does in
## the arena.
const GATE_BAR: float = 1.2
## (aperture, x, altitude, z)
const GATES: Array[Array] = [
	[40.0, -55.0, 35.0, -150.0],
	[32.0, 45.0, 45.0, -230.0],
	[26.0, -40.0, 30.0, -310.0],
	[20.0, 35.0, 50.0, -390.0],
	[14.0, 0.0, 40.0, -470.0],
]

const LABEL_COLOR := Color(0.35, 0.85, 1.0)

@export var structure: Material
@export var prop: Material
@export var paint: Material
@export var tarmac: Material
@export var pad_material: Material
@export var gate_material: Material
## The sign plates and their legs. Dark and matte on purpose: a sign is a BOARD
## with light on it, so the board must not glow or the glyphs stop reading as
## something mounted and go back to being a floating label.
@export var sign_material: Material

var _batch := BoxBatcher.new()


func _ready() -> void:
	_build_apron()
	_build_ruler_row()
	_build_town()
	_build_airfield()
	_build_pitch()
	_build_pylon_line()
	_build_wind_farm()
	_build_mast()
	_build_bridge()
	_build_height_comb()
	_build_gate_course()
	_batch.commit_into(self)
	_place_pilot()


## `place_at` rather than a transform assignment, so the reset key returns the
## pilot to the pad instead of to whatever the .tscn happened to say.
func _place_pilot() -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method("place_at"):
		return
	var landed := Transform3D((player as Node3D).global_transform.basis,
			Vector3(0.0, PAD_SIZE.y + PAD_LIFT, 0.0))
	player.call("place_at", landed)


# -----------------------------------------------------------------------------
# The apron
# -----------------------------------------------------------------------------

func _build_apron() -> void:
	_solid(PAD_SIZE, Vector3(0.0, PAD_SIZE.y * 0.5, 0.0), pad_material)
	_build_ladder()
	_sign("SCALE YARD", Vector3(0.0, 25.0, -34.0), 110.0)
	_sign("1 KESTREL   2 CONDOR   3 ROC", Vector3(0.0, 14.0, -34.0), 45.0)


## The three flyable frames, parked, plus a person to stand them against.
func _build_ladder() -> void:
	for entry: Array in LADDER:
		var at: Vector3 = LADDER_AT + Vector3(float(entry[3]), 0.0, 0.0)
		_airframe(at, float(entry[1]), float(entry[2]))
		_sign(String(entry[0]), at + Vector3(0.0, float(entry[4]), 0.0), 18.0)
	_person(LADDER_AT + Vector3(-3.5, 0.0, 0.0))
	_sign("PERSON 1.75M", LADDER_AT + Vector3(-3.5, 3.0, 0.0), 13.0)


## A parked quad at `body` metres across, built from the SAME proportions the
## flown airframe uses (`FlightController`), so the model on the apron is the
## machine you take off in and not an artist's impression of it.
func _airframe(at: Vector3, body: float, arm: float) -> void:
	var gear: float = body * 0.12
	_prop_box(Vector3(body, body * FlightController.BODY_HEIGHT_RATIO, body),
			at + Vector3(0.0, gear + body * FlightController.BODY_HEIGHT_RATIO * 0.5, 0.0))
	var motor := Vector3(body * FlightController.MOTOR_SIZE_RATIO,
			body * FlightController.MOTOR_HEIGHT_RATIO,
			body * FlightController.MOTOR_SIZE_RATIO)
	for corner: Array in [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0]]:
		_prop_box(motor, at + Vector3(float(corner[0]) * arm,
				gear + body * FlightController.MOTOR_LIFT_RATIO,
				float(corner[1]) * arm))
	# The nose glows, so which way a parked frame is pointing is readable at a
	# glance — and at 0.28 m that is the only part of the Kestrel you can see.
	_batch.add(motor, at + Vector3(0.0, gear + body * FlightController.NOSE_LIFT_RATIO,
			-body * FlightController.NOSE_REACH_RATIO), paint)


# -----------------------------------------------------------------------------
# The ruler row — things you have stood next to
# -----------------------------------------------------------------------------

func _build_ruler_row() -> void:
	_build_people(0)
	_build_car_park(1)
	_build_bus(2)
	_build_truck(3)
	_build_containers(4)
	_build_house(5)


## Where station `index` stands, and which way it faces. Every object's long
## axis is its local X, so a yaw of -bearing lays it along the arc's tangent —
## broadside to the pad.
func _station(index: int) -> Vector3:
	var bearing: float = deg_to_rad(ROW_BEARINGS_DEG[index])
	return Vector3(sin(bearing) * ROW_RADIUS, 0.0, -cos(bearing) * ROW_RADIUS)


func _station_yaw(index: int) -> float:
	return -deg_to_rad(ROW_BEARINGS_DEG[index])


## Five figures, because one person reads as a post and a group reads as people.
func _build_people(index: int) -> void:
	var at: Vector3 = _station(index)
	var yaw: float = _station_yaw(index)
	var along := Vector3(cos(yaw), 0.0, -sin(yaw))
	for i: int in 5:
		_person(at + along * (float(i) - 2.0) * 1.6
				+ Vector3(0.0, 0.0, float(i % 2) * 1.3))
	_sign("PERSON 1.75M", at + Vector3(0.0, PERSON_H + 2.6, 0.0), ROW_RADIUS)


func _person(at: Vector3) -> void:
	_prop_box(Vector3(PERSON_SHOULDER * 0.8, 0.85, 0.28), at + Vector3(0.0, 0.425, 0.0))
	_prop_box(Vector3(PERSON_SHOULDER, 0.65, 0.30), at + Vector3(0.0, 1.175, 0.0))
	_prop_box(Vector3(0.22, 0.24, 0.22), at + Vector3(0.0, 1.62, 0.0))


## Three cars in marked bays. The bay markings matter as much as the cars: a
## 2.5 x 5 m rectangle is a size almost everyone can picture from memory.
func _build_car_park(index: int) -> void:
	var at: Vector3 = _station(index)
	var yaw: float = _station_yaw(index)
	var along := Vector3(cos(yaw), 0.0, -sin(yaw))
	for i: int in 3:
		var slot: Vector3 = at + along * (float(i) - 1.0) * (BAY_W + 0.3)
		_bay_markings(slot, yaw)
		_car(slot, yaw)
	_sign("CAR 4.4M
BAY 2.5X5M", at + Vector3(0.0, CAR_H + 3.4, 0.0), ROW_RADIUS)


## Length on local X, so the arc's yaw turns it broadside. Bay depth (5 m) runs
## across the arc, which is why the car is laid along the bay's SHORT axis.
func _car(at: Vector3, yaw: float) -> void:
	_prop_box(Vector3(CAR_L, 0.75, CAR_W), at + Vector3(0.0, 0.55, 0.0), yaw)
	_prop_box(Vector3(CAR_L * 0.5, 0.55, CAR_W * 0.9),
			at + Vector3(0.0, 1.18, 0.0), yaw)


func _bay_markings(at: Vector3, yaw: float) -> void:
	for side: float in [-1.0, 1.0]:
		_paint_strip(Vector3(BAY_L, 0.02, 0.12),
				at + Vector3(0.0, 0.03, 0.0)
						+ Vector3(-sin(yaw), 0.0, -cos(yaw)) * side * BAY_W * 0.5,
				null, yaw)


func _build_bus(index: int) -> void:
	var at: Vector3 = _station(index)
	_solid(Vector3(BUS_L, BUS_H - 0.3, BUS_W),
			at + Vector3(0.0, 0.3 + (BUS_H - 0.3) * 0.5, 0.0), prop, _station_yaw(index))
	_sign("BUS 12M", at + Vector3(0.0, BUS_H + 2.8, 0.0), ROW_RADIUS)


func _build_truck(index: int) -> void:
	var at: Vector3 = _station(index)
	var yaw: float = _station_yaw(index)
	var along := Vector3(cos(yaw), 0.0, -sin(yaw))
	var cab_l: float = 2.4
	_solid(Vector3(cab_l, 2.7, TRUCK_W),
			at + along * (-TRUCK_L * 0.5 + cab_l * 0.5) + Vector3(0.0, 1.5, 0.0),
			prop, yaw)
	_solid(Vector3(TRUCK_L - cab_l - 0.4, 2.7, TRUCK_W),
			at + along * (cab_l * 0.5) + Vector3(0.0, TRUCK_H - 1.35, 0.0), prop, yaw)
	_sign("TRUCK 16.5M", at + Vector3(0.0, TRUCK_H + 2.8, 0.0), ROW_RADIUS)


## A stack of 40-foot containers: three along, two high, so the row reads as
## 12 m repeated — the same trick the pylon line plays at 220 m.
func _build_containers(index: int) -> void:
	var at: Vector3 = _station(index)
	var yaw: float = _station_yaw(index)
	var across := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for level: int in 2:
		for i: int in 3:
			_solid(Vector3(CONTAINER_L, CONTAINER_H, CONTAINER_W),
					at + across * (float(i) - 1.0) * (CONTAINER_W + 0.4)
							+ Vector3(0.0, CONTAINER_H * (0.5 + float(level)), 0.0),
					structure, yaw)
	_sign("CONTAINER 12.19M", at + Vector3(0.0, CONTAINER_H * 2.0 + 3.0, 0.0), ROW_RADIUS)


## Eaves plus a stepped ridge. Three shrinking slabs is not a pitched roof, but
## at greybox fidelity it reads as one and it stays inside the box grammar.
func _build_house(index: int) -> void:
	var at: Vector3 = _station(index)
	var yaw: float = _station_yaw(index)
	_solid(Vector3(HOUSE_W, HOUSE_EAVES, HOUSE_D),
			at + Vector3(0.0, HOUSE_EAVES * 0.5, 0.0), structure, yaw)
	var courses: int = 3
	var rise: float = (HOUSE_RIDGE - HOUSE_EAVES) / float(courses)
	for i: int in courses:
		var shrink: float = float(i + 1) / float(courses + 1)
		_solid(Vector3(HOUSE_W, rise, HOUSE_D * (1.0 - shrink * 0.8)),
				at + Vector3(0.0, HOUSE_EAVES + rise * (0.5 + float(i)), 0.0),
				structure, yaw)
	_sign("HOUSE 8.5M RIDGE", at + Vector3(0.0, HOUSE_RIDGE + 3.0, 0.0), ROW_RADIUS)


# -----------------------------------------------------------------------------
# The town — height measured in storeys
# -----------------------------------------------------------------------------

func _build_town() -> void:
	for block: Array in TOWN_BLOCKS:
		var storeys: int = int(block[2])
		var height: float = float(storeys) * STOREY_M
		var at: Vector3 = TOWN_AT + Vector3(float(block[3]), 0.0, float(block[4]))
		_solid(Vector3(float(block[0]), height, float(block[1])),
				at + Vector3(0.0, height * 0.5, 0.0), structure)
		# Only the archetypes are labelled — a label on all ten is noise, and the
		# point of the rest is to be a skyline you judge the labelled ones against.
		if storeys == 6:
			_sign("APARTMENTS
6 FLOORS 18M", at + Vector3(0.0, height + 6.0, 0.0), 200.0)
		elif storeys == 17:
			_sign("OFFICE
17 FLOORS 51M", at + Vector3(0.0, height + 9.0, 0.0), 260.0)
		elif storeys == 48:
			_sign("TOWER
48 FLOORS 144M", at + Vector3(0.0, height + 14.0, 0.0), 340.0)


# -----------------------------------------------------------------------------
# The airfield — and the one comparison this whole map was built to make
# -----------------------------------------------------------------------------

func _build_airfield() -> void:
	_build_runway()
	_build_hangar()
	_airliner(NARROW_AT, NARROW_L, NARROW_SPAN, NARROW_TAIL_H, NARROW_FUSELAGE_D)
	_sign("AIRLINER\n37.6M LONG",
			NARROW_AT + Vector3(0.0, NARROW_TAIL_H + 7.0, 0.0), 300.0)
	_airliner(WIDE_AT, WIDE_L, WIDE_SPAN, WIDE_TAIL_H, WIDE_FUSELAGE_D)
	_sign("WIDEBODY\n70.6M LONG",
			WIDE_AT + Vector3(0.0, WIDE_TAIL_H + 8.0, 0.0), 340.0)


func _build_runway() -> void:
	_paint_strip(Vector3(RUNWAY_L, 0.04, RUNWAY_W),
			Vector3(0.0, 0.02, RUNWAY_Z), tarmac)
	# Centreline.
	var period: float = DASH_L + DASH_GAP
	var dashes: int = int(RUNWAY_L / period)
	for i: int in dashes:
		var x: float = -RUNWAY_L * 0.5 + period * (float(i) + 0.5)
		_paint_strip(Vector3(DASH_L, 0.02, DASH_W), Vector3(x, 0.05, RUNWAY_Z))
	# Edge stripes, full length.
	for side: float in [-1.0, 1.0]:
		_paint_strip(Vector3(RUNWAY_L, 0.02, DASH_W),
				Vector3(0.0, 0.05, RUNWAY_Z + side * (RUNWAY_W * 0.5 - 0.9)))
	# Threshold bars and aiming-point blocks at both ends.
	for end: float in [-1.0, 1.0]:
		var edge: float = end * RUNWAY_L * 0.5
		for i: int in 8:
			var offset: float = (float(i) - 3.5) * 4.5
			_paint_strip(Vector3(30.0, 0.02, 1.8),
					Vector3(edge - end * 25.0, 0.05, RUNWAY_Z + offset))
		for side: float in [-1.0, 1.0]:
			_paint_strip(Vector3(45.0, 0.02, 6.0),
					Vector3(edge - end * 300.0, 0.05, RUNWAY_Z + side * 11.0))
	_sign("RUNWAY 45M WIDE\n1200M LONG",
			Vector3(0.0, 30.0, RUNWAY_Z + 70.0), 460.0)


func _build_hangar() -> void:
	var half_w: float = HANGAR_W * 0.5
	var pier: float = (HANGAR_W - HANGAR_DOOR_W) * 0.5
	# Side walls, back wall, roof, and two door piers with a lintel — the mouth
	# is the point, so it is left genuinely open.
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(1.0, HANGAR_H, HANGAR_D),
				HANGAR_AT + Vector3(side * half_w, HANGAR_H * 0.5, 0.0), structure)
	_solid(Vector3(HANGAR_W, HANGAR_H, 1.0),
			HANGAR_AT + Vector3(0.0, HANGAR_H * 0.5, -HANGAR_D * 0.5), structure)
	_solid(Vector3(HANGAR_W, 1.0, HANGAR_D),
			HANGAR_AT + Vector3(0.0, HANGAR_H, 0.0), structure)
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(pier, HANGAR_H, 1.0),
				HANGAR_AT + Vector3(side * (half_w - pier * 0.5), HANGAR_H * 0.5,
						HANGAR_D * 0.5), structure)
	_solid(Vector3(HANGAR_DOOR_W, HANGAR_H - HANGAR_DOOR_H, 1.0),
			HANGAR_AT + Vector3(0.0, HANGAR_DOOR_H + (HANGAR_H - HANGAR_DOOR_H) * 0.5,
					HANGAR_D * 0.5), structure)
	_sign("HANGAR DOOR\n60X18M",
			HANGAR_AT + Vector3(0.0, HANGAR_H + 5.0, HANGAR_D * 0.5), 240.0)


## Fuselage, wing, fin, stabiliser, two engines. Nose points north (-Z), so the
## span lies across the pilot's view on the way in.
func _airliner(at: Vector3, length: float, span: float, tail_h: float,
		diameter: float) -> void:
	var belly: float = diameter * 0.5 + 1.6
	_solid(Vector3(diameter, diameter, length), at + Vector3(0.0, belly, 0.0), prop)
	_solid(Vector3(span, 0.6, length * 0.22),
			at + Vector3(0.0, belly - diameter * 0.35, length * 0.05), prop)
	_solid(Vector3(0.8, tail_h - belly - diameter * 0.4, length * 0.18),
			at + Vector3(0.0, (tail_h + belly + diameter * 0.4) * 0.5,
					length * 0.42), prop)
	_solid(Vector3(span * 0.36, 0.5, length * 0.1),
			at + Vector3(0.0, belly + diameter * 0.4, length * 0.44), prop)
	# Engine centreline is set from the fuselage diameter rather than dropped a
	# fixed amount: at 0.7 x diameter the widebody's nacelles ended up buried in
	# the apron, which is the airliner-sized version of the camera-offset trap.
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(diameter * 0.62, diameter * 0.62, length * 0.13),
				at + Vector3(side * span * 0.28, belly - diameter * 0.40,
						-length * 0.02), prop)


# -----------------------------------------------------------------------------
# The football pitch — 105 x 68 m
# -----------------------------------------------------------------------------

func _build_pitch() -> void:
	_paint_strip(Vector3(PITCH_L + 10.0, 0.04, PITCH_W + 10.0),
			PITCH_AT + Vector3(0.0, 0.02, 0.0), tarmac)
	# Touchlines and goal lines.
	for side: float in [-1.0, 1.0]:
		_paint_strip(Vector3(PITCH_L, 0.02, LINE_W),
				PITCH_AT + Vector3(0.0, 0.05, side * PITCH_W * 0.5))
		_paint_strip(Vector3(LINE_W, 0.02, PITCH_W),
				PITCH_AT + Vector3(side * PITCH_L * 0.5, 0.05, 0.0))
	_paint_strip(Vector3(LINE_W, 0.02, PITCH_W), PITCH_AT + Vector3(0.0, 0.05, 0.0))
	# Centre circle, as tangent segments. The yaw puts each strip along the
	# tangent at its own angle: a yaw of phi sends +X to (cos phi, -sin phi) in
	# XZ, and the tangent at angle a is (-sin a, cos a), which solves to
	# phi = -(a + PI/2).
	var segments: int = 32
	var step: float = TAU / float(segments)
	for i: int in segments:
		var a: float = step * float(i)
		_paint_strip(Vector3(CENTRE_CIRCLE_R * step * 1.1, 0.02, LINE_W),
				PITCH_AT + Vector3(cos(a) * CENTRE_CIRCLE_R, 0.05,
						sin(a) * CENTRE_CIRCLE_R), paint, -(a + PI * 0.5))
	# Penalty areas and goals.
	for end: float in [-1.0, 1.0]:
		var goal_x: float = end * PITCH_L * 0.5
		_paint_strip(Vector3(LINE_W, 0.02, PENALTY_W),
				PITCH_AT + Vector3(goal_x - end * PENALTY_D, 0.05, 0.0))
		for side: float in [-1.0, 1.0]:
			_paint_strip(Vector3(PENALTY_D, 0.02, LINE_W),
					PITCH_AT + Vector3(goal_x - end * PENALTY_D * 0.5, 0.05,
							side * PENALTY_W * 0.5))
			_solid(Vector3(0.12, GOAL_H, 0.12),
					PITCH_AT + Vector3(goal_x, GOAL_H * 0.5, side * GOAL_W * 0.5), paint)
		_solid(Vector3(0.12, 0.12, GOAL_W),
				PITCH_AT + Vector3(goal_x, GOAL_H, 0.0), paint)
	_sign("FOOTBALL PITCH
105X68M",
			PITCH_AT + Vector3(0.0, 20.0, PITCH_W * 0.5 + 14.0), 260.0)


# -----------------------------------------------------------------------------
# Infrastructure — the distance and altitude rulers
# -----------------------------------------------------------------------------

## A transmission line: six pylons, 220 m apart, marching east. Counting towers
## is how you read distance off this map without looking at a number.
func _build_pylon_line() -> void:
	for i: int in PYLON_COUNT:
		var at: Vector3 = PYLON_START + Vector3(float(i) * PYLON_SPAN, 0.0, 0.0)
		_pylon(at)
		if i < PYLON_COUNT - 1:
			_catenary(at, PYLON_START + Vector3(float(i + 1) * PYLON_SPAN, 0.0, 0.0))
	_sign("PYLON 45M\nSPAN 220M",
			PYLON_START + Vector3(PYLON_SPAN * 0.5, 34.0, 0.0), 380.0)


func _pylon(at: Vector3) -> void:
	var courses: int = 5
	var rise: float = PYLON_H / float(courses)
	for i: int in courses:
		var t: float = float(i) / float(courses)
		var w: float = lerpf(PYLON_BASE_W, PYLON_TOP_W, t)
		_solid(Vector3(w, rise, w), at + Vector3(0.0, rise * (0.5 + float(i)), 0.0),
				structure)
	_solid(Vector3(1.2, 1.0, 25.0), at + Vector3(0.0, PYLON_H * 0.72, 0.0), structure)
	_solid(Vector3(1.2, 1.0, 18.0), at + Vector3(0.0, PYLON_H * 0.9, 0.0), structure)


## Conductors between two towers. Six horizontal segments stepped into a sag —
## a straight cable reads as a girder, and a real catenary needs a pitch the box
## batcher would rather not carry for scenery.
func _catenary(from: Vector3, to: Vector3) -> void:
	var segments: int = 6
	var span: float = to.x - from.x
	for offset: float in [-10.0, 10.0, -7.0, 7.0]:
		var top: float = PYLON_H * (0.72 if absf(offset) > 8.5 else 0.9)
		for i: int in segments:
			var t: float = (float(i) + 0.5) / float(segments)
			var sag: float = 6.0 * sin(t * PI)
			_prop_box(Vector3(span / float(segments) + 0.2, 0.35, 0.35),
					Vector3(from.x + span * t, from.y + top - sag, from.z + offset))


func _build_wind_farm() -> void:
	for i: int in TURBINE_COUNT:
		_turbine(TURBINE_AT + Vector3(float(i) * TURBINE_SPACING, 0.0,
				float(i % 2) * 90.0), float(i) * 0.7)
	_sign("WIND TURBINE\n135M TO TIP",
			TURBINE_AT + Vector3(TURBINE_SPACING * 1.5, 52.0, 130.0), 520.0)


func _turbine(at: Vector3, phase: float) -> void:
	var courses: int = 6
	var rise: float = TURBINE_HUB_H / float(courses)
	for i: int in courses:
		var t: float = float(i) / float(courses)
		var w: float = lerpf(4.5, 2.6, t)
		_solid(Vector3(w, rise, w), at + Vector3(0.0, rise * (0.5 + float(i)), 0.0),
				structure)
	var hub: Vector3 = at + Vector3(0.0, TURBINE_HUB_H, 0.0)
	_solid(Vector3(3.6, 3.6, 12.0), hub + Vector3(0.0, 0.0, 1.0), prop)
	# Three blades in the XY plane, so the rotor faces the pad.
	for i: int in 3:
		var theta: float = phase + TAU * float(i) / 3.0
		var radial := Vector3(cos(theta), sin(theta), 0.0)
		_batch.add_transformed(Vector3(TURBINE_BLADE_L, 2.6, 0.7),
				Transform3D(Basis(Vector3.BACK, theta),
						hub + radial * (TURBINE_BLADE_L * 0.5 - 1.0) + Vector3(0.0, 0.0, -5.0)),
				prop)


func _build_mast() -> void:
	var courses: int = 10
	var rise: float = MAST_H / float(courses)
	for i: int in courses:
		_solid(Vector3(MAST_W, rise, MAST_W),
				MAST_AT + Vector3(0.0, rise * (0.5 + float(i)), 0.0), structure)
	# Platforms, which is what makes a mast read as a mast rather than a pole.
	for level: float in [0.35, 0.62, 0.88]:
		_solid(Vector3(MAST_W * 2.6, 0.6, MAST_W * 2.6),
				MAST_AT + Vector3(0.0, MAST_H * level, 0.0), structure)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var anchor: Vector3 = MAST_AT + Vector3(cos(a) * 70.0, 0.0, sin(a) * 70.0)
		_strut(MAST_AT + Vector3(0.0, MAST_H * 0.9, 0.0), anchor, 0.5, prop)
	_sign("RADIO MAST
150M", MAST_AT + Vector3(0.0, 26.0, 34.0), 420.0)


## 240 m of span with 32 m of air under it. The clearance is the number that
## matters: it is the first object in the game whose gap is worth judging.
func _build_bridge() -> void:
	var half: float = BRIDGE_SPAN * 0.5
	_solid(Vector3(BRIDGE_DECK_W, 2.0, BRIDGE_SPAN + 80.0),
			BRIDGE_AT + Vector3(0.0, BRIDGE_CLEARANCE + 1.0, 0.0), structure)
	for end: float in [-1.0, 1.0]:
		var tower: Vector3 = BRIDGE_AT + Vector3(0.0, 0.0, end * half)
		for side: float in [-1.0, 1.0]:
			_solid(Vector3(3.0, BRIDGE_TOWER_H, 3.5),
					tower + Vector3(side * BRIDGE_DECK_W * 0.5, BRIDGE_TOWER_H * 0.5, 0.0),
					structure)
			for i: int in 4:
				var top: float = BRIDGE_TOWER_H - float(i) * 7.0
				var reach: float = half * (0.35 + 0.2 * float(i))
				_strut(tower + Vector3(side * BRIDGE_DECK_W * 0.5, top, 0.0),
						BRIDGE_AT + Vector3(side * BRIDGE_DECK_W * 0.5,
								BRIDGE_CLEARANCE + 2.0, end * (half - reach)), 0.45, prop)
		_solid(Vector3(BRIDGE_DECK_W + 4.0, 4.0, 5.0),
				tower + Vector3(0.0, BRIDGE_CLEARANCE, 0.0), structure)
	_sign("BRIDGE 240M SPAN\n32M CLEARANCE",
			BRIDGE_AT + Vector3(0.0, BRIDGE_TOWER_H + 10.0, 0.0), 440.0)


## The altitude ruler. Poles rather than markers because a pole is readable from
## anywhere in the map: fly level with a labelled tip and you know your height
## without reading an instrument.
func _build_height_comb() -> void:
	for i: int in COMB_HEIGHTS.size():
		var height: float = COMB_HEIGHTS[i]
		var at: Vector3 = COMB_AT + Vector3(
				(float(i) - float(COMB_HEIGHTS.size() - 1) * 0.5) * COMB_SPACING,
				0.0, 0.0)
		_solid(Vector3(COMB_POLE_W, height, COMB_POLE_W),
				at + Vector3(0.0, height * 0.5, 0.0), paint)
		_solid(Vector3(COMB_POLE_W * 5.0, 0.8, COMB_POLE_W * 5.0),
				at + Vector3(0.0, height, 0.0), paint)
		# THIS IS THE USER'S OWN EXAMPLE OF THE HOUSE RULE, made literal: *"the
		# sign of a 400m height platform may be bigger to be seen from afar."*
		# The read distance IS the pole's height, so a 400 m tip carries a sign
		# built to be read from 400 m and the 10 m pole carries one you read from
		# the pad. A fixed glyph size would make the tall end of a ruler its
		# worst end. The floor keeps the short poles legible from the apron.
		_sign("%dM" % int(height), at + Vector3(0.0, height + 2.0 + height * 0.04, 0.0),
				maxf(150.0, height * 1.3))


func _build_gate_course() -> void:
	for gate: Array in GATES:
		var aperture: float = float(gate[0])
		var at := Vector3(float(gate[1]), float(gate[2]), float(gate[3]))
		_gate(at, aperture)
		_sign("%dM" % int(aperture),
				at + Vector3(0.0, aperture * 0.5 + GATE_BAR + 3.0, 0.0),
				aperture * 5.0)
	# OFF THE PAD'S FORWARD AXIS, deliberately. Dead ahead at 122 m it stacked
	# straight onto the apron's own title from the one viewpoint every flight
	# starts at — the crowding the deleted visibility gate used to hide, showing
	# up the moment it was removed. Moved beside the first gate instead, which is
	# also where a course sign belongs.
	_sign("GATE COURSE", Vector3(-105.0, 44.0, -150.0), 190.0)


## Four solid bars around a square opening — the arena gate's grammar, sized for
## a 3 m aircraft instead of a 0.28 m one.
func _gate(at: Vector3, aperture: float) -> void:
	var reach: float = (aperture + GATE_BAR) * 0.5
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(aperture + GATE_BAR * 2.0, GATE_BAR, GATE_BAR),
				at + Vector3(0.0, side * reach, 0.0), gate_material)
		_solid(Vector3(GATE_BAR, aperture, GATE_BAR),
				at + Vector3(side * reach, 0.0, 0.0), gate_material)


# -----------------------------------------------------------------------------
# Primitives
# -----------------------------------------------------------------------------

## A box you can hit: batched for drawing, with its own collider.
func _solid(size: Vector3, at: Vector3, material: Material, yaw: float = 0.0) -> void:
	_batch.add(size, at, material, yaw)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(body)


## Scenery with no collider: people, cars, cables. Deliberately intangible —
## a 500 kg aircraft bouncing off a pedestrian is a worse lie than flying
## through one, and neither is what this map is for.
func _prop_box(size: Vector3, at: Vector3, yaw: float = 0.0) -> void:
	_batch.add(size, at, prop, yaw)


## Ground paint: no collider, and the caller supplies the material because the
## runway's surface and its markings are the same shape at different darknesses.
func _paint_strip(size: Vector3, at: Vector3, material: Material = null,
		yaw: float = 0.0) -> void:
	_batch.add(size, at, paint if material == null else material, yaw)


func _strut(from: Vector3, to: Vector3, thickness: float, material: Material) -> void:
	var delta: Vector3 = to - from
	var length: float = delta.length()
	if length <= 0.01:
		return
	var up: Vector3 = Vector3.UP
	if absf(delta.normalized().dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	_batch.add_transformed(Vector3(thickness, thickness, length),
			Transform3D(Basis.looking_at(delta, up), from + delta * 0.5), material)


# -----------------------------------------------------------------------------
# Signs
# -----------------------------------------------------------------------------

## THE HOUSE RULE (L.q10, the user's ruling 2026-08-13): **world text is an
## OBJECT, not a label.** *"it always feels wrong where the text aligns to me, it
## should take physical space and true volume, like big signs."* A sign does not
## turn to face you and does not vanish when you get close. It is built, it has a
## plate and posts, and it is there whether you are looking at it or not.
##
## THIS REVERSES WHAT THIS FILE USED TO DO, and the thing it replaces is worth
## keeping on the record because it was solving a real problem. Every label used
## to billboard toward the camera and switch off outside a distance window — the
## window existed because roughly forty labels, each a solid 3D object that does
## not shrink the way UI text would, stacked the far half of the map into an
## unreadable wall of glyphs across the horizon. Deleting the window without
## replacing the mechanism would bring that horizon straight back.
##
## **The replacement is the user's own principle and it is better: a sign is
## SIZED BY THE DISTANCE IT IS MEANT TO BE READ FROM.** *"the height of a human
## is a small text sign hovers over it, the sign of a 400m height platform may be
## bigger to be seen from afar."* That is what real signage does, and it fixes
## the crowding physically rather than by a visibility rule:
##
##  - A sign for a thing you read at 30 m is 0.05 m per font pixel — about three
##    metres of text. From 600 m away it is four arc-minutes wide. It does not
##    need hiding; it is simply small, exactly as a house number is.
##  - A sign for a thing you read at 500 m is genuinely huge, and it is huge AT
##    ITS OWN OBJECT, out where nothing near you is competing with it.
##  - The old scheme had no relationship between the two numbers at all, so a
##    distant object's label was authored at whatever size looked good on the pad
##    and then competed with everything in front of it forever.
##
## `READ_RATIO` is the whole law: `pixel_size = read_distance / READ_RATIO`, so a
## glyph (seven pixels tall) subtends `7 / 600` radians = **0.67 degrees** at the
## distance it was built for. That is four to eight times more generous than real
## road signage, deliberately: this is a 5x7 dot-matrix font with gaps between
## the dots and a bloom threshold on top, and it is calibrated on the number the
## human already flew — the deleted visibility gate called a sign readable out to
## 500 x its pixel size.
const READ_RATIO: float = 600.0
## Clear space around the text on its plate, in font pixels.
const SIGN_MARGIN_PX: float = 3.0
const SIGN_MIN_THICKNESS: float = 0.25


## Build a sign. `read_m` is the distance it is meant to be legible from and is
## the ONLY size control — there is no pixel size to author, on purpose, because
## an authored glyph size is exactly how the old scheme drifted away from the
## world it was labelling.
##
## `faces` is the point the sign is read from, defaulting to the pad. It is
## resolved ONCE, at build time, into a fixed yaw: the sign is turned toward its
## approach the way a real one is bolted facing the road, and then it never moves
## again.
##
## **Both faces carry text**, and that is a decision rather than an oversight.
## The rule is that a sign must not TURN, not that it must be readable from one
## side; a map whose whole purpose is flying around objects and looking at them
## would be hostile if half its signage were blank from the far side. Two faces
## on one plate is what a real double-sided sign is, and it works here where the
## first attempt failed for a reason worth remembering: two coplanar copies are
## read through each other's mirror image. These two are separated by the plate's
## own thickness, and the plate is opaque, so only one is ever visible. Signed off
## by the user on sight: *"the dual side of them is great."*
##
## **A SIGN HAS NO LEGS**, and that is the user's call after flying it: *"the
## signs can float in space, no need for legs."* The first version put posts under
## any plate low enough to reach the ground, on the reasoning that an object needs
## a mount to read as an object. It does not — the plate has volume, it holds a
## fixed bearing and it never moves, which is the whole of L.q10's rule. The legs
## were an argument about realism that the rule never made, and they cost the map
## a forest of posts around the ruler row.
func _sign(text: String, at: Vector3, read_m: float,
		faces: Vector3 = Vector3.ZERO, color: Color = LABEL_COLOR) -> void:
	var pixel: float = read_m / READ_RATIO
	var offset: Vector3 = faces - at
	var yaw: float = atan2(offset.x, offset.z)
	var lines: PackedStringArray = text.split("\n")
	var columns: int = 0
	for line: String in lines:
		columns = maxi(columns, line.length())
	var width: float = float(columns * GlowText3D.CHAR_PITCH - 1) * pixel
	var height: float = float(lines.size() * GlowText3D.LINE_PITCH - 1) * pixel
	var plate := Vector3(width + SIGN_MARGIN_PX * 2.0 * pixel,
			height + SIGN_MARGIN_PX * 2.0 * pixel,
			maxf(SIGN_MIN_THICKNESS, pixel * 1.5))
	_batch.add(plate, at, sign_material, yaw)
	# One glyph plane just clear of each face. The gap is a fraction of the plate
	# rather than a constant: at pixel 0.04 a fixed 0.1 m would float the text off
	# its own board, and at pixel 0.9 a fixed 0.1 m would bury it inside.
	var normal := Vector3(sin(yaw), 0.0, cos(yaw))
	var clearance: float = plate.z * 0.5 + pixel * 0.6
	for side: float in [1.0, -1.0]:
		var glyphs := GlowText3D.new()
		glyphs.text = text
		glyphs.pixel_size = pixel
		glyphs.glow_color = color
		glyphs.cast_shadows = false
		glyphs.position = at + normal * side * clearance
		# The far face is turned a half-turn so its text reads the right way
		# round from behind, which is the difference between a double-sided sign
		# and one sign seen through itself.
		glyphs.rotation.y = yaw if side > 0.0 else yaw + PI
		add_child(glyphs)
