class_name Outfits
extends RefCounted
## What people wear when nobody chose for them: by their people, their wealth and their work. Everyone gets
## underwear. Choices between garments are made from the person's id, never from a random stream, so dressing
## someone moves no other outcome. Changing what someone wears afterwards goes through Actions.wear.

const TIERS: int = 5
const BONDED: int = 0
const POOR: int = 1
const COMMON: int = 2
const WELL_OFF: int = 3
const NOBLE: int = 4
const TIER_NAMES: Array[String] = ["bonded", "poor", "common", "well-off", "noble"]
## Coin carried that lifts a commoner a step.
const COMFORTABLE_GOLD: int = 60
const RICH_GOLD: int = 400
## Forms with a body of their own. None of the human cloth fits them yet, so they go bare but for what they hold.
const OWN_BODY_FORMS: Array[StringName] = [&"kheth"]
## Who a rule dresses.
const ANYONE: int = 0
const MEN: int = 1
const WOMEN: int = 2

## A people's ways, slot by slot: [slot, lowest tier, highest tier, who, choices]. The first rule that fits a person
## gives their slot one of its choices; &"" among them leaves the slot bare. Peoples not listed dress as the Marches.
const WAYS: Dictionary[StringName, Array] = {
	&"hallowed": [
		[&"shirt", 0, 0, ANYONE, [&"short_tunic"]], [&"shirt", 1, 2, MEN, [&"shirt", &"tunic", &"tunic"]], [&"shirt", 3, 3, MEN, [&"tunic", &"doublet"]],
		[&"shirt", 4, 4, MEN, [&"doublet"]], [&"shirt", 1, 3, WOMEN, [&"gown"]], [&"shirt", 4, 4, WOMEN, [&"fine_gown"]],
		[&"trousers", 0, 2, MEN, [&"trousers"]], [&"trousers", 3, 4, MEN, [&"hose"]],
		[&"over", 3, 3, MEN, [&"coat", &""]], [&"over", 4, 4, MEN, [&"surcoat", &"fine_robe"]],
		[&"head", 0, 1, MEN, [&"hood", &"cap", &"straw_hat", &""]], [&"head", 2, 3, MEN, [&"hood", &"felt_hat", &"cap"]],
		[&"head", 1, 3, WOMEN, [&"veil", &"veil", &""]], [&"head", 4, 4, ANYONE, [&"circlet", &""]],
		[&"feet", 0, 0, ANYONE, [&"", &"turnshoes"]], [&"feet", 1, 2, ANYONE, [&"turnshoes", &"short_boots"]], [&"feet", 3, 3, ANYONE, [&"short_boots", &"boots"]],
		[&"feet", 4, 4, MEN, [&"tall_boots"]], [&"feet", 4, 4, WOMEN, [&"turnshoes"]],
		[&"belt", 1, 4, ANYONE, [&"belt"]], [&"cloak", 3, 3, ANYONE, [&"cloak", &""]], [&"cloak", 4, 4, ANYONE, [&"fine_cloak"]],
		[&"hands", 4, 4, MEN, [&"leather_gloves", &""]],
	],
	&"rime": [
		[&"shirt", 0, 3, MEN, [&"tunic"]], [&"shirt", 4, 4, MEN, [&"doublet"]], [&"shirt", 0, 3, WOMEN, [&"gown"]], [&"shirt", 4, 4, WOMEN, [&"fine_gown"]],
		[&"trousers", 0, 1, MEN, [&"trousers"]], [&"trousers", 2, 4, MEN, [&"fur_trousers", &"trousers"]],
		[&"over", 2, 4, ANYONE, [&"fur_coat", &""]], [&"cloak", 1, 2, ANYONE, [&"cloak", &""]], [&"cloak", 3, 4, ANYONE, [&"fur_cloak"]],
		[&"head", 0, 0, ANYONE, [&"hood"]], [&"head", 1, 3, ANYONE, [&"fur_hat", &"hood"]], [&"head", 4, 4, ANYONE, [&"circlet", &"fur_hat"]],
		[&"feet", 0, 0, ANYONE, [&"turnshoes"]], [&"feet", 1, 4, ANYONE, [&"fur_boots", &"short_boots"]],
		[&"hands", 1, 4, ANYONE, [&"fur_mitts", &""]], [&"belt", 1, 4, ANYONE, [&"belt"]],
	],
	&"steppe": [
		[&"shirt", 0, 4, ANYONE, [&"shirt"]], [&"trousers", 0, 4, ANYONE, [&"trousers"]],
		[&"over", 1, 1, ANYONE, [&"coat", &""]], [&"over", 2, 4, ANYONE, [&"kaftan"]],
		[&"head", 0, 4, ANYONE, [&"fur_hat", &"felt_hat"]], [&"feet", 0, 0, ANYONE, [&"short_boots"]], [&"feet", 1, 4, ANYONE, [&"tall_boots"]],
		[&"belt", 0, 4, ANYONE, [&"sash"]], [&"cloak", 3, 4, ANYONE, [&"fur_cloak", &""]],
	],
	&"sunborn": [
		[&"shirt", 0, 4, MEN, [&"shirt"]], [&"shirt", 0, 3, WOMEN, [&"gown"]], [&"shirt", 4, 4, WOMEN, [&"fine_gown"]],
		[&"trousers", 1, 4, MEN, [&"trousers"]],
		[&"over", 0, 2, ANYONE, [&"desert_wrap"]], [&"over", 3, 3, ANYONE, [&"kaftan"]], [&"over", 4, 4, ANYONE, [&"fine_robe", &"kaftan"]],
		[&"head", 0, 4, MEN, [&"turban"]], [&"head", 0, 4, WOMEN, [&"veil"]],
		[&"feet", 0, 2, ANYONE, [&"sandals"]], [&"feet", 3, 4, ANYONE, [&"turnshoes"]], [&"belt", 1, 4, ANYONE, [&"sash"]],
	],
	&"tidebound": [
		[&"shirt", 1, 4, ANYONE, [&"short_tunic", &""]], [&"trousers", 0, 4, ANYONE, [&"kilt"]],
		[&"head", 0, 3, ANYONE, [&"straw_hat", &""]], [&"head", 4, 4, ANYONE, [&"circlet"]],
		[&"feet", 2, 4, ANYONE, [&"sandals"]], [&"belt", 2, 4, ANYONE, [&"sash"]],
	],
	&"freehold": [
		[&"shirt", 0, 4, ANYONE, [&"tunic"]], [&"trousers", 0, 4, ANYONE, [&"trousers"]],
		[&"over", 1, 2, ANYONE, [&"jerkin", &""]], [&"over", 3, 4, ANYONE, [&"coat", &"jerkin"]],
		[&"head", 0, 3, ANYONE, [&"hood", &"cap"]], [&"head", 4, 4, ANYONE, [&"circlet"]],
		[&"feet", 0, 1, ANYONE, [&"short_boots"]], [&"feet", 2, 4, ANYONE, [&"boots"]],
		[&"hands", 2, 4, ANYONE, [&"leather_gloves", &""]], [&"belt", 0, 4, ANYONE, [&"belt"]], [&"cloak", 3, 4, ANYONE, [&"fur_cloak", &"cloak"]],
	],
	&"veiled": [
		[&"shirt", 0, 3, MEN, [&"tunic"]], [&"shirt", 4, 4, MEN, [&"doublet"]], [&"shirt", 0, 3, WOMEN, [&"gown"]], [&"shirt", 4, 4, WOMEN, [&"fine_gown"]],
		[&"trousers", 0, 4, MEN, [&"hose"]], [&"over", 1, 3, ANYONE, [&"robe", &""]], [&"over", 4, 4, ANYONE, [&"fine_robe"]],
		[&"head", 0, 3, WOMEN, [&"veil", &""]], [&"head", 0, 3, MEN, [&"hood", &""]], [&"head", 4, 4, ANYONE, [&"circlet"]],
		[&"feet", 0, 4, ANYONE, [&"turnshoes"]], [&"belt", 1, 4, ANYONE, [&"belt", &"sash"]], [&"cloak", 2, 3, ANYONE, [&"cloak", &""]],
		[&"cloak", 4, 4, ANYONE, [&"fine_cloak"]],
	],
	&"ashen": [
		[&"shirt", 1, 4, ANYONE, [&"short_tunic"]], [&"trousers", 0, 4, ANYONE, [&"trousers", &"fur_trousers"]],
		[&"over", 2, 2, ANYONE, [&"jerkin", &""]], [&"over", 3, 4, ANYONE, [&"fur_coat", &"jerkin"]],
		[&"head", 3, 4, ANYONE, [&"fur_hat", &""]], [&"feet", 1, 2, ANYONE, [&"boots", &""]], [&"feet", 3, 4, ANYONE, [&"fur_boots"]],
		[&"belt", 0, 4, ANYONE, [&"belt"]], [&"cloak", 4, 4, ANYONE, [&"fur_cloak"]],
	],
	&"reef": [
		[&"trousers", 1, 4, ANYONE, [&"kilt"]], [&"head", 2, 4, ANYONE, [&"straw_hat", &""]], [&"belt", 3, 4, ANYONE, [&"sash"]],
	],
}
## The underwear everyone wears, whoever their people: a loincloth for the bonded, braies or drawers and a shift or
## undershirt for most, a fine chemise for the great.
const UNDER: Array = [
	[&"underwear_bottom", 0, 0, ANYONE, [&"loincloth"]], [&"underwear_bottom", 1, 1, MEN, [&"braies", &"loincloth"]],
	[&"underwear_bottom", 1, 1, WOMEN, [&"loincloth", &"drawers"]], [&"underwear_bottom", 2, 4, MEN, [&"braies", &"braies", &"drawers"]],
	[&"underwear_bottom", 2, 4, WOMEN, [&"drawers"]],
	[&"underwear_top", 0, 0, WOMEN, [&"breast_band"]], [&"underwear_top", 1, 1, WOMEN, [&"breast_band", &"shift"]],
	[&"underwear_top", 2, 3, WOMEN, [&"shift"]], [&"underwear_top", 1, 1, MEN, [&"undershirt", &""]],
	[&"underwear_top", 2, 2, MEN, [&"undershirt", &"sark"]], [&"underwear_top", 3, 3, MEN, [&"sark"]],
	[&"underwear_top", 4, 4, ANYONE, [&"chemise"]],
]
## Peoples of hot lands, who wear less under: a loincloth or drawers, a breast band, and linen only when well off.
const HOT_PEOPLES: Array[StringName] = [&"sunborn", &"tidebound", &"reef"]
const UNDER_HOT: Array = [
	[&"underwear_bottom", 0, 1, ANYONE, [&"loincloth"]], [&"underwear_bottom", 2, 4, ANYONE, [&"drawers"]],
	[&"underwear_top", 0, 2, WOMEN, [&"breast_band"]], [&"underwear_top", 3, 3, WOMEN, [&"shift"]],
	[&"underwear_top", 3, 3, MEN, [&"undershirt", &""]], [&"underwear_top", 4, 4, ANYONE, [&"chemise"]],
]
const DEFAULT_WAYS: StringName = &"hallowed"


## A whole outfit for a person of this people, sex and wealth, as garment ids, one per slot. job adds what a
## ruler wears. pick chooses among the choices the same way every time for the same person.
static func outfit(defs: DefCatalog, culture_id: StringName, race_id: StringName, male: bool, tier: int, job: StringName, pick: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if not fits_race(defs, race_id):
		return out
	var ways: Array = WAYS.get(culture_id, WAYS[DEFAULT_WAYS]) as Array
	var filled: Dictionary[StringName, bool] = {}
	for rules: Array in [UNDER_HOT if HOT_PEOPLES.has(culture_id) else UNDER, ways]:
		for rule: Variant in rules:
			var r: Array = rule as Array
			var slot: StringName = r[0] as StringName
			if filled.has(slot) or tier < (r[1] as int) or tier > (r[2] as int) or not _dresses(r[3] as int, male):
				continue
			filled[slot] = true
			var choices: Array = r[4] as Array
			var chosen: StringName = choices[posmod(hash([pick, slot]), choices.size())] as StringName
			if chosen != &"" and _fits(defs, chosen, race_id):
				out.append(chosen)
	if job == &"ruler":
		put_on(defs, out, &"crown")
	return out


## Whether a race wears the shared garments at all.
static func fits_race(defs: DefCatalog, race_id: StringName) -> bool:
	return defs.races.has(race_id) and not OWN_BODY_FORMS.has(defs.races[race_id].form)


static func _fits(defs: DefCatalog, garment_id: StringName, race_id: StringName) -> bool:
	if not defs.armours.has(garment_id):
		return false
	var def: GarmentDef = defs.armours[garment_id] as GarmentDef
	if def == null:
		return true
	if def.race_ids.is_empty():
		return fits_race(defs, race_id)
	return def.race_ids.has(race_id)


static func _dresses(who: int, male: bool) -> bool:
	return who == ANYONE or (who == MEN) == male


## How well off someone looks: the law they live under, their work, and what they carry.
static func tier_of(ctx: SimContext, c: CharacterData) -> int:
	if not LegalService.is_free(c) or c.occupation == &"bonded":
		return BONDED
	var tier: int = POOR
	match c.occupation:
		&"ruler", &"noble":
			tier = NOBLE
		&"merchant":
			tier = WELL_OFF
		&"soldier":
			tier = COMMON
	if c.inventory.gold >= RICH_GOLD:
		tier = maxi(tier, WELL_OFF)
	elif c.inventory.gold >= COMFORTABLE_GOLD:
		tier = maxi(tier, COMMON)
	var f: FactionData = ctx.faction(c.faction_id)
	if f != null and f.ruler_id == c.id:
		tier = NOBLE
	return tier


## The people whose ways a person dresses in: their town's if it is of their race, else their realm's, else the
## first people of their race.
static func culture_of(ctx: SimContext, c: CharacterData) -> StringName:
	var race: StringName = GeneticsService.dominant_race(c)
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s != null and ctx.defs.cultures.has(s.culture_id) and ctx.defs.cultures[s.culture_id].primary_race == race:
		return s.culture_id
	var people: CultureDef = CharacterFactory.people_of(ctx, race, c.faction_id)
	if people != null:
		return people.id
	return Actions.culture_for_race(ctx, race)


## Dresses someone in their people's clothes for their wealth and work, in place of whatever they had on. For
## people coming into the world; anyone already in it changes clothes through Actions.wear.
## tier, when given, stands for how well off they look.
static func dress(ctx: SimContext, c: CharacterData, tier: int = -1) -> void:
	if tier < 0:
		tier = tier_of(ctx, c)
	var f: FactionData = ctx.faction(c.faction_id)
	var job: StringName = &"ruler" if f != null and f.ruler_id == c.id else c.occupation
	c.equipment.armour_ids = outfit(ctx.defs, culture_of(ctx, c), GeneticsService.dominant_race(c), c.sex == SimEnums.Sex.MALE, tier, job, c.id)


## What a soldier of this kind wears: the troop's own kit, with their people's everyday clothes in any slot it leaves.
## A race with a body of its own still wears the kit, as what it stops counts, though none of it is drawn yet.
static func troop_outfit(defs: DefCatalog, troop: TroopDef, culture_id: StringName, male: bool, race_id: StringName = &"human", pick: int = 0) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(troop.armour_ids)
	if not fits_race(defs, race_id):
		return out
	# Armour shows: no coat or cloak over it, and no hat under a helmet.
	var armoured: bool = not slot_free(defs, out, &"gambeson")
	var helmed: bool = not slot_free(defs, out, &"helmet")
	for id: StringName in outfit(defs, culture_id, race_id, male, COMMON, &"soldier", pick):
		var slot: StringName = GarmentDef.slot_of(defs.armours[id])
		if (armoured and (slot == &"over" or slot == &"cloak")) or (helmed and slot == &"head"):
			continue
		if slot_free(defs, out, id):
			out.append(id)
	return out


## Whether nothing worn yet takes the slot this garment would.
static func slot_free(defs: DefCatalog, worn: Array[StringName], garment_id: StringName) -> bool:
	if not defs.armours.has(garment_id):
		return false
	var slot: StringName = GarmentDef.slot_of(defs.armours[garment_id])
	for id: StringName in worn:
		if defs.armours.has(id) and GarmentDef.slot_of(defs.armours[id]) == slot:
			return false
	return true


## Puts a garment into a list of worn ids, in place of whatever had its slot. For outfits being made up, not for
## anyone already in the world.
static func put_on(defs: DefCatalog, worn: Array[StringName], garment_id: StringName) -> void:
	if not defs.armours.has(garment_id):
		return
	var slot: StringName = GarmentDef.slot_of(defs.armours[garment_id])
	for i: int in range(worn.size() - 1, -1, -1):
		if defs.armours.has(worn[i]) and GarmentDef.slot_of(defs.armours[worn[i]]) == slot:
			worn.remove_at(i)
	worn.append(garment_id)
