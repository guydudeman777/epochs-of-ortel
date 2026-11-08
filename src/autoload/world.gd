extends Node
## Owns the current WorldState and handles new game, save and load.

signal world_changed(state: WorldState)

var state: WorldState = null


func new_game(config: WorldGenConfig) -> void:
	state = WorldGenerator.generate(config, DefRegistry.catalog)
	world_changed.emit(state)


func save_game(path: String) -> Error:
	if state == null:
		return ERR_UNCONFIGURED
	Simulation.kernel.ctx.sync_rng_to_world()
	return SaveGame.save_to(state, path)


func load_game(path: String) -> Error:
	var loaded: WorldState = SaveGame.load_from(path)
	if loaded == null:
		return ERR_FILE_CANT_READ
	state = loaded
	world_changed.emit(state)
	return OK
