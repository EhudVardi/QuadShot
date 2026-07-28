class_name Jamming
extends RefCounted

## Electronic warfare, as one number (GAMEPLAY-DESIGN P4.2 Screamer, S14).
##
## Every EW effect in the game is the SAME scalar read in a different place:
## 0 = clean, 1 = fully jammed. The gun director's solution window shrinks by it,
## the missile's lock builds slower and refuses outright at full strength, the
## flak fuse degrades toward contact-only, and the video feed breaks up. One
## number, four consumers — which is exactly what D6 predicted when it noted that
## "EW *and* battle damage both degrade FCS — one mechanism".
##
## IT FADES WITH DISTANCE, and that is the user's call over my own lean (S.q8,
## 2026-07-28). I argued for a hard bubble edge from S7's rule that a step must
## never be smeared into a slope to look continuous; the user's reading is that a
## *sensor* warning is precisely where a gradient belongs, and S7 is about not
## smearing a decision BOUNDARY, which this is not. The gradient also earns its
## keep in the fight: the screamer's counterplay is to close and kill it, so a
## jam that strengthens as you close makes the approach itself the cost. A binary
## bubble would have made that approach free right up to the edge.
##
## Where a step DOES remain, deliberately: `Weapon.director_active()`. Whether the
## pilot reaches for the manual trigger is a decision, and a decision needs an
## edge (see DIRECTOR_MIN_M there).
##
## ONLY THE PLAYER IS JAMMED. The bestiary's own aim and the balance benches'
## perfect shooters are untouched, because nothing in the roster fields an EW
## asset against the enemy — the day something does, this is the file that grows
## a team argument rather than every consumer growing one.

## Group every jamming emitter joins. Members must expose
## `jam_level_at(point: Vector3) -> float`, so the FALLOFF SHAPE belongs to the
## type rather than to this file: a second EW type with a different profile costs
## nothing here.
const GROUP: StringName = &"jammers"

## BENCH HOOK, and the same idea as `Weapon.fire_override`: >= 0 forces the level
## the whole game reads, ignoring whatever is in the tree.
##
## It exists because a delivery cell must STATE its jam the way it already states
## its jink mode (ReferencePilot.Jink) — otherwise the arena picks the number, and
## v1.78's first Layer 3b attempt is the standing lesson about what that costs.
## The jam state is also DISCRETE in the model (`clear` / `jammed`) even though
## the field is graded, on the exact precedent of `Lethality.STATES`: a shield is
## a continuous pool modeled as two states, and for the same reason — the two ends
## are what a weapon's answer inverts between, and averaging them destroys both.
##
## The real field is exercised by `screamer_check.gd`, so the two cannot drift:
## the check verifies the emitter, the bench measures the effect.
static var bench_override: float = -1.0


## The strongest jam reaching `node`, 0..1. Null-safe and tree-safe: a node
## outside the tree (or a bench with no arena) reads clean rather than crashing,
## the same contract SoundBank's static API keeps.
static func level_at(node: Node3D) -> float:
	if bench_override >= 0.0:
		return clampf(bench_override, 0.0, 1.0)
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return 0.0
	var tree: SceneTree = node.get_tree()
	if tree == null:
		return 0.0
	var point: Vector3 = node.global_position
	var worst: float = 0.0
	for emitter: Node in tree.get_nodes_in_group(GROUP):
		var source: Node3D = emitter as Node3D
		if source == null or not is_instance_valid(source) \
				or source.is_queued_for_deletion():
			continue
		worst = maxf(worst, float(source.call(&"jam_level_at", point)))
		if worst >= 1.0:
			# Saturated: nothing a second emitter says can raise it, and the
			# roster's densest planned formation is a pair (P4.3's aegis+screamer).
			return 1.0
	return clampf(worst, 0.0, 1.0)


## The shared falloff: 1 inside `full_range`, fading to 0 at `range_m`, and 0
## outside it. Linear on purpose — a curve here would be a second tuning surface
## nobody asked for, and the two radii already say everything the shape needs to.
##
## Emitters call this rather than rolling their own, so "how strong is the jam
## here" has one definition even once the roster has two jammers.
static func falloff(distance: float, full_range: float, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	if distance <= full_range:
		return 1.0
	if distance >= range_m:
		return 0.0
	return clampf((range_m - distance) / maxf(range_m - full_range, 0.001),
			0.0, 1.0)
