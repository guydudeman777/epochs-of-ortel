class_name BattleResolver
extends RefCounted
## Abstract auto-resolve. Phase 2 tactical battles can replace this behind the same call.
## Each kind of troop counts its TroopDef.strength, which rises with its rank, and a band's soldiers come out of every
## battle they live through with experience to rise by (TroopOps.gain_xp).

const CAPTIVE_SHARE: float = 0.35
## Chance a named fighter is caught by blows, and how many fall on them.
const NAMED_WOUNDED_LOSER: float = 0.6
const NAMED_BLOWS_LOSER: int = 3
const NAMED_WOUNDED_WINNER: float = 0.15
const NAMED_BLOWS_WINNER: int = 1
const NAMED_CAPTURE_LOSER: float = 0.3
const LOOT_SHARE: float = 0.5
const MILITIA_STRENGTH_PER_HEAD: float = 0.04


static func strength(ctx: SimContext, side: BattleSide) -> float:
	var sum: float = 0.0
	for id: StringName in side.troops:
		sum += ctx.defs.troops[id].strength * side.troops[id]
	var leader: CharacterData = ctx.character(side.leader_id)
	if leader != null:
		var leadership: int = leader.skills.levels.get(&"leadership", 0)
		sum += leader.attributes.might * LimbService.fighting_capacity(ctx, leader)
		sum *= 1.0 + leadership * 0.005
	if side.holds_walls:
		sum += PopService.total_with_status(side.garrison_of, SimEnums.LegalStatus.FREE) * MILITIA_STRENGTH_PER_HEAD
	return sum * side.defense_mult


## Returns the winning side. Applies casualties, captives, named fates and loot.
static func fight(ctx: SimContext, a: BattleSide, b: BattleSide, site_id: int) -> BattleSide:
	var rng: RandomNumberGenerator = ctx.rng(&"battle")
	var strength_a: float = strength(ctx, a)
	var strength_b: float = strength(ctx, b)
	var power_a: float = strength_a * rng.randf_range(0.8, 1.2)
	var power_b: float = strength_b * rng.randf_range(0.8, 1.2)
	var winner: BattleSide = a if power_a >= power_b else b
	var loser: BattleSide = b if power_a >= power_b else a
	var win_power: float = maxf(power_a, power_b)
	var lose_power: float = minf(power_a, power_b)
	var margin: float = win_power / maxf(win_power + lose_power, 0.001)
	_apply_casualties(winner, 0.5 * (1.0 - margin), rng)
	var fallen: int = _apply_casualties(loser, 0.5 + 0.4 * margin, rng)
	# Those left standing learn from it, the winners more.
	if winner.band != null:
		TroopOps.gain_xp(ctx, winner.band, TroopOps.battle_xp(strength_b if winner == a else strength_a, true))
	if loser.band != null:
		TroopOps.gain_xp(ctx, loser.band, TroopOps.battle_xp(strength_a if winner == a else strength_b, false))
	ctx.bump(&"ledger_troops_fallen", fallen)
	_take_commoner_captives(ctx, winner, loser, fallen, site_id)
	_named_fates(ctx, winner, loser, site_id, rng)
	_loot(winner, loser)
	ctx.events.battle_resolved.emit(winner.label, loser.label, site_id)
	ctx.events.band_beaten.emit(winner.band.id if winner.band != null else -1, loser.band.id if loser.band != null else -1)
	if winner.band != null:
		WarbandOps.destroy_if_empty(ctx, winner.band)
	if loser.band != null:
		WarbandOps.destroy_if_empty(ctx, loser.band)
	return winner


static func _apply_casualties(side: BattleSide, share: float, rng: RandomNumberGenerator) -> int:
	var fallen: int = 0
	var ids: Array[StringName] = []
	ids.assign(side.troops.keys())
	ids.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	for id: StringName in ids:
		var count: int = side.troops[id]
		var lost: int = mini(count, PopService.random_round(rng, count * share))
		fallen += lost
		if side.band != null:
			TroopOps.lose_xp(side.band, id, count, count - lost)
		if count - lost <= 0:
			side.troops.erase(id)
		else:
			side.troops[id] = count - lost
	return fallen


static func _side_race(ctx: SimContext, side: BattleSide, site_id: int) -> StringName:
	var leader: CharacterData = ctx.character(side.leader_id)
	if leader != null:
		return GeneticsService.dominant_race(leader)
	if side.garrison_of != null:
		return PopService.dominant_free_race(side.garrison_of)
	var site: SettlementData = ctx.settlement(site_id)
	return PopService.dominant_free_race(site) if site != null else &""


## The fallen include those taken alive. The winner's law decides if they are held.
static func _take_commoner_captives(ctx: SimContext, winner: BattleSide, loser: BattleSide, fallen: int, site_id: int) -> void:
	var race: StringName = _side_race(ctx, loser, site_id)
	if race == &"":
		return
	var laws: FactionLawsData = LegalService.laws_for(ctx, winner.faction_id)
	if not LegalService.can_enslave_standing(laws, LegalService.race_standing(laws, race), SimEnums.BondageOrigin.CAPTIVE):
		return
	var taken: int = roundi(fallen * CAPTIVE_SHARE)
	if taken <= 0:
		return
	if winner.band != null:
		var held: int = winner.band.captives.get(race, 0)
		winner.band.captives[race] = held + taken
		ctx.bump(&"captives_taken", taken)
	elif winner.garrison_of != null:
		PopService.get_or_create(winner.garrison_of, race, SimEnums.LegalStatus.ENSLAVED).count += taken
		ctx.events.pop_enslaved.emit(winner.garrison_of.id, race, taken, SimEnums.BondageOrigin.CAPTIVE)


static func _named_fates(ctx: SimContext, winner: BattleSide, loser: BattleSide, site_id: int, rng: RandomNumberGenerator) -> void:
	if winner.band != null:
		var ours: Array[int] = winner.band.member_ids.duplicate()
		for id: int in ours:
			if rng.randf() < NAMED_WOUNDED_WINNER:
				LimbService.battle_wounds(ctx, ctx.character(id), rng.randi_range(1, NAMED_BLOWS_WINNER), rng)
	if loser.band == null:
		return
	var theirs: Array[int] = loser.band.member_ids.duplicate()
	for id: int in theirs:
		var c: CharacterData = ctx.character(id)
		if c == null:
			continue
		if rng.randf() < NAMED_WOUNDED_LOSER:
			LimbService.battle_wounds(ctx, c, rng.randi_range(1, NAMED_BLOWS_LOSER), rng)
			if ctx.character(id) == null:
				continue
		if rng.randf() < NAMED_CAPTURE_LOSER:
			_capture_named(ctx, c, winner, site_id)


## Where the winner's law forbids it, a captive walks free after the battle.
static func _capture_named(ctx: SimContext, c: CharacterData, winner: BattleSide, site_id: int) -> bool:
	var owner_kind: SimEnums.OwnerKind = SimEnums.OwnerKind.FACTION
	var owner_id: int = winner.faction_id
	if winner.faction_id < 0:
		# Unaligned winners hold captives personally, so the leader must have survived the battle.
		if ctx.character(winner.leader_id) == null:
			return false
		owner_kind = SimEnums.OwnerKind.CHARACTER
		owner_id = winner.leader_id
	if c.settlement_id < 0:
		c.settlement_id = site_id
	return BondageService.enslave_character(ctx, c, SimEnums.BondageOrigin.CAPTIVE, winner.faction_id, owner_kind, owner_id)


static func _loot(winner: BattleSide, loser: BattleSide, share: float = LOOT_SHARE) -> void:
	if winner.band == null or loser.band == null:
		return
	var taken: int = roundi(loser.band.inventory.gold * share)
	loser.band.inventory.gold -= taken
	winner.band.inventory.gold += taken
	for id: StringName in loser.band.inventory.goods:
		var count: int = loser.band.inventory.goods[id]
		var moved: int = roundi(count * share)
		loser.band.inventory.goods[id] = count - moved
		var have: int = winner.band.inventory.goods.get(id, 0)
		winner.band.inventory.goods[id] = have + moved


## A band gives itself up without a blow. Its chest and its troops go to the winner if the winner's law can hold them. Its
## named people are taken, or if the law forbids it, robbed and let go. The band is over either way.
static func surrender(ctx: SimContext, loser_band: WarbandData, winner_band: WarbandData, site_id: int) -> void:
	var winner: BattleSide = BattleSide.from_band(winner_band)
	var loser: BattleSide = BattleSide.from_band(loser_band)
	_loot(winner, loser, 1.0)
	take_alive(ctx, winner, _side_race(ctx, loser, site_id), WarbandOps.troop_count(loser_band), site_id)
	loser_band.troops.clear()
	var people: Array[int] = loser_band.member_ids.duplicate()
	people.sort()
	for id: int in people:
		var c: CharacterData = ctx.character(id)
		if c == null:
			continue
		if not _capture_named(ctx, c, winner, site_id):
			winner_band.inventory.gold += c.inventory.gold
			c.inventory.gold = 0
	ctx.events.battle_resolved.emit(winner.label, loser.label, site_id)
	ctx.events.band_beaten.emit(winner.band.id if winner.band != null else -1, loser.band.id if loser.band != null else -1)
	if ctx.world.warbands.has(loser_band.id):
		WarbandOps.destroy(ctx, loser_band)


## People beaten but alive. The winner holds them if the law lets it, and they count among the fallen, as they do in any
## battle. Otherwise they go free and join the people of the nearest town.
static func take_alive(ctx: SimContext, winner: BattleSide, race: StringName, count: int, site_id: int) -> void:
	if count <= 0:
		return
	var laws: FactionLawsData = LegalService.laws_for(ctx, winner.faction_id)
	if winner.band != null and race != &"" and LegalService.can_enslave_standing(laws, LegalService.race_standing(laws, race), SimEnums.BondageOrigin.CAPTIVE):
		var held: int = winner.band.captives.get(race, 0)
		winner.band.captives[race] = held + count
		ctx.bump(&"captives_taken", count)
		ctx.bump(&"ledger_troops_fallen", count)
		return
	var s: SettlementData = ctx.settlement(site_id)
	if s != null:
		WarbandOps.return_to_population(s, count)
