class_name SocialOrderSystem
extends SimSystem
## Unrest, escapes, expiring terms, debt bondage among commoners, and revolt.

const REVOLT_THRESHOLD: float = 70.0
const REVOLT_CHANCE: float = 0.02
const REBEL_SHARE: float = 0.2
const MIN_GROUP_TO_REVOLT: int = 60
const ESCAPE_RATE: float = 0.0006
const TERM_EXPIRY_RATE: float = 0.015
const MANUMISSION_CHANCE: float = 0.01
const MANUMISSION_SHARE: float = 0.05
const COMMONER_DEBT_RATE: float = 0.01
const DEBT_FOOD_LINE: float = 0.85
const UNREST_AFTER_REVOLT: float = 25.0
const REPRISAL_SHARE: float = 0.1
const REBEL_SEIZED_SHARE: float = 0.4


func tick(ctx: SimContext) -> void:
	var rng: RandomNumberGenerator = ctx.rng(&"social")
	for id: int in ctx.todays_characters():
		var c: CharacterData = ctx.character(id)
		if c != null and c.legal.term_end_day >= 0 and ctx.today() >= c.legal.term_end_day:
			BondageService.free_character(ctx, c, &"term_served")
	for id: int in ctx.settlement_ids():
		if ctx.is_turn(id):
			process_settlement(ctx, ctx.world.settlements[id], rng)


func process_settlement(ctx: SimContext, s: SettlementData, rng: RandomNumberGenerator) -> void:
	var laws: FactionLawsData = LegalService.laws_for(ctx, s.faction_id)
	if laws.bondage_law == SimEnums.BondageLaw.BANNED:
		BondageService.free_all_pops(ctx, s, &"abolished")
	_update_unrest(ctx, s, laws)
	_bonded_flows(ctx, s, laws, rng)
	_check_revolt(ctx, s, rng)


func _garrison_size(s: SettlementData) -> int:
	var sum: int = 0
	for id: StringName in s.garrison:
		sum += s.garrison[id]
	return sum


func _update_unrest(ctx: SimContext, s: SettlementData, laws: FactionLawsData) -> void:
	var guards: int = _garrison_size(s)
	var people: int = PopService.total(s)
	var suppression: float = minf(1.2, guards * 30.0 / float(maxi(people, 1)))
	var hunger: float = (1.0 - s.food_ratio) * 3.0
	var overreach: float = 0.0
	var f: FactionData = ctx.faction(s.faction_id)
	if f != null:
		overreach = maxf(0.0, (f.settlement_ids.size() - 7) * 0.08)
	for group: PopGroupData in s.pop_groups:
		var drift: float = -1.0
		match group.status:
			SimEnums.LegalStatus.ENSLAVED:
				drift = 1.2
			SimEnums.LegalStatus.INDENTURED:
				drift = 0.4
			SimEnums.LegalStatus.SERF:
				drift = 0.1
			SimEnums.LegalStatus.FREE:
				var standing: int = LegalService.race_standing(laws, group.race_id)
				if standing == SimEnums.RaceStanding.ENSLAVABLE:
					drift = 0.6
				elif standing == SimEnums.RaceStanding.SUBJUGATED:
					drift = 0.3
				elif standing == SimEnums.RaceStanding.TOLERATED:
					drift = 0.1
		group.unrest = clampf(group.unrest + drift + hunger + overreach - suppression, 0.0, 100.0)


func _bonded_flows(ctx: SimContext, s: SettlementData, laws: FactionLawsData, rng: RandomNumberGenerator) -> void:
	var groups: Array[PopGroupData] = s.pop_groups.duplicate()
	for group: PopGroupData in groups:
		if group.count <= 0:
			continue
		match group.status:
			SimEnums.LegalStatus.ENSLAVED:
				var escaped: int = PopService.random_round(rng, group.count * ESCAPE_RATE * (1.0 + group.unrest * 0.03))
				if escaped > 0:
					_escape(ctx, s, group, escaped)
				if rng.randf() < MANUMISSION_CHANCE:
					BondageService.free_pop(ctx, s, group.race_id, group.status, roundi(group.count * MANUMISSION_SHARE), &"manumitted")
			SimEnums.LegalStatus.INDENTURED:
				BondageService.free_pop(ctx, s, group.race_id, group.status, PopService.random_round(rng, group.count * TERM_EXPIRY_RATE), &"term_served")
			SimEnums.LegalStatus.FREE:
				if s.food_ratio < DEBT_FOOD_LINE and laws.bondage_law >= SimEnums.BondageLaw.DEBT:
					BondageService.enslave_free_pop(ctx, s, group.race_id, PopService.random_round(rng, group.count * COMMONER_DEBT_RATE), SimEnums.BondageOrigin.DEBT, s.faction_id)


## Runaways make for the nearest realm where they cannot be held. If none exists, they vanish into the wilds.
func _escape(ctx: SimContext, s: SettlementData, group: PopGroupData, count: int) -> void:
	var moved: int = mini(count, group.count)
	group.count -= moved
	ctx.events.pop_escaped.emit(s.id, group.race_id, moved)
	var best: SettlementData = null
	var best_distance: float = INF
	for id: int in ctx.settlement_ids():
		var other: SettlementData = ctx.world.settlements[id]
		if LegalService.laws_for(ctx, other.faction_id).bondage_law != SimEnums.BondageLaw.BANNED:
			continue
		var d: float = ctx.paths.distance(ctx.world.map, s.id, id)
		if d < best_distance:
			best_distance = d
			best = other
	if best != null:
		PopService.get_or_create(best, group.race_id, SimEnums.LegalStatus.FREE).count += moved
	else:
		ctx.bump(&"ledger_vanished", moved)


func _check_revolt(ctx: SimContext, s: SettlementData, rng: RandomNumberGenerator) -> void:
	var groups: Array[PopGroupData] = s.pop_groups.duplicate()
	for group: PopGroupData in groups:
		if group.count >= MIN_GROUP_TO_REVOLT and group.unrest >= REVOLT_THRESHOLD and rng.randf() < REVOLT_CHANCE:
			start_revolt(ctx, s, group)
			return


## A revolt raises a rebel warband, which fights the garrison on the spot.
static func start_revolt(ctx: SimContext, s: SettlementData, group: PopGroupData) -> void:
	var old_faction: FactionData = ctx.faction(s.faction_id)
	if old_faction != null:
		old_faction.last_revolt_day = ctx.today()
	var leader: CharacterData = CharacterFactory.promote_commoner(ctx, s, group, &"rebel")
	if leader == null:
		return
	BondageService.free_character(ctx, leader, &"revolt")
	leader.faction_id = -1
	var rebels: int = maxi(roundi(group.count * REBEL_SHARE), 1)
	group.count = maxi(group.count - rebels, 0)
	ctx.bump(&"ledger_rebels_rose", rebels)
	ctx.events.revolt_started.emit(s.id, group.race_id, rebels)
	var band: WarbandData = WarbandData.new()
	band.id = ctx.new_id()
	band.role = SimEnums.WarbandRole.REBEL
	band.display_name = "%s's rebels" % leader.given_name
	band.leader_id = leader.id
	band.at_settlement_id = s.id
	band.home_settlement_id = s.id
	band.supplies = 10.0
	band.troops[&"rebel_militia"] = rebels
	ctx.world.warbands[band.id] = band
	WarbandOps.add_member(ctx, band, leader)
	ctx.events.warband_formed.emit(band.id)
	var side: BattleSide = BattleSide.from_band(band)
	var winner: BattleSide = BattleResolver.fight(ctx, side, BattleSide.from_garrison_inside(s), s.id)
	var won: bool = winner == side and ctx.world.warbands.has(band.id)
	if won:
		_rebels_take_settlement(ctx, s, group, band, leader)
	else:
		group.unrest = UNREST_AFTER_REVOLT
		var killed: int = roundi(group.count * REPRISAL_SHARE)
		group.count = maxi(group.count - killed, 0)
		ctx.bump(&"ledger_reprisals", killed)
		WarbandOps.destroy(ctx, band)
	ctx.events.revolt_ended.emit(s.id, won)


static func _rebels_take_settlement(ctx: SimContext, s: SettlementData, group: PopGroupData, band: WarbandData, leader: CharacterData) -> void:
	var was_bonded: bool = group.status != SimEnums.LegalStatus.FREE
	var survivors: int = band.troops.get(&"rebel_militia", 0)
	s.garrison.clear()
	s.garrison[TroopOps.levy_for(ctx, s)] = survivors
	var culture: StringName = Actions.culture_near(ctx, group.race_id, s.id)
	var f: FactionData = FactionOps.create_faction(ctx, "Free %s of %s" % [String(group.race_id).capitalize(), s.display_name], culture, null)
	f.is_rebel = true
	if was_bonded:
		f.laws.bondage_law = SimEnums.BondageLaw.BANNED
		f.laws.customary_bondage_law = SimEnums.BondageLaw.BANNED
		f.laws.hereditary_bondage = false
	var old: FactionData = ctx.faction(s.faction_id)
	if old != null:
		f.known_techs = old.known_techs.duplicate()
		FactionOps.start_war(ctx, f, old)
	band.troops.clear()
	WarbandOps.destroy(ctx, band)
	var seized: int = roundi(s.purse * REBEL_SEIZED_SHARE)
	s.purse -= seized
	f.treasury += seized
	FactionOps.set_ruler(ctx, f, leader)
	ctx.events.faction_founded.emit(f.id)
	FactionOps.capture_settlement(ctx, s, f.id)
	for g: PopGroupData in s.pop_groups:
		if g.race_id == group.race_id:
			g.unrest = 0.0
