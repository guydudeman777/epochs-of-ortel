class_name LegalService
extends RefCounted
## What the law of a realm allows. Applies to the player and every NPC alike.

const MIXED_HERITAGE_MIN_SHARE: float = 0.2

static var _lawless: FactionLawsData = null


## No realm means no law: nobody is protected and nothing is forbidden.
static func laws_for(ctx: SimContext, faction_id: int) -> FactionLawsData:
	var f: FactionData = ctx.faction(faction_id)
	if f != null:
		return f.laws
	if _lawless == null:
		_lawless = FactionLawsData.new()
		_lawless.bondage_law = SimEnums.BondageLaw.CHATTEL
	return _lawless


static func race_standing(laws: FactionLawsData, race_id: StringName) -> int:
	return laws.race_standing.get(race_id, SimEnums.RaceStanding.TOLERATED)


## A character's standing under a realm's law, including how it ranks mixed heritage.
static func standing_of(ctx: SimContext, c: CharacterData, faction_id: int) -> int:
	var laws: FactionLawsData = laws_for(ctx, faction_id)
	if laws.mixed_heritage_rule == SimEnums.MixedHeritageRule.DOMINANT:
		return race_standing(laws, GeneticsService.dominant_race(c))
	var lowest: int = SimEnums.RaceStanding.PRIVILEGED
	for race: StringName in c.genetics.ancestry:
		var share: float = c.genetics.ancestry[race]
		if share >= MIXED_HERITAGE_MIN_SHARE:
			lowest = mini(lowest, race_standing(laws, race))
	return lowest


static func is_free(c: CharacterData) -> bool:
	return c.legal.status == SimEnums.LegalStatus.FREE


static func is_bonded(c: CharacterData) -> bool:
	return c.legal.status == SimEnums.LegalStatus.ENSLAVED or c.legal.status == SimEnums.LegalStatus.INDENTURED


static func can_hold_title(ctx: SimContext, c: CharacterData, faction_id: int) -> bool:
	return is_free(c) and standing_of(ctx, c, faction_id) >= SimEnums.RaceStanding.CITIZEN


static func can_own_business(ctx: SimContext, c: CharacterData, faction_id: int) -> bool:
	return is_free(c) and standing_of(ctx, c, faction_id) >= SimEnums.RaceStanding.TOLERATED


static func can_bear_arms(ctx: SimContext, c: CharacterData, faction_id: int) -> bool:
	return is_free(c) and standing_of(ctx, c, faction_id) >= SimEnums.RaceStanding.TOLERATED


static func can_trade(ctx: SimContext, c: CharacterData, faction_id: int) -> bool:
	return is_free(c) and standing_of(ctx, c, faction_id) >= SimEnums.RaceStanding.TOLERATED


static func pop_can_bear_arms(group: PopGroupData, laws: FactionLawsData) -> bool:
	return group.status == SimEnums.LegalStatus.FREE and race_standing(laws, group.race_id) >= SimEnums.RaceStanding.TOLERATED


## Whether a realm's law permits bondage of this standing by this route.
static func can_enslave_standing(laws: FactionLawsData, standing: int, origin: SimEnums.BondageOrigin) -> bool:
	match origin:
		SimEnums.BondageOrigin.PENAL:
			return laws.bondage_law >= SimEnums.BondageLaw.PENAL_ONLY
		SimEnums.BondageOrigin.DEBT:
			return laws.bondage_law >= SimEnums.BondageLaw.DEBT
		SimEnums.BondageOrigin.BIRTH:
			return laws.hereditary_bondage and laws.bondage_law >= SimEnums.BondageLaw.DEBT
		SimEnums.BondageOrigin.CAPTIVE, SimEnums.BondageOrigin.RAID:
			return laws.bondage_law == SimEnums.BondageLaw.CHATTEL and standing <= SimEnums.RaceStanding.TOLERATED
	return false


static func allows_forced_labor(laws: FactionLawsData) -> bool:
	return laws.bondage_law != SimEnums.BondageLaw.BANNED
