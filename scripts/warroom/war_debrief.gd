class_name WarDebrief
extends RefCounted

## THE LOOP, CLOSED IN THE ROOM (Iteration 13, C.q2 — decided 2026-08-01).
##
## A flown sortie is priced into the war, then the war takes its turn. Both
## halves used to live in `sortie.gd`, which was right when the sortie scene was
## the only thing that existed and is wrong now: P1.8's sequence is
## `briefing -> fly -> debrief -> the tick plays out as animated map movement`,
## so the tick has to happen where the map is or the animation is replaying
## something that already happened somewhere else.
##
## Pure over the state Dictionary, like everything else that touches the war —
## it never saves, never touches a Node3D, and so the whole joint is assertable
## headless. The room saves after calling this, which is also the moment P1.q4
## defines: everything before it is still "exit without save".

## Resolve a flown sortie. Returns `{}` if the result names a node this war does
## not have, WITHOUT ticking — a bogus result must not be able to advance the
## war, and returning early is the only way that stays true.
static func resolve(state: Dictionary, config: WarConfig,
		result: Dictionary) -> Dictionary:
	var tick_before: int = int(state["tick"])
	var summary: Dictionary = WarSim.apply_sortie(state, config, result)
	if summary.is_empty():
		push_warning("[war] the node this sortie was composed from is gone")
		return {}

	# No proxy skill. The sim runs its own phases — production, supply, enemy
	# operations, weather, intel — WITHOUT inventing a second, abstract player
	# sortie on top of the real one just flown, which would double-count you.
	WarSim.tick(state, config)
	return {
		"summary": summary,
		"outcome": result.get("outcome", &"partial"),
		"kills": result.get("kills", {}),
		"objectives_destroyed": int(result.get("objectives_destroyed", 0)),
		"objective_assets": int(result.get("objective_assets", 0)),
		"egressed": bool(result.get("egressed", false)),
		"pilot_lost": bool(result.get("pilot_lost", false)),
		"tick_before": tick_before,
		"tick_after": int(state["tick"]),
		"pilots_left": int(state["pilots"]),
		"winner": state["winner"],
	}


## The debrief panel's text. Rendered to lines for the same reason the card is:
## it is then something a check can read.
##
## `saved` IS THE F7 FIX AND IT IS A PARAMETER RATHER THAN A ROOM DETAIL. The
## room used to apply the sortie, tick the war, build this text and show it, and
## only THEN attempt the write — using the `false` return to decide whether to
## print a line. A failed write therefore left the player watching the front move
## on a map whose next launch would reload the war from before the sortie.
##
## Saying so belongs here because this is the function that speaks to the player,
## and putting it here is what makes it assertable: a check can read the text and
## see the warning without a viewport, exactly as `WarView.card_lines` made the
## fog leak assertable.
static func lines(debrief: Dictionary, saved: bool = true) -> PackedStringArray:
	if debrief.is_empty():
		return PackedStringArray(["the sortie resolved against nothing"])
	var summary: Dictionary = debrief["summary"]
	var out: PackedStringArray = [
		"SORTIE %s" % String(debrief["outcome"]).to_upper(),
		"node %d   %s" % [int(summary["node_id"]),
				String(summary["node_type"]).to_upper()],
		"",
	]
	if int(debrief["objective_assets"]) > 0:
		out.append("objective %d of %d destroyed"
				% [int(debrief["objectives_destroyed"]),
				int(debrief["objective_assets"])])
	out.append("egress %s" % ("made" if bool(debrief["egressed"]) else "not made"))

	var kills: Dictionary = debrief["kills"]
	var killed: PackedStringArray = []
	for type_id: StringName in kills:
		killed.append("%dx %s" % [int(kills[type_id]), type_id])
	out.append("killed %s" % (" ".join(killed) if not killed.is_empty() else "nothing"))
	out.append("")
	# P2.q4 made visible: everything you destroyed dents the node whether you
	# completed the objective, aborted, or died on the way out.
	out.append("garrison %.1f -> %.1f   (dent %.1f)"
			% [float(summary["garrison_before"]), float(summary["garrison_after"]),
			float(summary["dent"])])
	if bool(summary["captured"]):
		out.append("THE NODE IS YOURS")
	elif bool(summary["degraded"]):
		out.append("degraded - no friendly ground adjacent to hold it")
	if bool(debrief["pilot_lost"]):
		out.append("PILOT LOST - %d left" % int(debrief["pilots_left"]))
	out.append("")
	if int(debrief["tick_after"]) > int(debrief["tick_before"]):
		out.append("the war moves to tick %d" % int(debrief["tick_after"]))
	if debrief["winner"] != &"":
		out.append("THE WAR IS OVER - %s" % String(debrief["winner"]).to_upper())
	# LAST, and loud. Everything above describes a war that moved; if the write
	# failed, none of it survives leaving the room, and the player is the only
	# one who can do anything about the disk.
	if not saved:
		out.append("")
		out.append("*** NOT SAVED - %s could not be written" % WarSave.PATH)
		out.append("*** this sortie is LOST if you leave the room")
	return out
