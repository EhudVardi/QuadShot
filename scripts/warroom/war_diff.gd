class_name WarDiff
extends RefCounted

## WHAT THE TICK DID, computed by comparing two snapshots (Iteration 13, C8).
##
## The obvious way to animate a war tick is to have `WarSim.tick` emit an event
## list as it works. That would be a mistake: it puts presentation concerns
## inside the one module whose purity is load-bearing for determinism, the
## portable save (F4) and the soak.
##
## Diffing costs nothing and is strictly better. `war/` stays pure, the animation
## is DERIVED from the state rather than narrated alongside it — so it cannot
## disagree with the war it is describing — and the differ is testable without a
## viewport, which an event stream emitted mid-tick would not be.
##
## Deep-copy the state before resolving, resolve, compare. That is the whole
## mechanism.

const KIND_CAPTURED: StringName = &"captured"
const KIND_LOST: StringName = &"lost"
const KIND_REINFORCED: StringName = &"reinforced"
const KIND_WEAKENED: StringName = &"weakened"

## Garrison movement below this is not worth animating — the tick nudges almost
## every node by a rounding-sized amount, and thirty simultaneous twitches read
## as noise rather than as the war moving.
const GARRISON_EPSILON: float = 0.05

## Ownership changes lead. They are the thing the player actually cares about,
## and staggering them first means the eye is drawn to the front before the
## quieter strength changes start.
const KIND_ORDER: Array[StringName] = [
	KIND_CAPTURED, KIND_LOST, KIND_WEAKENED, KIND_REINFORCED,
]


## An ordered, serializable list of what moved. Empty when nothing did.
static func between(before: Dictionary, after: Dictionary) -> Array:
	var was: Dictionary = {}
	for node: Dictionary in before.get("nodes", []):
		was[int(node["id"])] = node

	var events: Array = []
	for node: Dictionary in after.get("nodes", []):
		var id: int = int(node["id"])
		if not was.has(id):
			continue
		var old: Dictionary = was[id]
		var owner_before: StringName = old["owner"]
		var owner_after: StringName = node["owner"]
		var garrison_before: float = float(old["garrison"])
		var garrison_after: float = float(node["garrison"])

		var kind: StringName = &""
		if owner_before != owner_after:
			# Named from the PLAYER's side of the table, because the map is read
			# from there: ground turning green is a capture whoever did it.
			kind = KIND_CAPTURED if owner_after == &"player" else KIND_LOST
		elif absf(garrison_after - garrison_before) > GARRISON_EPSILON:
			kind = KIND_REINFORCED if garrison_after > garrison_before \
					else KIND_WEAKENED
		if kind == &"":
			continue
		events.append({
			"node_id": id,
			"kind": kind,
			"owner_before": owner_before,
			"owner_after": owner_after,
			"garrison_before": WarSim.quantize(garrison_before),
			"garrison_after": WarSim.quantize(garrison_after),
		})

	# Stable: by kind priority, then by node id. Two runs of the same tick play
	# the same animation, which is F4's determinism reaching the screen.
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a: int = KIND_ORDER.find(a["kind"])
		var rank_b: int = KIND_ORDER.find(b["kind"])
		if rank_a == rank_b:
			return int(a["node_id"]) < int(b["node_id"])
		return rank_a < rank_b)
	return events


## One line for the map's caption while the tick plays.
static func summary(events: Array) -> String:
	if events.is_empty():
		return "the front did not move"
	var counts: Dictionary = {}
	for event: Dictionary in events:
		counts[event["kind"]] = int(counts.get(event["kind"], 0)) + 1
	var parts: PackedStringArray = []
	for kind: StringName in KIND_ORDER:
		if counts.has(kind):
			parts.append("%d %s" % [int(counts[kind]), kind])
	return " - ".join(parts)
