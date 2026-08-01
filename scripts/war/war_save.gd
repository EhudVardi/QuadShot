class_name WarSave
extends RefCounted

## F4's portable save, finally written to disk (Iteration 12, W7).
##
## The war state has been *provably* serializable since v1.7 — every evolving
## float goes through `WarSim.quantize` precisely so `var_to_str` round-trips it
## bit-exactly, and `war_soak` asserts it every run. Nothing had ever written
## the file. This is that file.
##
## IT IS `var_to_str`, NOT JSON, AND THAT IS THE WHOLE DESIGN DECISION HERE.
## `user://profile.json` is the standing precedent for saving in this project,
## and it is the wrong precedent for this one:
##
##   - **JSON has no StringName.** Every `&"enemy"`, `&"factory"` and `&"city"`
##     in the state comes back as a plain String, so `node["owner"] == &"enemy"`
##     is false for a loaded war and every side in the theater silently becomes
##     neutral. That exact class of drift — StringName vs String — is what
##     `war_soak`'s round-trip guard was originally written to catch.
##   - **JSON has no int.** Godot's JSON parses every number as a float, so
##     `tick`, `pilots`, node ids and `rng_state` all come back as doubles.
##     `rng_state` is a 64-bit integer; a double cannot hold one, so a JSON
##     round-trip silently forks the war's random stream and F4's "the save
##     replays the same war" promise dies quietly.
##   - `var_to_str` has neither problem, and the quantization that already
##     exists makes its float output exact rather than merely close.
##
## So the file is text, human-readable, diffable and shareable — everything F4
## asked for — and it is byte-identical to what produced it.

## The file. One war, one file, portable by copying it (F4).
const PATH: String = "user://war.save"
## Bumped when the state's SHAPE changes, so an old save is rejected loudly
## rather than half-read into a war that behaves strangely.
const SAVE_VERSION: int = 1

## True when `load_war` found a file it could not use, as opposed to no file at
## all. Both return `{}`, and collapsing the two was a campaign-shredder: a
## version bump - the exact event `SAVE_VERSION` exists for - made `load_or_new`
## generate a fresh theater, and the first finished sortie wrote it straight over
## the war it had failed to read. The warning went to `push_warning`, which
## nobody sees.
static var last_load_rejected: bool = false


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


## Write the war. Returns false and warns rather than throwing, because losing
## a campaign to a disk error should not also crash the game you were playing.
static func save(state: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[war] could not write %s (error %d)"
				% [PATH, FileAccess.get_open_error()])
		return false
	file.store_line("# QuadShot war save v%d" % SAVE_VERSION)
	file.store_line(str(SAVE_VERSION))
	file.store_string(var_to_str(state))
	file.close()
	return true


## Load the war, or `{}` if there is no readable one. A rejected save is never
## silently replaced — the caller decides whether to start a new war, because
## overwriting somebody's campaign is not a thing to do by default.
static func load_war() -> Dictionary:
	last_load_rejected = false
	if not exists():
		return {}
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("[war] could not read %s" % PATH)
		last_load_rejected = true
		return {}
	# Read the WHOLE file and split it, rather than get_line()-ing past the
	# header and then calling get_as_text(). `get_as_text()` reads from the
	# START of the file regardless of the cursor, so the positioned version fed
	# the "# QuadShot war save" comment to `str_to_var`, which saw a leading '#'
	# and tried to parse the campaign as a Color. Caught by war_loop_check on
	# its first run: every save in the world would have been unreadable.
	var text: String = file.get_as_text()
	file.close()
	# At most three pieces: comment, version, and the body (which contains
	# newlines of its own and must not be split further).
	var parts: PackedStringArray = text.split("\n", true, 2)
	if parts.size() < 3:
		push_warning("[war] %s is truncated" % PATH)
		last_load_rejected = true
		return {}
	var version: int = int(parts[1].strip_edges())
	var body: String = parts[2]
	if version != SAVE_VERSION:
		push_warning("[war] save is version %d, this build reads %d - ignoring"
				% [version, SAVE_VERSION])
		last_load_rejected = true
		return {}
	var parsed: Variant = str_to_var(body)
	if parsed == null or not parsed is Dictionary:
		push_warning("[war] %s did not parse as a war state" % PATH)
		last_load_rejected = true
		return {}
	var state: Dictionary = parsed
	# Cheap shape check. A file that parses but is not a war is worse than one
	# that does not parse, because it fails later and further away.
	for key: String in ["tick", "nodes", "seed", "rng_state", "winner"]:
		if not state.has(key):
			push_warning("[war] %s is missing '%s' - ignoring" % [PATH, key])
			last_load_rejected = true
			return {}
	return state


## The normal entry point: resume the campaign, or start one on `seed_value`.
##
## An UNREADABLE save is never overwritten - it is moved aside first, so a bad
## version, a truncated write or a half-synced file costs the player a rename
## rather than their war. Starting fresh on top of a file we could not parse is
## the one outcome that has to be impossible here, because the next sortie saves.
static func load_or_new(config: WarConfig, seed_value: int) -> Dictionary:
	var state: Dictionary = load_war()
	if not state.is_empty():
		return state
	if last_load_rejected:
		var kept: String = preserve_rejected()
		if kept == "":
			# Could not even move it aside, so refuse to trample it. An empty
			# state is a caller problem; a deleted campaign is not recoverable.
			push_error("[war] %s is unreadable and could not be moved aside - refusing to overwrite it"
					% PATH)
			return {}
		print("[war] %s was unreadable and has been kept as %s; starting a new war"
				% [PATH, kept])
	return TheaterGenerator.generate(config, seed_value)


## Move an unreadable save out of the way, returning its new name (or "" on
## failure). Timestamped so a second bad launch cannot clobber the first rescue.
static func preserve_rejected() -> String:
	if not exists():
		return ""
	var raw: String = Time.get_datetime_string_from_system(false, false)
	var stamp: String = raw.replace(":", "").replace("-", "").replace("T", "-")
	var target: String = "%s.rejected-%s" % [PATH, stamp]
	var error: int = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(PATH),
			ProjectSettings.globalize_path(target))
	return target if error == OK else ""


static func clear() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
