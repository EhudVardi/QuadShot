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
## (display name, body m, arm m, offset x, label height). The label heights are
## staggered on purpose: three signs 15 m wide on frames 7 m apart would overlap
## into one unreadable line if they shared an altitude.
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

var _batch := BoxBatcher.new()
## Every sign in the map, turned toward the pilot each frame by `_process`.
var _labels: Array[Node3D] = []


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
	_label("SCALE YARD", Vector3(0.0, 22.0, -32.0), 0.55)
	_label("1 KESTREL   2 CONDOR   3 ROC", Vector3(0.0, 15.0, -32.0), 0.3)


## The three flyable frames, parked, plus a person to stand them against.
func _build_ladder() -> void:
	for entry: Array in LADDER:
		var at: Vector3 = LADDER_AT + Vector3(float(entry[3]), 0.0, 0.0)
		_airframe(at, float(entry[1]), float(entry[2]))
		_label(String(entry[0]), at + Vector3(0.0, float(entry[4]), 0.0), 0.18)
	_person(LADDER_AT + Vector3(-3.5, 0.0, 0.0))
	_label("PERSON 1.75M", LADDER_AT + Vector3(-3.5, 3.2, 0.0), 0.13)


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
	_label("PERSON 1.75M", at + Vector3(0.0, PERSON_H + 3.0, 0.0), 0.2)


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
	_label("CAR 4.4M  ·  BAY 2.5X5M", at + Vector3(0.0, CAR_H + 3.5, 0.0), 0.22)


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
	_label("BUS 12M", at + Vector3(0.0, BUS_H + 3.5, 0.0), 0.24)


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
	_label("TRUCK 16.5M", at + Vector3(0.0, TRUCK_H + 3.5, 0.0), 0.24)


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
	_label("CONTAINER 12.19M", at + Vector3(0.0, CONTAINER_H * 2.0 + 3.5, 0.0), 0.26)


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
	_label("HOUSE 8.5M RIDGE", at + Vector3(0.0, HOUSE_RIDGE + 3.5, 0.0), 0.28)


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
			_label("APARTMENTS 6 FLOORS 18M", at + Vector3(0.0, height + 8.0, 0.0), 0.5)
		elif storeys == 17:
			_label("OFFICE 17 FLOORS 51M", at + Vector3(0.0, height + 12.0, 0.0), 0.8)
		elif storeys == 48:
			_label("TOWER 48 FLOORS 144M", at + Vector3(0.0, height + 18.0, 0.0), 1.3)


# -----------------------------------------------------------------------------
# The airfield — and the one comparison this whole map was built to make
# -----------------------------------------------------------------------------

func _build_airfield() -> void:
	_build_runway()
	_build_hangar()
	_airliner(NARROW_AT, NARROW_L, NARROW_SPAN, NARROW_TAIL_H, NARROW_FUSELAGE_D)
	_label("AIRLINER 37.6M LONG",
			NARROW_AT + Vector3(0.0, NARROW_TAIL_H + 8.0, 0.0), 0.6)
	_airliner(WIDE_AT, WIDE_L, WIDE_SPAN, WIDE_TAIL_H, WIDE_FUSELAGE_D)
	_label("WIDEBODY 70.6M LONG",
			WIDE_AT + Vector3(0.0, WIDE_TAIL_H + 9.0, 0.0), 0.7)


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
	_label("RUNWAY 45M WIDE  ·  1200M LONG",
			Vector3(0.0, 26.0, RUNWAY_Z), 0.8)


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
	_label("HANGAR DOOR 60X18M",
			HANGAR_AT + Vector3(0.0, HANGAR_H + 7.0, HANGAR_D * 0.5), 0.6)


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
	_label("FOOTBALL PITCH 105X68M", PITCH_AT + Vector3(0.0, 22.0, 0.0), 0.7)


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
	_label("PYLON 45M  ·  SPAN 220M",
			PYLON_START + Vector3(0.0, PYLON_H + 12.0, 0.0), 0.9)


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
	_label("WIND TURBINE 135M TO TIP",
			TURBINE_AT + Vector3(0.0, TURBINE_HUB_H + TURBINE_BLADE_L + 14.0, 0.0), 1.4)


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
	_label("RADIO MAST 150M", MAST_AT + Vector3(0.0, MAST_H + 14.0, 0.0), 1.4)


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
	_label("BRIDGE  ·  32M CLEARANCE  ·  240M SPAN",
			BRIDGE_AT + Vector3(0.0, BRIDGE_TOWER_H + 12.0, 0.0), 1.0)


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
		# Label size tracks the pole, so the 400 m tip is as readable as the 10 m
		# one — a fixed glyph would make the tall end of a ruler its worst end.
		# The floor is set so that even the 10 m pole's label survives the
		# distance gate from the pad; the comb is useless if half of it is dark.
		_label("%dM" % int(height), at + Vector3(0.0, height + 3.0 + height * 0.03, 0.0),
				maxf(0.35, height * 0.006))


func _build_gate_course() -> void:
	for gate: Array in GATES:
		var aperture: float = float(gate[0])
		var at := Vector3(float(gate[1]), float(gate[2]), float(gate[3]))
		_gate(at, aperture)
		_label("%dM" % int(aperture),
				at + Vector3(0.0, aperture * 0.5 + GATE_BAR + 4.0, 0.0),
				maxf(0.3, aperture * 0.03))
	_label("GATE COURSE", Vector3(0.0, 70.0, -150.0), 0.8)


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


## Neon glyphs that turn to face the pilot (yaw only, so text stays upright).
##
## THE FIRST VERSION PUT TWO COPIES BACK TO BACK and it was unreadable: the two
## are coplanar, so from either side you read one sign through its own mirror
## image. A fixed facing has the same defect more quietly — every label in the
## map is legible from the pad and mirrored from everywhere else, which for a
## map you fly AROUND is most of the time. Billboarding is the only version that
## is right from every angle, and it costs one yaw per label per frame.
func _label(text: String, at: Vector3, pixel: float,
		color: Color = LABEL_COLOR) -> void:
	var glyphs := GlowText3D.new()
	glyphs.text = text
	glyphs.pixel_size = pixel
	glyphs.glow_color = color
	glyphs.cast_shadows = false
	glyphs.position = at
	add_child(glyphs)
	_labels.append(glyphs)


## Turn every sign toward the pilot, and show only the ones at their own reading
## distance.
##
## THE SECOND HALF IS NOT POLISH. Roughly forty labels, each a solid 3D object
## that does not shrink with distance the way UI text would, all drawing at once:
## from the apron the far half of the map stacked its signage into an unreadable
## wall of glyphs across the horizon, and the near ones filled the screen when
## flown past. A label's `pixel_size` already states how big it was meant to be
## read at, so that same number gives the window for free — near limit so a sign
## you are on top of gets out of the way (you can see the OBJECT at that range),
## far limit so it stops competing with signs that are actually legible.
## The near limit is a multiple of the sign's WIDTH, not of its glyph size, and
## the difference is not academic: "1 KESTREL 0.28M" at pixel 0.18 is 16 m of
## text, so it needs about 26 m of standoff to fit in frame, while "10M" at the
## same pixel size needs four. Keying off glyph height alone let the long signs
## swallow the screen from inside their own supposedly-safe range.
const LABEL_NEAR_PER_WIDTH: float = 1.6
## The far limit IS a multiple of glyph size: text stops being readable when a
## glyph falls under roughly half a degree, and that is a height question.
##
## Set well INSIDE that readability limit on purpose. Forty signs that are merely
## legible is still forty signs, and from the pad the airfield's, the town's and
## the wind farm's all stacked into the same strip of horizon as the ones you
## were actually reading. At 500 each group announces itself as you approach it,
## which is what signage does.
const LABEL_FAR_PER_PIXEL: float = 500.0


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye: Vector3 = camera.global_position
	for glyphs: Node3D in _labels:
		var text: GlowText3D = glyphs as GlowText3D
		var offset: Vector3 = eye - glyphs.global_position
		var range_m: float = offset.length()
		var width: float = float(text.text.length()) \
				* float(GlowText3D.CHAR_PITCH) * text.pixel_size
		glyphs.visible = range_m >= width * LABEL_NEAR_PER_WIDTH \
				and range_m <= text.pixel_size * LABEL_FAR_PER_PIXEL
		if glyphs.visible:
			glyphs.rotation.y = atan2(offset.x, offset.z)
