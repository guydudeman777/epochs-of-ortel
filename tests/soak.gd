class_name Soak
extends RefCounted
## Long headless run. Prints a report and checks the world stays alive and consistent.
## Usage: godot --headless --path . res://tests/test_runner.tscn -- --soak --years=100 --seed=1 --named=5000

const INVARIANT_CHECK_YEARS: int = 5
const REPORT_YEARS: int = 10
const TARGET_AVG_DAY_MS: float = 4.0

const WEAK_LANDS: int = 2
const STRONG_LANDS: int = 5

var _failures: int = 0
## Realms that have been weak at some point, by id.
var _was_weak: Dictionary[int, bool] = {}
var _recovered: Dictionary[int, bool] = {}
var _peak_lands: Dictionary[int, int] = {}


## How far people have changed the land, and whether anywhere they settled is somewhere a town could stand.
func _report_land(ctx: SimContext) -> void:
	var map: MapData = ctx.world.map
	var biggest: float = 0.0
	var on_bad_ground: int = 0
	for id: int in ctx.settlement_ids():
		var reach: float = map.clearings.get(id, 0.0)
		biggest = maxf(biggest, reach)
		if not ctx.terrain().is_walkable(map.positions[id]):
			on_bad_ground += 1
	_expect(on_bad_ground == 0, "every town stands on ground that can be walked")
	var wilds: int = 0
	var stuck: int = 0
	var starving: int = 0
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		if band.supplies <= 0.0:
			starving += 1
		if not band.in_wilds:
			continue
		wilds += 1
		var target: Vector2 = band.destination if band.has_destination else band.position
		if not band.has_destination or ctx.terrain().next_waypoint(band.position, target) == band.position:
			stuck += 1
	print("  Bands in the wilds %d, going nowhere %d, out of supplies %d" % [wilds, stuck, starving])
	print("  Land: woods felled %d times, grown back %d times, widest clearing %d" % [ctx.stat(&"woods_felled"), ctx.stat(&"woods_regrown"), roundi(biggest)])


func run(args: PackedStringArray) -> int:
	var years: int = _int_arg(args, "--years", 100)
	var world_seed: int = _int_arg(args, "--seed", 1)
	var named: int = _int_arg(args, "--named", 5000)
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = world_seed
	config.named_target = named
	var gen_start: int = Time.get_ticks_msec()
	var state: WorldState = WorldGenerator.generate(config, DefRegistry.catalog)
	print("Generated in %d ms. seed=%d years=%d named_target=%d" % [Time.get_ticks_msec() - gen_start, world_seed, years, named])
	var hub: EventHub = EventHub.new()
	var kernel: SimKernel = SimKernel.new(state, DefRegistry.catalog, hub)
	var ctx: SimContext = kernel.ctx
	kernel.profile = true
	var total_usec: int = 0
	var worst_usec: int = 0
	var min_named: int = ctx.world.characters.size()
	var max_named: int = min_named
	var start_commoners: int = _commoners(ctx)
	var min_commoners: int = start_commoners
	var max_commoners: int = start_commoners
	var max_enslaved_share: float = 0.0
	var first_gunpowder_year: int = -1
	print(_header())
	print(_row(ctx))
	for day: int in range(years * CalendarData.DAYS_PER_YEAR):
		var t0: int = Time.get_ticks_usec()
		kernel.advance_day()
		var spent: int = Time.get_ticks_usec() - t0
		total_usec += spent
		worst_usec = maxi(worst_usec, spent)
		if (day + 1) % CalendarData.DAYS_PER_YEAR != 0:
			continue
		var year: int = ctx.world.calendar.year()
		var people: int = ctx.world.characters.size()
		min_named = mini(min_named, people)
		max_named = maxi(max_named, people)
		var commoners: int = _commoners(ctx)
		min_commoners = mini(min_commoners, commoners)
		max_commoners = maxi(max_commoners, commoners)
		max_enslaved_share = maxf(max_enslaved_share, _enslaved_share(ctx))
		if first_gunpowder_year < 0 and _gunpowder_known(ctx):
			first_gunpowder_year = year
		_track_realms(ctx)
		if year % INVARIANT_CHECK_YEARS == 0:
			_check_invariants(ctx, year)
		if year % REPORT_YEARS == 0:
			print(_row(ctx))
	_print_profile(kernel, years)
	_print_recovery()
	_print_town_sizes(ctx)
	_report(ctx, total_usec, worst_usec, years, min_named, max_named, min_commoners, max_commoners, max_enslaved_share, first_gunpowder_year)
	_save_check(kernel)
	_bounds(ctx, named, years, min_named, max_named, start_commoners, min_commoners, max_commoners, max_enslaved_share, first_gunpowder_year, total_usec)
	hub.free()
	print("\nSoak %s" % ("PASSED" if _failures == 0 else "FAILED with %d problems" % _failures))
	return _failures


func _track_realms(ctx: SimContext) -> void:
	for id: int in ctx.faction_ids():
		var lands: int = ctx.world.factions[id].settlement_ids.size()
		var peak: int = _peak_lands.get(id, 0)
		_peak_lands[id] = maxi(peak, lands)
		if lands <= WEAK_LANDS:
			_was_weak[id] = true
		elif lands >= STRONG_LANDS and _was_weak.has(id):
			_recovered[id] = true


func _print_recovery() -> void:
	print("--- Realm recovery ---")
	var outgrew_one: int = 0
	for id: int in _peak_lands:
		if _peak_lands[id] > 1 and _was_weak.has(id):
			outgrew_one += 1
	print("  realms ever seen: %d, ever weak (<=%d towns): %d, grew past 1 town after being weak: %d, weak then reached %d+: %d" % [
		_peak_lands.size(), WEAK_LANDS, _was_weak.size(), outgrew_one, STRONG_LANDS, _recovered.size()])
	var peaks: Array[int] = []
	peaks.assign(_peak_lands.values())
	peaks.sort()
	print("  peak size of every realm: %s" % str(peaks))


func _largest_realm(ctx: SimContext) -> int:
	var best: int = 0
	for id: int in ctx.faction_ids():
		best = maxi(best, ctx.world.factions[id].settlement_ids.size())
	return best


func _print_town_sizes(ctx: SimContext) -> void:
	var sizes: Array[int] = []
	for id: int in ctx.settlement_ids():
		sizes.append(PopService.total(ctx.world.settlements[id]))
	sizes.sort()
	var broke: int = 0
	for id: int in ctx.faction_ids():
		if ctx.world.factions[id].treasury == 0:
			broke += 1
	print("--- Towns ---")
	print("  realm splits: %d, largest realm now: %d of %d towns" % [ctx.stat(&"realm_splits"), _largest_realm(ctx), sizes.size()])
	_report_land(ctx)
	print("  %d towns (%d founded), people smallest %d, median %d, largest %d. Realms with empty treasuries: %d of %d. Migrants: %d" % [sizes.size(), ctx.stat(&"settlements_founded"),
		sizes[0], sizes[sizes.size() / 2], sizes[sizes.size() - 1], broke, ctx.faction_ids().size(), ctx.stat(&"migrants")])
	var walls: Array[int] = [0, 0, 0, 0, 0]
	for id: int in ctx.settlement_ids():
		walls[mini(Actions.wall_steps(ctx.world.settlements[id].fortification), 4)] += 1
	print("  Walls by step, none to strongest: %s" % str(walls))


func _print_profile(kernel: SimKernel, years: int) -> void:
	print("\n--- Per system, ms per day ---")
	var days: float = years * CalendarData.DAYS_PER_YEAR
	var names: Array[String] = []
	names.assign(kernel.system_usec.keys())
	names.sort()
	for system_name: String in names:
		print("  %-20s %.2f" % [system_name, kernel.system_usec[system_name] / days / 1000.0])


func _food(ctx: SimContext) -> float:
	var total: float = 0.0
	for id: int in ctx.world.settlements:
		total += ctx.world.settlements[id].food_ratio
	return total / float(maxi(ctx.world.settlements.size(), 1))


func _int_arg(args: PackedStringArray, key: String, fallback: int) -> int:
	for arg: String in args:
		if arg.begins_with(key + "="):
			return arg.get_slice("=", 1).to_int()
	return fallback


func _commoners(ctx: SimContext) -> int:
	var sum: int = 0
	for id: int in ctx.world.settlements:
		sum += PopService.total(ctx.world.settlements[id])
	return sum


func _enslaved_share(ctx: SimContext) -> float:
	var enslaved: int = 0
	for id: int in ctx.world.settlements:
		enslaved += PopService.total_with_status(ctx.world.settlements[id], SimEnums.LegalStatus.ENSLAVED)
	return enslaved / float(maxi(_commoners(ctx), 1))


func _gunpowder_known(ctx: SimContext) -> bool:
	for id: int in ctx.faction_ids():
		for tech: StringName in ctx.world.factions[id].known_techs:
			if ctx.defs.techs[tech].is_gunpowder:
				return true
	return false


func _max_techs(ctx: SimContext) -> int:
	var best: int = 0
	for id: int in ctx.faction_ids():
		best = maxi(best, ctx.world.factions[id].known_techs.size())
	return best


func _race_totals(ctx: SimContext) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for race: StringName in ctx.defs.race_ids:
		out[race] = 0
	for id: int in ctx.world.settlements:
		for group: PopGroupData in ctx.world.settlements[id].pop_groups:
			out[group.race_id] += group.count
	return out


func _header() -> String:
	return "%5s %6s %7s %7s %5s %5s %5s %6s %5s %5s %5s %5s" % ["year", "named", "commons", "slaves%", "realm", "bands", "busi", "battle", "revlt", "taken", "techs", "food"]


func _row(ctx: SimContext) -> String:
	return "%5d %6d %7d %6.1f%% %5d %5d %5d %6d %5d %5d %5d %5.2f" % [ctx.world.calendar.year(), ctx.world.characters.size(), _commoners(ctx),
		_enslaved_share(ctx) * 100.0, ctx.faction_ids().size(), ctx.world.warbands.size(), ctx.world.businesses.size(), ctx.stat(&"battles"),
		ctx.stat(&"revolts"), ctx.stat(&"settlements_captured"), _max_techs(ctx), _food(ctx)]


func _check_invariants(ctx: SimContext, year: int) -> void:
	var problems: PackedStringArray = Invariants.check(ctx)
	if not problems.is_empty():
		_failures += 1
		print("FAIL  invariants at year %d: %d problems. %s" % [year, problems.size(), "; ".join(problems.slice(0, 8))])


func _report(ctx: SimContext, total_usec: int, worst_usec: int, years: int, min_named: int, max_named: int, min_commoners: int,
		max_commoners: int, max_enslaved_share: float, first_gunpowder_year: int) -> void:
	var days: int = years * CalendarData.DAYS_PER_YEAR
	print("\n--- Performance ---")
	print("avg day %.2f ms, worst day %.2f ms, %.1f s per century" % [total_usec / float(days) / 1000.0, worst_usec / 1000.0, total_usec / 1000000.0 / years * 100.0])
	print("--- Population ---")
	print("named %d..%d (now %d), commoners %d..%d (now %d), peak enslaved share %.1f%%" % [min_named, max_named, ctx.world.characters.size(), min_commoners, max_commoners, _commoners(ctx), max_enslaved_share * 100.0])
	print("by race: %s" % str(_race_totals(ctx)))
	print("archived dead: %d, dynasties with living members: %d" % [ctx.world.archived_characters.size(), _living_dynasties(ctx)])
	print("--- Totals ---")
	var keys: Array[StringName] = []
	keys.assign(ctx.world.stats.keys())
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var parts: PackedStringArray = PackedStringArray()
	for key: StringName in keys:
		parts.append("%s=%d" % [key, ctx.world.stats[key]])
	print(", ".join(parts))
	print("--- Commoner ledger ---")
	for key: StringName in [&"ledger_born", &"ledger_died", &"ledger_recruited", &"ledger_troops_fallen", &"ledger_troops_starved", &"ledger_raided_away", &"captives_sold",
			&"ledger_rebels_rose", &"ledger_reprisals", &"ledger_vanished", &"promotions"]:
		print("  %-24s %d" % [key, ctx.stat(key)])
	print("first gunpowder tech: year %d" % first_gunpowder_year)
	print("--- Realms now ---")
	for id: int in ctx.faction_ids():
		var f: FactionData = ctx.world.factions[id]
		print("  %-28s lands=%-2d treasury=%-7d law=%-10s techs=%-2d wars=%d rebel=%s" % [f.display_name, f.settlement_ids.size(), f.treasury,
			SimEnums.BondageLaw.keys()[f.laws.bondage_law], f.known_techs.size(), f.at_war_with.size(), f.is_rebel])
	var player: CharacterData = ctx.character(ctx.world.player_character_id)
	print("--- Player pointer ---")
	print("  handoffs=%d now=%s" % [ctx.stat(&"player_handoffs"), player.given_name if player != null else "line ended"])
	print("--- Chronicle sample ---")
	var entries: Array[ChronicleEntry] = ctx.world.chronicle
	var step: int = maxi(1, floori(entries.size() / 12.0))
	for i: int in range(0, entries.size(), step):
		print("  y%-3d %s" % [floori(entries[i].day / float(CalendarData.DAYS_PER_YEAR)), entries[i].text])


func _living_dynasties(ctx: SimContext) -> int:
	var count: int = 0
	for id: int in ctx.world.dynasties:
		if not ctx.world.dynasties[id].living_member_ids.is_empty():
			count += 1
	return count


func _save_check(kernel: SimKernel) -> void:
	var path: String = "user://soak_save_%d.res" % kernel.ctx.world.world_seed
	var t0: int = Time.get_ticks_msec()
	var err: Error = kernel.save_to(path)
	var save_ms: int = Time.get_ticks_msec() - t0
	if err != OK:
		_expect(false, "save failed: %s" % err)
		return
	var size_mb: float = FileAccess.get_file_as_bytes(path).size() / 1048576.0
	t0 = Time.get_ticks_msec()
	var loaded: WorldState = SaveGame.load_from(path)
	print("--- Save ---\n  %.1f MB, save %d ms, load %d ms" % [size_mb, save_ms, Time.get_ticks_msec() - t0])
	_expect(loaded != null, "save loads back")
	if loaded != null:
		_expect(StateHash.compute(loaded) == StateHash.compute(kernel.ctx.world), "loaded world matches")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL  " + message)


func _bounds(ctx: SimContext, named: int, years: int, min_named: int, max_named: int, start_commoners: int, min_commoners: int, max_commoners: int,
		max_enslaved_share: float, first_gunpowder_year: int, total_usec: int) -> void:
	print("\n--- Checks ---")
	_check_invariants(ctx, ctx.world.calendar.year())
	_expect(min_named >= named * 0.4, "named population stayed above 40%% of target (%d)" % min_named)
	_expect(max_named <= named * 1.5, "named population stayed under 150%% of target (%d)" % max_named)
	_expect(min_commoners >= start_commoners * 0.4, "commoners stayed above 40%% of start (%d of %d)" % [min_commoners, start_commoners])
	_expect(max_commoners <= start_commoners * 3, "commoners stayed under 3x start (%d of %d)" % [max_commoners, start_commoners])
	_expect(max_enslaved_share < 0.5, "enslaved share stayed under 50%% (%.1f%%)" % (max_enslaved_share * 100.0))
	for stat_key: StringName in [&"births", &"deaths", &"marriages", &"wars", &"battles", &"settlements_captured", &"raids", &"pops_enslaved",
			&"characters_enslaved", &"revolts", &"pops_freed", &"pops_escaped", &"captives_sold", &"caravan_trades", &"businesses_founded", &"techs_discovered"]:
		_expect(ctx.stat(stat_key) > 0, "%s happened" % stat_key)
	_expect(_living_dynasties(ctx) > 0, "at least one dynasty survives")
	# Slavery does not have to survive. What must work is that rulers can move the law either way.
	print("bondage law: hardened %d times, softened %d times, enslaved share now %.1f%%" % [ctx.stat(&"law_bondage_tightened"), ctx.stat(&"law_bondage_loosened"), _enslaved_share(ctx) * 100.0])
	if years >= 100:
		_expect(ctx.stat(&"law_bondage_loosened") > 0, "some ruler softened bondage law")
		_expect(not _recovered.is_empty(), "a realm that was weak grew strong again (%d+ towns)" % STRONG_LANDS)
		_expect(ctx.stat(&"revolts_won") > 0, "a revolt succeeded")
		_expect(ctx.stat(&"factions_founded") > 0, "a new realm arose")
		_expect(ctx.stat(&"woods_felled") > 0, "woods were felled")
	if years >= 300:
		_expect(ctx.stat(&"law_bondage_tightened") > 0, "some ruler hardened bondage law")
	var taken: int = ctx.stat(&"captives_taken")
	var held: int = 0
	for id: int in ctx.world.warbands:
		for race: StringName in ctx.world.warbands[id].captives:
			held += ctx.world.warbands[id].captives[race]
	print("captives taken %d, sold %d, still held %d" % [taken, ctx.stat(&"captives_sold"), held])
	_expect(ctx.faction_ids().size() >= 2, "more than one realm remains (%d)" % ctx.faction_ids().size())
	for race: StringName in ctx.defs.race_ids:
		_expect(_race_totals(ctx)[race] > 0, "race %s survives" % race)
	if years >= 300:
		_expect(first_gunpowder_year >= 0, "gunpowder reached within %d years" % years)
	var avg_ms: float = total_usec / float(years * CalendarData.DAYS_PER_YEAR) / 1000.0
	print("avg day %.2f ms against a %.1f ms target" % [avg_ms, TARGET_AVG_DAY_MS])
