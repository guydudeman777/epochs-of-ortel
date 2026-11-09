class_name SaveGame
extends RefCounted
## Saving and loading the one root resource.


static func save_to(state: WorldState, path: String) -> Error:
	return ResourceSaver.save(state, path, ResourceSaver.FLAG_COMPRESS)


## Saves older than this were made on a map that is gone, and cannot be played on.
const OLDEST_LOADABLE: int = 2


static func load_from(path: String) -> WorldState:
	var loaded: WorldState = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WorldState
	if loaded == null:
		return null
	if loaded.save_version < OLDEST_LOADABLE:
		push_warning("%s was made on the old map of Ortel and cannot be loaded. Start a new game." % path)
		return null
	_migrate(loaded)
	return loaded


static func _migrate(state: WorldState) -> void:
	# Version upgrades go here, one step per version.
	state.save_version = WorldState.CURRENT_SAVE_VERSION
