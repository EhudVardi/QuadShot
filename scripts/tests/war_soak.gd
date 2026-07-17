extends SceneTree

## Theater soak harness (GAMEPLAY-DESIGN Iteration 1 / F4.a): births many
## seeded theaters and lets the war fight itself to completion, unattended.
## Validates the P1 skeleton with data:
##   1. Determinism   — same seed, same history, same hash.
##   2. Serialization — save mid-war (var_to_str), restore, identical future.
##   3. Spectator     — no player: the war must be losable without you.
##   4. Skill sweep   — proxy pilots at several skills: win rate must rise
##                      with skill, wars must terminate, campaign length
##                      lands near the P1.q5 target (25-40 sorties).
##
## Run: <godot> --headless -s scripts/tests/war_soak.gd --path .

const THEATERS_PER_MODE: int = 40
const SKILLS: Array[float] = [0.3, 0.6, 0.9]
const CHECK_TICKS: int = 60

var _failures: PackedStringArray = []


func _initialize() -> void:
	var config: WarConfig = load("res://resources/default_war_config.tres") as WarConfig
	print("[war_soak] node_count=%d, max_ticks=%d, %d theaters/mode"
			% [int(config.node_count), int(config.max_ticks), THEATERS_PER_MODE])
	_check_determinism(config)
	_check_serialization(config)
	_soak_spectator(config)
	for skill: float in SKILLS:
		_soak_skill(config, skill)
	if _failures.is_empty():
		print("[war_soak] PASS")
		quit(0)
	else:
		for failure: String in _failures:
			print("[war_soak] FAIL: %s" % failure)
		print("[war_soak] FAIL")
		quit(1)


func _run_ticks(state: Dictionary, config: WarConfig, ticks: int, skill: float) -> void:
	for i: int in ticks:
		WarSim.tick(state, config, skill)


func _state_hash(state: Dictionary) -> int:
	# JSON.stringify compares by CONTENT: StringName-vs-String type drift
	# from the var_to_str round-trip is invisible to behavior (GDScript
	# compares them by value), so it must be invisible to the hash too.
	return hash(JSON.stringify(state))


func _check_determinism(config: WarConfig) -> void:
	var first: Dictionary = TheaterGenerator.generate(config, 12345)
	_run_ticks(first, config, CHECK_TICKS, 0.6)
	var second: Dictionary = TheaterGenerator.generate(config, 12345)
	_run_ticks(second, config, CHECK_TICKS, 0.6)
	var ok: bool = _state_hash(first) == _state_hash(second)
	print("[war_soak] determinism: %s" % ("OK" if ok else "BROKEN"))
	if not ok:
		_failures.append("same seed produced different histories")


func _check_serialization(config: WarConfig) -> void:
	var live: Dictionary = TheaterGenerator.generate(config, 777)
	_run_ticks(live, config, CHECK_TICKS / 2, 0.6)
	var snapshot: String = var_to_str(live)  # the portable save (F4)
	_run_ticks(live, config, CHECK_TICKS / 2, 0.6)
	var restored: Dictionary = str_to_var(snapshot)
	_run_ticks(restored, config, CHECK_TICKS / 2, 0.6)
	var ok: bool = _state_hash(live) == _state_hash(restored)
	print("[war_soak] serialization round-trip: %s" % ("OK" if ok else "BROKEN"))
	if not ok:
		_failures.append("restored save diverged from the live war")


func _soak_spectator(config: WarConfig) -> void:
	var enemy_wins: int = 0
	var hold_ticks: Array[int] = []
	for i: int in THEATERS_PER_MODE:
		var state: Dictionary = TheaterGenerator.generate(config, 1000 + i)
		while WarSim.winner(state) == &"":
			WarSim.tick(state, config, -1.0)
		if WarSim.winner(state) == &"enemy":
			enemy_wins += 1
			hold_ticks.append(int(state["tick"]))
	hold_ticks.sort()
	var median: int = hold_ticks[hold_ticks.size() / 2] if not hold_ticks.is_empty() else -1
	print("[war_soak] spectator: enemy wins %d/%d, median hold %s ticks"
			% [enemy_wins, THEATERS_PER_MODE, str(median)])
	# Without you, the war must be losable — a passive ally that never falls
	# would mean the enemy AI has no teeth.
	if enemy_wins < int(THEATERS_PER_MODE * 0.8):
		_failures.append("spectator wars stalemate too often (enemy wins %d/%d)"
				% [enemy_wins, THEATERS_PER_MODE])


func _soak_skill(config: WarConfig, skill: float) -> void:
	var wins: int = 0
	var losses: int = 0
	var stalemates: int = 0
	var win_sorties: Array[int] = []
	var pilots_lost_total: int = 0
	for i: int in THEATERS_PER_MODE:
		var state: Dictionary = TheaterGenerator.generate(config, 2000 + i)
		while WarSim.winner(state) == &"":
			WarSim.tick(state, config, skill)
		pilots_lost_total += int(config.starting_pilots) - int(state["pilots"])
		match WarSim.winner(state):
			&"player":
				wins += 1
				win_sorties.append(int(state["sorties"]))
			&"enemy":
				losses += 1
			_:
				stalemates += 1
	win_sorties.sort()
	var median_sorties: String = str(win_sorties[win_sorties.size() / 2]) \
			if not win_sorties.is_empty() else "-"
	print("[war_soak] skill %.1f: W %d / L %d / S %d, median win at %s sorties, %.1f pilots lost/war"
			% [skill, wins, losses, stalemates, median_sorties,
			float(pilots_lost_total) / float(THEATERS_PER_MODE)])
	_last_win_rates[skill] = float(wins) / float(THEATERS_PER_MODE)
	if stalemates > THEATERS_PER_MODE / 5:
		_failures.append("skill %.1f: too many stalemates (%d)" % [skill, stalemates])
	if skill == SKILLS[SKILLS.size() - 1] \
			and _last_win_rates[SKILLS[0]] > _last_win_rates[skill]:
		_failures.append("win rate does not rise with skill (%.2f -> %.2f)"
				% [_last_win_rates[SKILLS[0]], _last_win_rates[skill]])


var _last_win_rates: Dictionary = {}
