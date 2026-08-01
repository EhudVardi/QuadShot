class_name WarLaunch

## Cross-scene handoff between the war room and a sortie (Iteration 13, C7).
##
## `change_scene_to_file` cannot carry arguments, so the room parks the target
## here on the way out and the sortie parks its result here on the way back —
## the same static-layer pattern as `MenuLaunch` and `RunMods`. Defaults mean a
## directly-booted `scenes/sortie.tscn` behaves exactly as it did before the room
## existed, which is what keeps TESTING.md's repro command alive.
##
## THE STATE ITSELF IS NOT CARRIED, and that is deliberate. Only the seed and
## whether to persist cross over, because the war is deterministic: given the
## same seed and the same save, the room and the sortie derive the same theater.
## Passing a live Dictionary between scenes would be a second copy of the war
## able to disagree with the file.
##
## A QUIT MID-SORTIE THEREFORE LOSES THE SORTIE, which is not a bug — it is
## P1.q4's "exit without save" decided in v1.6: the war reverts to the last
## war-room state, and it does so by nothing having happened.

## Set by the room before it leaves. False means the sortie was booted directly
## and must resolve the war itself.
static var from_room: bool = false
static var node_id: int = -1
static var theater_seed: int = 4242
static var persist: bool = true

## Set by the sortie on the way back. `flew` is the flag the room consumes: a
## sortie that was abandoned (signal lost, quit) hands back nothing, so the room
## simply redraws the war it already had.
static var flew: bool = false
static var result: Dictionary = {}


static func arm(node: int, seed_value: int, persist_save: bool) -> void:
	from_room = true
	node_id = node
	theater_seed = seed_value
	persist = persist_save
	flew = false
	result = {}


## Take the result, exactly once. The room clears as it consumes so returning to
## the map a second time cannot price the same sortie into the war twice.
static func take_result() -> Dictionary:
	var taken: Dictionary = result
	flew = false
	result = {}
	return taken


static func clear() -> void:
	from_room = false
	node_id = -1
	flew = false
	result = {}
