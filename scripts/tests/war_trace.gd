extends SceneTree

## Single-theater trace: runs one war with a proxy pilot and prints the
## strategic picture every TRACE_EVERY ticks — the debugging companion to
## war_soak.gd's statistics (watch one war instead of averaging hundreds).
##
## Run: <godot> --headless -s scripts/tests/war_trace.gd --path .

const SEED: int = 2003
const SKILL: float = 0.9
const TRACE_EVERY: int = 25


func _initialize() -> void:
	var config: WarConfig = load("res://resources/default_war_config.tres") as WarConfig
	var state: Dictionary = TheaterGenerator.generate(config, SEED)
	print("[war_trace] seed %d skill %.1f aggression %.2f"
			% [SEED, SKILL, float(state["aggression"])])
	_snapshot(state, config)
	while WarSim.winner(state) == &"":
		WarSim.tick(state, config, SKILL)
		if int(state["tick"]) % TRACE_EVERY == 0:
			_snapshot(state, config)
	_snapshot(state, config)
	print("[war_trace] ENDED: %s after %d ticks, %d sorties, %d pilots left"
			% [WarSim.winner(state), int(state["tick"]), int(state["sorties"]),
			int(state["pilots"])])
	quit(0)


func _snapshot(state: Dictionary, config: WarConfig) -> void:
	var player_nodes: int = 0
	var enemy_strength: float = 0.0
	var player_strength: float = 0.0
	var commands: int = 0
	var hq_in_range: bool = false
	var in_range: Dictionary = WarSim._strike_range(state, config)
	for node: Dictionary in state["nodes"]:
		if node["owner"] == &"player":
			player_nodes += 1
			player_strength += float(node["garrison"])
		else:
			enemy_strength += float(node["garrison"])
		if node["type"] == &"command" and node["owner"] == &"enemy" \
				and float(node["garrison"]) >= 1.0:
			commands += 1
		if node["hq"] and in_range.has(int(node["id"])):
			hq_in_range = true
	print("[war_trace] t=%3d nodes=%2d/%d str=%5.0f vs %5.0f cmd=%d hq_in_range=%s pilots=%d sorties=%d"
			% [int(state["tick"]), player_nodes, (state["nodes"] as Array).size(),
			player_strength, enemy_strength, commands, str(hq_in_range),
			int(state["pilots"]), int(state["sorties"])])
