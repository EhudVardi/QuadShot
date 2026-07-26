extends SceneTree

## Composed-sortie trace: generates a theater, runs it forward, and prints the
## sorties the war is OFFERING — the readable companion to
## sortie_compose_check.gd's assertions (see the fights, don't just assert
## about them). The P2 twin of war_trace.gd.
##
## It prints each strikeable node as the composer sees it: archetype and
## objective, the layered garrison, what is held back and what springs it, the
## approach, and the H.q2 difficulty INPUTS — never a difficulty score, which
## is the harness's to measure (H6).
##
## It also prints the BRIEFING beside the TRUTH for a fogged node, which is
## the one thing only a trace can show: the same function, two evaluations,
## diverging exactly as much as your intel is stale.
##
## Run: <godot> --headless -s scripts/tests/sortie_trace.gd --path .
##      <godot> --headless -s scripts/tests/sortie_trace.gd --path . -- 4242 30

const DEFAULT_SEED: int = 2003
const DEFAULT_TICKS: int = 30
const SKILL: float = 0.9


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else DEFAULT_SEED
	var ticks: int = int(args[1]) if args.size() > 1 else DEFAULT_TICKS

	var config: WarConfig = load("res://resources/default_war_config.tres") as WarConfig
	var state: Dictionary = TheaterGenerator.generate(config, seed_value)
	for tick: int in ticks:
		WarSim.tick(state, config, SKILL)
		if WarSim.winner(state) != &"":
			break

	var escalation: float = WarSim.escalation(state, config)
	print("[sortie_trace] seed %d, tick %d, escalation %.2f, %d pilots"
			% [seed_value, int(state["tick"]), escalation, int(state["pilots"])])
	print("[sortie_trace] ------------------------------------------------------------")

	var shown: int = 0
	var slice_ready: int = 0
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy":
			continue
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if SortieComposer.is_slice_ready(spec):
			slice_ready += 1
		_print_spec(spec)
		shown += 1
	print("[sortie_trace] ------------------------------------------------------------")
	print("[sortie_trace] %d enemy nodes offering fights, %d of them slice-ready "
			% [shown, slice_ready] + "(P2.13: Strike + Dogfight)")

	_print_fog_comparison(state, config)
	quit(0)


func _print_spec(spec: Dictionary) -> void:
	var inputs: Dictionary = spec["difficulty_inputs"]
	print("[sortie_trace] node %2d  %-9s → %-12s %s"
			% [int(spec["node_id"]), spec["node_type"], spec["archetype"],
			"CAPTURE" if bool(spec["capture"]) else "degrade only"])
	print("[sortie_trace]           objective: %s%s   biome %s / %s"
			% [spec["objective"],
			"" if int(spec["objective_assets"]) == 0
			else " ×%d" % int(spec["objective_assets"]),
			spec["biome"], spec["weather"]])
	for layer: StringName in SortieComposer.LAYER_ORDER:
		var units: Array = spec["layers"][layer]
		if not units.is_empty():
			print("[sortie_trace]           %-5s  %s" % [layer, _units(units)])
	for trigger: Dictionary in spec["triggers"]:
		print("[sortie_trace]           +%-4s on %-17s after %4.1fs  %s"
				% ["w%d" % int(trigger["wave"]), trigger["on"],
				float(trigger["after_s"]), _units(trigger["units"])])
	var approach: Dictionary = spec["approach"]
	print("[sortie_trace]           ingress %.0fm, %d corridor(s), cover %.2f"
			% [float(approach["ingress_m"]), int(approach["corridors"]),
			float(approach["cover"])]
			+ ", %d pad(s)%s" % [int(spec["pads"]),
			", 1 dare" if not spec["dares"].is_empty() else ""])
	# The H.q2 vector: WHY this node is hard. No composite — H6 keeps SDI a
	# measurement, and the composer never grades its own output.
	print("[sortie_trace]           inputs: garrison %.1f · cover %.2f · %s(%.2f) "
			% [float(inputs["garrison_strength"]), float(inputs["cover"]),
			inputs["weather"], float(inputs["weather_penalty"])]
			+ "· pads %d · esc %.2f · fort %.2f  [total fieldable %.1f]"
			% [int(inputs["pads"]), float(inputs["escalation"]),
			float(inputs["fortification"]), SortieComposer.total_strength(spec)])


## The P2.1 double evaluation, side by side — the thing only a trace shows.
func _print_fog_comparison(state: Dictionary, config: WarConfig) -> void:
	var target: Dictionary = {}
	for node: Dictionary in state["nodes"]:
		if node["owner"] == &"enemy" and int(node["intel_age"]) > 5:
			target = node
			break
	if target.is_empty():
		print("[sortie_trace] (no node stale enough to show the fog split)")
		return
	print("[sortie_trace] ")
	print("[sortie_trace] BRIEFING vs TRUTH — node %d, intel %d ticks old"
			% [int(target["id"]), int(target["intel_age"])])
	var briefing: Dictionary = SortieComposer.compose_briefing(target, state, config)
	var truth: Dictionary = SortieComposer.compose(target, state, config)
	print("[sortie_trace]   briefing (%s): %s"
			% [briefing["garrison_detail"], _fog_line(briefing)])
	print("[sortie_trace]   truth        : %s" % _all_units(truth))
	print("[sortie_trace]   ^ the surprise is DESIGNED: fly recon or fly blind (P1.3)")


func _fog_line(briefing: Dictionary) -> String:
	var intel: Dictionary = briefing.get("intel", {})
	if briefing["garrison_detail"] == &"exact":
		return _all_units(briefing)
	if briefing["garrison_detail"] == &"families":
		var parts: PackedStringArray = []
		for family: StringName in intel.get("families", {}):
			parts.append("%s ~%.1f" % [family, float(intel["families"][family])])
		return ", ".join(parts)
	return "strength ~%.1f (no composition resolved)" % float(briefing["garrison_strength"])


## Everything the node can field, merged per type — the briefing's opposite
## number, so the two lines compare like for like instead of listing the same
## raiders once per ring and once per wave.
func _all_units(spec: Dictionary) -> String:
	var totals: Dictionary = {}
	var groups: Array = []
	for layer: StringName in SortieComposer.LAYER_ORDER:
		groups.append(spec["layers"][layer])
	for trigger: Dictionary in spec["triggers"]:
		groups.append(trigger["units"])
	for group: Array in groups:
		for unit: Dictionary in group:
			var entry: Dictionary = totals.get(unit["type"],
					{"type": unit["type"], "count": 0, "bodies": 0})
			entry["count"] = int(entry["count"]) + int(unit["count"])
			entry["bodies"] = int(entry["bodies"]) + int(unit["bodies"])
			totals[unit["type"]] = entry
	var merged: Array = []
	for type_id: StringName in WarManifest.ROSTER:
		if totals.has(type_id):
			merged.append(totals[type_id])
	return _units(merged)


func _units(units: Array) -> String:
	if units.is_empty():
		return "—"
	var parts: PackedStringArray = []
	for unit: Dictionary in units:
		var label: String = "%d×%s" % [int(unit["count"]), unit["type"]]
		# A swarm's unit is the pack, so say how many bodies that actually is.
		if int(unit["bodies"]) != int(unit["count"]):
			label += "(%d)" % int(unit["bodies"])
		parts.append(label)
	return " ".join(parts)
