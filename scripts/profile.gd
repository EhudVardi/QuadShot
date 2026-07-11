class_name PlayerProfile
extends RefCounted

## Meta progression across runs (roadmap M4): lifetime stats and bests,
## persisted as plain JSON so it survives config resets and stays
## hand-inspectable.

const SAVE_PATH: String = "user://profile.json"

var runs: int = 0
var kills_total: int = 0
var best_score: int = 0
var best_sorties: int = 0


func record_run(sorties_cleared: int, kills: int, score: int) -> void:
	runs += 1
	kills_total += kills
	best_score = maxi(best_score, score)
	best_sorties = maxi(best_sorties, sorties_cleared)


func save() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[profile] cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"runs": runs,
		"kills_total": kills_total,
		"best_score": best_score,
		"best_sorties": best_sorties,
	}, "\t"))


static func load_or_new() -> PlayerProfile:
	var profile := PlayerProfile.new()
	if not FileAccess.file_exists(SAVE_PATH):
		return profile
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		profile.runs = int(data.get("runs", 0))
		profile.kills_total = int(data.get("kills_total", 0))
		profile.best_score = int(data.get("best_score", 0))
		profile.best_sorties = int(data.get("best_sorties", 0))
	return profile
