extends SceneTree
## Times the sea lookups caravans make. Dev tool, not part of the game.


func _init() -> void:
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all()
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 7
	config.named_target = 300
	var state: WorldState = WorldGenerator.generate(config, catalog)
	var hub: EventHub = EventHub.new()
	var k: SimKernel = SimKernel.new(state, catalog, hub)
	var t0: int = Time.get_ticks_usec()
	var ports: int = 0
	for id: int in k.ctx.settlement_ids():
		if NavalOps.is_port(k.ctx, k.ctx.settlement(id)):
			ports += 1
	print("ports ", ports, " first pass us ", Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	var reached: int = 0
	for id: int in k.ctx.settlement_ids():
		reached += NavalOps.ports_by_sea(k.ctx, k.ctx.settlement(id), NavalOps.SEA_TRADE_REACH).size()
	print("ports_by_sea for all, us ", Time.get_ticks_usec() - t0, " pairs ", reached)
	t0 = Time.get_ticks_usec()
	for id: int in k.ctx.settlement_ids():
		NavalOps.ports_by_sea(k.ctx, k.ctx.settlement(id), NavalOps.SEA_TRADE_REACH)
	print("again, cached, us ", Time.get_ticks_usec() - t0)
	hub.free()
	quit(0)
