extends Node3D

## THE WAR ROOM (GAMEPLAY-DESIGN Iteration 13, P1.8) — the between-sorties
## screen, where the theater lives.
##
## PHASE 1 OF FIVE (C9): the map that reads. It loads the campaign, lays the
## theater out as a hex table, and lets you move a selection over it. It does
## NOT launch a sortie, does not tick the war, and does not write the save —
## those are phases 3 and 4, and the discipline of not building them early is
## what keeps this iteration from becoming one enormous untested screen.
##
## The card is deliberately thin for the same reason. It shows what a node IS
## and whether it can be flown; the intel-fogged garrison estimate is phase 2,
## and showing the raw garrison here would teach the player a number that P1.3
## says they are not supposed to have. A placeholder that lies is worse than a
## placeholder that is quiet.
##
## READ-ONLY, DELIBERATELY. This scene opens `user://war.save` and never writes
## it, so looking at the map cannot cost you a campaign no matter what happens
## next. That stops being true in phase 3, which is exactly when the check that
## counts saves gets written.

const MENU_SCENE: String = "res://scenes/menu_tower.tscn"

## Camera pitch, measured down from the horizon. Steep enough that tall prisms
## do not hide the short ones behind them, shallow enough that height still
## reads as height rather than as a slightly bigger hexagon.
const CAMERA_PITCH_DEG: float = 62.0
## Slack around the theater's bounding box so the outermost hexes are not
## clipped by the frame.
const CAMERA_MARGIN: float = 1.25
## How near the cursor has to be to a hex top, in pixels, to select it.
const PICK_RADIUS_PX: float = 70.0

@export var theater_seed: int = 4242
## Resume `user://war.save` if there is one. `--fresh` clears it first.
@export var persist: bool = true

@onready var _camera: Camera3D = $Camera
@onready var _table: HexTable = $HexTable
@onready var _header: Label = $Ui/Header
@onready var _card: Label = $Ui/Card/Text
@onready var _legend: Label = $Ui/Legend

var _state: Dictionary = {}
var _config: WarConfig
var _reasons: Dictionary = {}
var _selected: int = -1


func _ready() -> void:
	_read_command_line()
	_config = WarConfig.new()
	_state = WarSave.load_or_new(_config, theater_seed) if persist \
			else TheaterGenerator.generate(_config, theater_seed)
	if _state.is_empty():
		# `load_or_new` only returns nothing when a save was unreadable AND could
		# not be moved aside. Refusing beats generating a fresh war on top of one
		# we could not read (the v2.01 campaign-shredder, in its other half).
		push_error("[warroom] no war state - refusing to open a map over an unreadable save")
		_header.text = "NO CAMPAIGN - user://war.save is unreadable and was not replaced"
		return
	if persist and WarSave.exists():
		print("[war] resumed tick %d, %d pilots, %d sorties flown"
				% [int(_state["tick"]), int(_state["pilots"]), int(_state["sorties"])])
	_frame_camera()
	_rebuild()
	_select(_first_flyable())


func _read_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			theater_seed = int(args[i + 1])
		elif args[i] == "--fresh":
			WarSave.clear()
		elif args[i] == "--no-persist":
			persist = false


func _unhandled_input(event: InputEvent) -> void:
	if _state.is_empty():
		return
	# CLICK selects; hovering does not. Motion-to-select was written first and it
	# is wrong for a screen you read: the ring chases the cursor, so moving the
	# mouse toward the card changes the node the card is describing, and any
	# jiggle overrides an arrow-key selection. Phase 3 hangs a launch off this
	# selection, which makes "the thing I picked stays picked" load-bearing.
	if event is InputEventMouseButton and event.is_pressed() \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var picked: int = _pick_screen((event as InputEventMouseButton).position)
		if picked >= 0:
			_select(picked)
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	# Hex neighbours, walked by whichever one lies most nearly in the pressed
	# direction. Six neighbours and four keys never map cleanly; nearest-bearing
	# is the version that always goes somewhere sensible.
	if event.is_action_pressed(&"ui_up"):
		_step(Vector3.FORWARD)
	elif event.is_action_pressed(&"ui_down"):
		_step(Vector3.BACK)
	elif event.is_action_pressed(&"ui_left"):
		_step(Vector3.LEFT)
	elif event.is_action_pressed(&"ui_right"):
		_step(Vector3.RIGHT)


## ---------- the map ----------

func _rebuild() -> void:
	_reasons = WarView.refusals(_state, _config)
	_table.build(_state, _config, _camera.global_position)
	_update_header()
	_update_legend()


## Fit the whole theater in frame. The camera is fixed (C.q1) — so this runs
## once, and the glyphs are turned to face wherever it ended up.
func _frame_camera() -> void:
	var box: AABB = WarView.bounds(_state, HexTable.HEX_SIZE)
	var center: Vector3 = box.get_center()
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport.x / viewport.y if viewport.y > 0.0 else 16.0 / 9.0
	# Godot's `fov` is the VERTICAL angle, so the across-screen extent gets the
	# wider horizontal one for free — and a ground extent running away from the
	# camera lands on screen-vertical scaled by sin(pitch), because most of it is
	# depth. Framing on max(x, z) against the vertical fov alone (the first
	# version) pushed the camera back far enough to waste half the screen.
	var tan_v: float = tan(deg_to_rad(_camera.fov * 0.5))
	var need_v: float = (box.size.z * 0.5 * sin(pitch) + HexTable.HEIGHT_SPAN * 0.5) / tan_v
	var need_h: float = box.size.x * 0.5 / (tan_v * aspect)
	var distance: float = maxf(need_v, need_h) * CAMERA_MARGIN
	_camera.position = center + Vector3(0.0, sin(pitch) * distance,
			cos(pitch) * distance)
	_camera.look_at(center, Vector3.UP)
	_camera.far = maxf(_camera.far, distance * 3.0)


## Screen-space picking, not a ray onto the ground plane. A prism's TOP is what
## the eye aims at, and at this pitch a tall one's top sits most of a cell away
## from its own footprint — so a ground-plane ray would select the hex behind
## whichever one you were pointing at.
func _pick_screen(at: Vector2) -> int:
	var best: int = -1
	var best_distance: float = PICK_RADIUS_PX
	for id: int in _table.centers:
		var top: Vector3 = _table.top_of(id)
		if _camera.is_position_behind(top):
			continue
		var distance: float = _camera.unproject_position(top).distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


func _step(direction: Vector3) -> void:
	if _selected < 0:
		return
	var here: Dictionary = WarSim.node_by_id(_state, _selected)
	var from: Vector3 = WarView.node_world(here, HexTable.HEX_SIZE)
	var best: int = -1
	var best_dot: float = 0.35  # ignore neighbours that are barely that way
	for node: Dictionary in _state["nodes"]:
		if TheaterGenerator.hex_distance(
				Vector2i(int(here["q"]), int(here["r"])),
				Vector2i(int(node["q"]), int(node["r"]))) != 1:
			continue
		var offset: Vector3 = WarView.node_world(node, HexTable.HEX_SIZE) - from
		var score: float = direction.dot(offset.normalized())
		if score > best_dot:
			best_dot = score
			best = int(node["id"])
	if best >= 0:
		_select(best)


func _select(id: int) -> void:
	_selected = id
	_table.select(id)
	_update_card()


func _first_flyable() -> int:
	var flyable: Array = WarView.flyable_ids(_state, _config)
	if not flyable.is_empty():
		return int(flyable[0])
	return int(_state["nodes"][0]["id"]) if not _state["nodes"].is_empty() else -1


## ---------- the panels ----------

func _update_header() -> void:
	var flyable: int = WarView.flyable_ids(_state, _config).size()
	var line: String = "SEED %d   TICK %d   PILOTS %d   SORTIES FLOWN %d   %d/%d NODES FLYABLE" \
			% [int(_state["seed"]), int(_state["tick"]), int(_state["pilots"]),
			int(_state["sorties"]), flyable, _state["nodes"].size()]
	if _state["winner"] != &"":
		line += "\nTHE WAR IS OVER - %s" % String(_state["winner"]).to_upper()
	_header.text = line


func _update_legend() -> void:
	_legend.text = "\n".join(PackedStringArray([
		"height = garrison   green = yours   red = theirs   dim = out of range",
		"amber bar = front line   thin line = supply",
		"click or arrows select   ESC returns to the menu",
		"the card shows what INTEL believes, not what is there - fly it to find out",
		"PHASE 2 of the war room: the map reads and briefs, nothing launches yet",
	]))


## The card is rendered by `WarView.card_lines`, not here, so that the one bug it
## can have — showing truth the fog is supposed to be hiding — is asserted by a
## headless check instead of by someone noticing.
func _update_card() -> void:
	if _selected < 0:
		_card.text = "no node selected"
		return
	var node: Dictionary = WarSim.node_by_id(_state, _selected)
	if node.is_empty():
		_card.text = "no node selected"
		return
	_card.text = "\n".join(WarView.card_lines(node, _state, _config,
			_reasons.get(_selected, WarView.REASON_NONE)))
