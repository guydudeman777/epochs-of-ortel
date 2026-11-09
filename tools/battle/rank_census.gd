extends SceneTree
## Runs a world for some years and counts the soldiers of every rank in its bands and garrisons, to see that captains
## raise their men and towns hire their own people's troops. Run:
## godot --headless --path . --script res://tools/battle/rank_census.gd [-- --years=5 --seed=1]


func _init() -> void:
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all()
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = _arg("seed", "1").to_int()
	var hub: EventHub = EventHub.new()
	var k: SimKernel = SimKernel.new(WorldGenerator.generate(config, catalog), catalog, hub)
	var years: int = _arg("years", "5").to_int()
	for year: int in range(years + 1):
		if year > 0:
			k.advance_days(CalendarData.DAYS_PER_YEAR)
		_count(k.ctx, year)
	hub.free()
	quit(0)


func _count(ctx: SimContext, year: int) -> void:
	var bands: Array[int] = [0, 0, 0, 0, 0, 0]
	var garrisons: Array[int] = [0, 0, 0, 0, 0, 0]
	var peoples: Dictionary[StringName, int] = {}
	var xp: float = 0.0
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		for troop: StringName in band.troops:
			var def: TroopDef = ctx.defs.troops[troop]
			bands[def.tier] += band.troops[troop]
			var had: int = peoples.get(def.culture_id, 0)
			peoples[def.culture_id] = had + band.troops[troop]
		for troop: StringName in band.troop_xp:
			xp += band.troop_xp[troop]
	for id: int in ctx.settlement_ids():
		var s: SettlementData = ctx.settlement(id)
		for troop: StringName in s.garrison:
			garrisons[ctx.defs.troops[troop].tier] += s.garrison[troop]
	print("year %d  bands by tier %s  garrisons by tier %s  unspent xp %d  peoples %s" % [year, bands.slice(1), garrisons.slice(1), roundi(xp), peoples])


func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return fallback
