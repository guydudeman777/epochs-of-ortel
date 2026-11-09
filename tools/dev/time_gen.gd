extends SceneTree
## Times world making and a stretch of days, by system. Dev tool, not part of the game.


func _init() -> void:
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all()
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 7
	config.named_target = 5000 if OS.get_cmdline_user_args().has("--big") else 300
	var t0: int = Time.get_ticks_msec()
	var state: WorldState = WorldGenerator.generate(config, catalog)
	print("generate ms: ", Time.get_ticks_msec() - t0, " settlements ", state.settlements.size(), " bands ", state.warbands.size())
	var hub: EventHub = EventHub.new()
	var k: SimKernel = SimKernel.new(state, catalog, hub)
	k.advance_days(5)
	var wilds: int = 0
	var roads: int = 0
	for id: int in k.ctx.warband_ids():
		var band: WarbandData = k.ctx.warband(id)
		if band.in_wilds:
			wilds += 1
		elif band.at_settlement_id < 0:
			roads += 1
	print("bands in the wilds ", wilds, " on roads ", roads)
	var terrain: OverworldTerrain = k.ctx.terrain()
	var t1: int = Time.get_ticks_usec()
	var clear: int = 0
	for i: int in range(200):
		var a: Vector2 = Vector2(400.0 + i * 15.0, 900.0)
		if terrain.line_is_clear(a, a + Vector2(600.0, 300.0)):
			clear += 1
	print("200 long line checks us: ", Time.get_ticks_usec() - t1)
	t1 = Time.get_ticks_usec()
	for i: int in range(50):
		terrain.next_waypoint(Vector2(1300.0, 1000.0), Vector2(900.0 + i * 40.0, 2400.0))
	print("50 far waypoints us: ", Time.get_ticks_usec() - t1)
	k.profile = true
	var t3: int = Time.get_ticks_msec()
	var days: int = 360 if OS.get_cmdline_user_args().has("--big") else 60
	k.advance_days(days)
	print(days, " days ms: ", Time.get_ticks_msec() - t3, " bands ", k.ctx.warband_ids().size())
	for key: Variant in k.system_usec.keys():
		print("  ", key, " ", int(k.system_usec[key]) / 1000, " ms")
	var system: WarbandSystem = WarbandSystem.new()
	var moving: int = 0
	var contacts: int = 0
	var by_kind: Dictionary[String, int] = {}
	for watch: int in range(64):
		var t5: int = Time.get_ticks_usec()
		for id: int in k.ctx.warband_ids():
			var band: WarbandData = k.ctx.warband(id)
			if band == null:
				continue
			var kind: String = "sea" if band.at_sea else ("wilds" if band.in_wilds or band.chase_band_id >= 0 else ("town" if band.at_settlement_id >= 0 else "road"))
			var t6: int = Time.get_ticks_usec()
			system._move(k.ctx, band)
			by_kind[kind] = by_kind.get(kind, 0) + Time.get_ticks_usec() - t6
		var t7: int = Time.get_ticks_usec()
		moving += t7 - t5
		system._resolve_contacts(k.ctx)
		contacts += Time.get_ticks_usec() - t7
	print("64 watches: moving us ", moving, " contacts us ", contacts, " by kind ", by_kind)
	hub.free()
	quit(0)
