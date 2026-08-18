extends SceneTree

## READ A HUMAN'S DRILL RUN AGAINST THE PREDICTION IT WAS FLOWN AGAINST.
##
##   <godot> --headless -s scripts/tests/drill_report.gd --path .
##   <godot> --headless -s scripts/tests/drill_report.gd --path . -- --drill rotor_out
##   <godot> --headless -s scripts/tests/drill_report.gd --path . -- --file <path>
##   <godot> --headless -s scripts/tests/drill_report.gd --path . -- --list
##
## With no arguments it reads the NEWEST artifact of every drill that has one.
##
## THIS IS THE ONE INSTRUMENT IN THE PROJECT THAT DELIBERATELY READS `user://`,
## and the exception is worth stating rather than hiding. The standing rule
## exists for two reasons: a bench must never measure one machine's tuning, and
## the harness must never destroy the human's data. This tool does neither — it
## reads exactly one file, the one the drill itself wrote, writes nothing at all,
## and turns config overrides off anyway. It is also NOT ON THE BOARD: the pure
## modules it drives are checked by `drill_check`, which touches nothing.
##
## THE GIT CALL IS THE POINT, not plumbing. `git log -1 --format=%ct` on the
## prediction file gives the second it was committed, which is a date the agent
## does not author, and `DrillCompare` refuses the whole comparison if that
## second is later than the flight's. Without it the instrument would rest on an
## agent's word about when it wrote something down.

const ARTIFACT_DIR: String = "user://blackbox/drills"


func _initialize() -> void:
	TunableConfig.user_overrides_enabled = false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var files: PackedStringArray = _artifacts()
	if args.has("--list"):
		for path: String in files:
			print("[report] %s" % path)
		if files.is_empty():
			print("[report] no drill runs in %s yet" % ARTIFACT_DIR)
		quit(0)
		return
	var chosen: PackedStringArray = PackedStringArray()
	var at: int = args.find("--file")
	if at >= 0 and at + 1 < args.size():
		chosen.append(args[at + 1])
	else:
		at = args.find("--drill")
		var wanted: String = args[at + 1] if at >= 0 and at + 1 < args.size() else ""
		for id: String in DrillBook.ids():
			if not wanted.is_empty() and id != wanted:
				continue
			var newest: String = _newest(files, id)
			if not newest.is_empty():
				chosen.append(newest)
	if chosen.is_empty():
		print("[report] no drill runs found in %s" % ARTIFACT_DIR)
		print("[report] fly one first: <godot> --path . scenes/drill.tscn -- --drill %s"
				% DrillBook.ids()[0])
		quit(0)
		return
	for path: String in chosen:
		_report(path)
	quit(0)


func _report(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		print("[report] cannot read %s" % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		print("[report] %s is not a drill artifact" % path)
		return
	var artifact: Dictionary = parsed as Dictionary
	var id: String = String(artifact.get("drill", ""))
	if not DrillBook.has(id):
		print("[report] %s names an unknown drill '%s'" % [path, id])
		return
	print("")
	print("file       %s" % path)
	for line: String in DrillCompare.report_lines(id,
			DrillPredictions.load_prediction(id), artifact, _committed_at(id)):
		print(line)


## Unix seconds of the commit that last touched this drill's prediction file, or
## 0 if git could not be asked. Zero is not treated as "fine": `DrillCompare`
## turns an unknown date into a REFUSAL, because a prediction that cannot be
## shown to predate the flight has not been shown to be a prediction.
func _committed_at(drill_id: String) -> int:
	var output: Array = []
	var relative: String = DrillBook.prediction_path(drill_id).replace("res://", "")
	var code: int = OS.execute("git", ["-C",
			ProjectSettings.globalize_path("res://").rstrip("/"),
			"log", "-1", "--format=%ct", "--", relative], output, true)
	if code != 0 or output.is_empty():
		push_warning("[report] git could not date %s" % relative)
		return 0
	var stamp: String = String(output[0]).strip_edges()
	return int(stamp) if stamp.is_valid_int() else 0


func _artifacts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(ARTIFACT_DIR)
	if dir == null:
		return out
	for name: String in dir.get_files():
		if name.ends_with(".json"):
			out.append("%s/%s" % [ARTIFACT_DIR, name])
	# The runner stamps YYYYMMDD_HHMMSS into the name, so sorting by name sorts
	# by time — the same reason the blackbox stopped naming files by tick count.
	out.sort()
	return out


## The newest artifact THIS drill wrote. It asks `DrillBook` which drill a file
## name belongs to rather than testing the name against a prefix: `course_` is
## also the start of `course_tight_...` and `course_wide_...`, so the prefix
## version reported the wide course twice and the medium course never.
func _newest(files: PackedStringArray, drill_id: String) -> String:
	var newest: String = ""
	for path: String in files:
		if DrillBook.artifact_drill_id(path.get_file()) == drill_id:
			newest = path
	return newest
