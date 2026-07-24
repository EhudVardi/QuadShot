class_name TunableConfig
extends Resource

## Base for live-tunable config resources (the FlightConfig pattern, now
## shared): the overlay edits fields on the shared instance, and persistence
## copies values ONTO that instance so every node holding a reference keeps
## seeing live data. Subclasses override save_path()/defaults_path().


## Where the last successful load_from_user() actually read from. Usually
## save_path(), but FlightConfig can fall back to a legacy path, and a boot log
## that names the wrong file is worse than no boot log.
var loaded_from: String = ""

## Save paths already loaded once this session (v1.41). Every scene's _ready
## calls load_from_user, and before this guard each scene change stomped live
## tuning with stale disk state — the shared instances persist in the resource
## cache, so only the FIRST ask per path actually reads the file. The
## overlay's LOAD button passes force to genuinely re-read.
static var _session_loaded: Dictionary = {}


func save_path() -> String:
	return ""


func defaults_path() -> String:
	return ""


## Fields naming WHICH instance this is (EnemyConfig.type_id,
## FlightConfig/FrameConfig.frame_id) rather than how it behaves. Subclasses
## with many instances list them here and copy_from skips them.
##
## Values travel between instances constantly — that is what the overlay's
## preset bars are for — and identity must not travel with them: a FLIGHT preset
## saved on the Kestrel and loaded onto the Atlas would otherwise rename the
## Atlas, which then saves its tuning over the Kestrel's file. Same exposure the
## BESTIARY preset bars have always had with type_id.
func identity_fields() -> PackedStringArray:
	return PackedStringArray()


func copy_from(source: TunableConfig) -> void:
	var identity: PackedStringArray = identity_fields()
	for prop: Dictionary in get_property_list():
		var usage: int = prop["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (usage & PROPERTY_USAGE_STORAGE) \
				and not identity.has(prop["name"]):
			set(prop["name"], source.get(prop["name"]))


func save_to_user() -> Error:
	return ResourceSaver.save(self, save_path())


func session_loaded() -> bool:
	return _session_loaded.has(save_path())


func _mark_session_loaded() -> void:
	_session_loaded[save_path()] = true


func load_from_user(force: bool = false) -> bool:
	if not force and session_loaded():
		return false
	if not FileAccess.file_exists(save_path()):
		return false
	var loaded: TunableConfig = ResourceLoader.load(
			save_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TunableConfig
	if loaded == null:
		return false
	copy_from(loaded)
	loaded_from = save_path()
	_mark_session_loaded()
	return true


func reset_to_defaults() -> void:
	# CACHE_MODE_IGNORE: the cached default resource may be this very
	# instance, already mutated by live tuning - a fresh read is required.
	var defaults: TunableConfig = ResourceLoader.load(
			defaults_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TunableConfig
	if defaults != null:
		copy_from(defaults)
