extends SceneTree
## Prints what a battle site's field holds at its middle. For finding out why a field came out as it did.
## godot --headless --path . --script res://tools/battle/debug_site.gd -- --kind=ford --biome=snow


func _init() -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 7
	config.named_target = 300
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all("res://content/defs")
	var hub: EventHub = EventHub.new()
	var kernel: SimKernel = SimKernel.new(WorldGenerator.generate(config, catalog), catalog, hub)
	var sites: BattleSitesDef = BattleSitesDef.of_land(&"ortel")
	var kind: StringName = StringName(_arg("kind", "ford"))
	var biome: int = LandDef.BIOME_NAMES.find(StringName(_arg("biome", "temperate")))
	var site: BattleSiteDef = sites.first_of(kind, biome)
	var ground: BattleGround = BattleGround.of_site(kernel.ctx, site)
	print("site %d %s at %s, land %.2f (water %.2f)" % [site.id, site.kind, site.position, catalog.land.height_at(site.position), OverworldTerrain.WATER_LEVEL])
	for z: int in range(-30, 31, 5):
		var row: String = ""
		for x: int in range(-30, 31, 5):
			row += "%5.2f " % ground.depth_at(Vector2(x, z))
		print(row)
	hub.free()
	quit(0)


func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return fallback
