class_name TunableConfig
extends Resource

## Base for live-tunable config resources (the FlightConfig pattern, now
## shared): the overlay edits fields on the shared instance, and persistence
## copies values ONTO that instance so every node holding a reference keeps
## seeing live data. Subclasses override save_path()/defaults_path().


func save_path() -> String:
	return ""


func defaults_path() -> String:
	return ""


func copy_from(source: TunableConfig) -> void:
	for prop: Dictionary in get_property_list():
		var usage: int = prop["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (usage & PROPERTY_USAGE_STORAGE):
			set(prop["name"], source.get(prop["name"]))


func save_to_user() -> Error:
	return ResourceSaver.save(self, save_path())


func load_from_user() -> bool:
	if not FileAccess.file_exists(save_path()):
		return false
	var loaded: TunableConfig = ResourceLoader.load(
			save_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TunableConfig
	if loaded == null:
		return false
	copy_from(loaded)
	return true


func reset_to_defaults() -> void:
	# CACHE_MODE_IGNORE: the cached default resource may be this very
	# instance, already mutated by live tuning - a fresh read is required.
	var defaults: TunableConfig = ResourceLoader.load(
			defaults_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TunableConfig
	if defaults != null:
		copy_from(defaults)
