class_name WorldGenerator
extends RefCounted
## Peoples the one land with a starting world. The land and who holds it are the same in every game, and the people in
## it come from the seed. Emits nothing to the game's event bus:
## generation is not history.

const LAND_ID: StringName = &"ortel"
## People, walls and felled woods for a town, a city and a capital on the first day.
const PEOPLE_BY_TIER: Array[int] = [600, 1600, 2600]
const WALLS_BY_TIER: Array[float] = [1.05, 1.8, 2.2]
const STARTING_CLEARING: Array[float] = [26.0, 40.0, 48.0]
## Shares of a town that are of another race than its realm's.
const HUMAN_MINORITY: float = 0.2
const OLD_RACE_MINORITY: float = 0.03
const NAMED_BONDED_SHARE: float = 0.05
const ROOM_FOR_NEW_SETTLEMENTS: float = 1.8


static func generate(config: WorldGenConfig, catalog: DefCatalog) -> WorldState:
	var state: WorldState = WorldState.new()
	state.world_seed = config.world_seed
	state.named_target = config.named_target
	var hub: EventHub = EventHub.new()
	var ctx: SimContext = SimContext.new(state, catalog, hub)
	var rng: RandomNumberGenerator = ctx.rng(&"worldgen")
	var land: LandDef = catalog.land
	var sites: Dictionary[int, int] = _make_map(ctx, land)
	state.max_settlements = roundi(sites.size() * ROOM_FOR_NEW_SETTLEMENTS)
	var factions: Dictionary[StringName, FactionData] = _make_factions(ctx, land)
	_make_settlements(ctx, land, sites, factions, rng)
	ctx.paths.rebuild(state.map)
	_make_people(ctx, config, land, factions, rng)
	_sell_some_businesses(ctx, rng)
	_make_warbands(ctx, rng)
	if config.place_player:
		_place_player(ctx, rng)
	for id: int in ctx.settlement_ids():
		Pricing.update_settlement(ctx, ctx.world.settlements[id])
	ctx.rebuild_indexes()
	ctx.sync_rng_to_world()
	hub.free()
	return state


## Every place the land has people in on the first day, in the order they are written. Place index -> settlement id.
static func _make_map(ctx: SimContext, land: LandDef) -> Dictionary[int, int]:
	var ids: Dictionary[int, int] = {}
	var map: MapData = ctx.world.map
	map.land_id = LAND_ID
	for i: int in range(land.places.size()):
		var place: PlaceDef = land.places[i]
		if place.realm == &"":
			continue
		var id: int = ctx.new_id()
		ids[i] = id
		map.positions[id] = place.position
		map.clearings[id] = STARTING_CLEARING[place.tier]
	for road: Vector2i in land.roads:
		var edge: Vector2i = Vector2i(ids[road.x], ids[road.y])
		map.roads.append(edge)
		map.road_bends[edge] = land.road_bends[road]
	return ids


static func _make_factions(ctx: SimContext, land: LandDef) -> Dictionary[StringName, FactionData]:
	var out: Dictionary[StringName, FactionData] = {}
	for realm: RealmDef in land.realms:
		var f: FactionData = FactionOps.create_faction(ctx, realm.display_name, realm.culture, null)
		f.treasury = 3000
		out[realm.id] = f
	return out


static func _make_settlements(ctx: SimContext, land: LandDef, sites: Dictionary[int, int], factions: Dictionary[StringName, FactionData], rng: RandomNumberGenerator) -> void:
	var indexes: Array[int] = []
	indexes.assign(sites.keys())
	indexes.sort()
	for i: int in indexes:
		var place: PlaceDef = land.places[i]
		var f: FactionData = factions[place.realm]
		var s: SettlementData = SettlementData.new()
		s.id = sites[i]
		s.display_name = place.display_name
		s.place_id = place.id
		s.faction_id = f.id
		s.culture_id = f.culture_id
		ctx.world.settlements[s.id] = s
		f.settlement_ids.append(s.id)
		_populate(ctx, s, f, ctx.defs.cultures[f.culture_id], place, rng)
		_equip(ctx, s, f, place, rng)
	for realm: RealmDef in land.realms:
		factions[realm.id].settlement_ids.sort()
	_bind_towns(ctx, land, sites)


## Towns on the map are work places bound to the nearest city of their own realm.
static func _bind_towns(ctx: SimContext, land: LandDef, sites: Dictionary[int, int]) -> void:
	var indexes: Array[int] = []
	indexes.assign(sites.keys())
	indexes.sort()
	for i: int in indexes:
		var place: PlaceDef = land.places[i]
		if place.tier != PlaceDef.Tier.TOWN:
			continue
		var s: SettlementData = ctx.world.settlements[sites[i]]
		s.kind = SimEnums.SettlementKind.TOWN
		s.specialty = place.trades[0] if not place.trades.is_empty() else &"farm"
		var best: float = INF
		for j: int in indexes:
			var other: PlaceDef = land.places[j]
			if other.tier == PlaceDef.Tier.TOWN or other.realm != place.realm:
				continue
			var d: float = other.position.distance_squared_to(place.position)
			if d < best:
				best = d
				s.city_id = sites[j]


static func _populate(ctx: SimContext, s: SettlementData, f: FactionData, culture: CultureDef, place: PlaceDef, rng: RandomNumberGenerator) -> void:
	var people: int = roundi(PEOPLE_BY_TIER[place.tier] * rng.randf_range(0.85, 1.15))
	s.capacity = roundi(people * rng.randf_range(1.6, 2.4))
	var primary: int = people
	for race: StringName in ctx.defs.race_ids:
		if race != culture.primary_race:
			primary -= roundi(people * (HUMAN_MINORITY if race == &"human" else OLD_RACE_MINORITY))
	if f.laws.bondage_law == SimEnums.BondageLaw.DEBT:
		PopService.get_or_create(s, culture.primary_race, SimEnums.LegalStatus.SERF).count = roundi(primary * 0.15)
		PopService.get_or_create(s, culture.primary_race, SimEnums.LegalStatus.INDENTURED).count = roundi(primary * 0.05)
		primary = roundi(primary * 0.8)
	PopService.get_or_create(s, culture.primary_race, SimEnums.LegalStatus.FREE).count = primary
	var minorities: Array[StringName] = []
	for race: StringName in ctx.defs.race_ids:
		if race != culture.primary_race:
			minorities.append(race)
	for race: StringName in minorities:
		# Humans are everywhere. The old races are few outside their own realms.
		var share: int = roundi(people * (HUMAN_MINORITY if race == &"human" else OLD_RACE_MINORITY))
		var standing: int = LegalService.race_standing(f.laws, race)
		var bonded: int = 0
		if f.laws.bondage_law == SimEnums.BondageLaw.CHATTEL and standing <= SimEnums.RaceStanding.SUBJUGATED:
			bonded = roundi(share * 0.7)
			PopService.get_or_create(s, race, SimEnums.LegalStatus.ENSLAVED).count = bonded
		PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count = share - bonded


static func _equip(ctx: SimContext, s: SettlementData, f: FactionData, place: PlaceDef, rng: RandomNumberGenerator) -> void:
	var people: int = PopService.total(s)
	s.purse = people * 3
	s.fortification = WALLS_BY_TIER[place.tier] + rng.randf_range(-0.05, 0.05)
	for good: StringName in ctx.defs.good_ids:
		s.stock[good] = roundi(maxf(ctx.defs.goods[good].demand_per_100, 0.2) * people * 0.01 * 3.0)
	s.garrison = TroopOps.starting_garrison(ctx, s, people)
	var enslaved: int = PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED)
	var food_needed: int = ceili(people * 0.22)
	var grows: float = LandOps.fertility(ctx, s)
	if enslaved >= 150 and f.laws.bondage_law == SimEnums.BondageLaw.CHATTEL:
		_add_business(ctx, s, &"plantation", f)
		food_needed -= roundi(330 * grows)
	for trade: StringName in place.trades:
		if trade == &"fishery":
			food_needed -= 45
	while food_needed > 0:
		_add_business(ctx, s, &"farm", f)
		food_needed -= roundi(100 * grows)
	_add_business(ctx, s, &"farm", f)
	for trade: StringName in place.trades:
		_add_business(ctx, s, trade, f)


static func _add_business(ctx: SimContext, s: SettlementData, building: StringName, f: FactionData) -> void:
	var b: BusinessData = BusinessData.new()
	b.id = ctx.new_id()
	b.building_id = building
	b.settlement_id = s.id
	b.owner_kind = SimEnums.OwnerKind.FACTION
	b.owner_id = f.id
	ctx.world.businesses[b.id] = b
	s.business_ids.append(b.id)


static func _make_people(ctx: SimContext, config: WorldGenConfig, land: LandDef, factions: Dictionary[StringName, FactionData], rng: RandomNumberGenerator) -> void:
	var quota_per_site: int = floori(config.named_target / float(maxi(ctx.world.settlements.size(), 1)))
	for realm: RealmDef in land.realms:
		var f: FactionData = factions[realm.id]
		var capital: SettlementData = ctx.settlement(f.settlement_ids[0]) if not f.settlement_ids.is_empty() else null
		if capital == null:
			continue
		var culture: CultureDef = ctx.defs.cultures[f.culture_id]
		var ruling: Array[CharacterData] = _make_household(ctx, capital, f, culture, culture.primary_race, &"noble", rng)
		ctx.world.dynasties[ruling[0].dynasty_id].display_name = realm.house
		FactionOps.set_ruler(ctx, f, ruling[0])
	for s_id: int in ctx.settlement_ids():
		var s: SettlementData = ctx.world.settlements[s_id]
		var f: FactionData = ctx.faction(s.faction_id)
		var culture: CultureDef = ctx.defs.cultures[f.culture_id]
		var made: int = 0
		for bonded: int in range(roundi(quota_per_site * NAMED_BONDED_SHARE)):
			var group: PopGroupData = PopService.largest_group(s, SimEnums.LegalStatus.ENSLAVED)
			if group == null:
				group = PopService.largest_group(s, SimEnums.LegalStatus.INDENTURED)
			if group != null and CharacterFactory.promote_commoner(ctx, s, group, &"bonded") != null:
				made += 1
		while made < quota_per_site:
			var race: StringName = _pick_free_race(s, rng)
			var household: Array[CharacterData] = _make_household(ctx, s, f, culture, race, _pick_occupation(rng), rng)
			made += household.size()


static func _pick_free_race(s: SettlementData, rng: RandomNumberGenerator) -> StringName:
	var total_free: int = PopService.total_with_status(s, SimEnums.LegalStatus.FREE)
	var roll: int = rng.randi_range(0, maxi(total_free - 1, 0))
	for group: PopGroupData in s.pop_groups:
		if group.status != SimEnums.LegalStatus.FREE:
			continue
		roll -= group.count
		if roll < 0:
			return group.race_id
	return s.pop_groups[0].race_id


static func _pick_occupation(rng: RandomNumberGenerator) -> StringName:
	var roll: float = rng.randf()
	if roll < 0.1:
		return &"noble"
	if roll < 0.25:
		return &"merchant"
	if roll < 0.4:
		return &"soldier"
	return &"commoner"


static func _starting_gold(occupation: StringName, rng: RandomNumberGenerator) -> int:
	match occupation:
		&"noble", &"ruler":
			return rng.randi_range(200, 600)
		&"merchant":
			return rng.randi_range(150, 400)
		&"soldier":
			return rng.randi_range(30, 90)
	return rng.randi_range(15, 40)


## A married couple and their children. The first entry is the head of the household.
static func _make_household(ctx: SimContext, s: SettlementData, f: FactionData, culture: CultureDef, race_id: StringName,
		occupation: StringName, rng: RandomNumberGenerator) -> Array[CharacterData]:
	var race: RaceDef = ctx.defs.races[race_id]
	var dynasty: DynastyData = DynastyData.new()
	dynasty.id = ctx.new_id()
	dynasty.display_name = culture.dynasty_names[rng.randi_range(0, culture.dynasty_names.size() - 1)]
	ctx.world.dynasties[dynasty.id] = dynasty
	var age_head: float = race.adult_age + rng.randf_range(4.0, race.lifespan * 0.35)
	var head: CharacterData = CharacterFactory.create_founder(ctx, race_id, CharacterFactory.random_sex(rng), age_head, f.id, s.id, dynasty.id, occupation)
	head.inventory.gold = _starting_gold(occupation, rng)
	var out: Array[CharacterData] = [head]
	var partner_sex: SimEnums.Sex = SimEnums.Sex.FEMALE if head.sex == SimEnums.Sex.MALE else SimEnums.Sex.MALE
	var age_partner: float = maxf(race.adult_age, age_head + rng.randf_range(-5.0, 5.0))
	var partner: CharacterData = CharacterFactory.create_founder(ctx, race_id, partner_sex, age_partner, f.id, s.id, dynasty.id, occupation)
	partner.inventory.gold = roundi(_starting_gold(occupation, rng) * 0.5)
	head.spouse_id = partner.id
	partner.spouse_id = head.id
	out.append(partner)
	var mother: CharacterData = head if head.sex == SimEnums.Sex.FEMALE else partner
	var father: CharacterData = partner if head.sex == SimEnums.Sex.FEMALE else head
	var years_as_parent: float = minf(age_head, age_partner) - race.adult_age
	for i: int in range(rng.randi_range(0, 4)):
		var child_age: float = rng.randf_range(0.0, maxf(years_as_parent, 0.1))
		var child: CharacterData = CharacterFactory.create_founder(ctx, race_id, CharacterFactory.random_sex(rng), child_age, f.id, s.id, dynasty.id, &"child")
		child.father_id = father.id
		child.mother_id = mother.id
		child.genetics.face = FaceService.child_face(ctx.rng(&"faces"), mother.genetics.face, father.genetics.face, child.sex == SimEnums.Sex.MALE)
		father.children_ids.append(child.id)
		mother.children_ids.append(child.id)
		if child_age >= race.adult_age:
			child.occupation = occupation
			child.inventory.gold = _starting_gold(occupation, rng) / 2
		out.append(child)
	return out


## Some businesses start in private hands, so ownership is not only the realm's.
static func _sell_some_businesses(ctx: SimContext, rng: RandomNumberGenerator) -> void:
	var by_site: Dictionary[int, Array] = {}
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.occupation == &"merchant" and c.spouse_id >= 0 and LegalService.can_own_business(ctx, c, c.faction_id):
			if not by_site.has(c.settlement_id):
				by_site[c.settlement_id] = []
			by_site[c.settlement_id].append(id)
	var business_ids: Array[int] = []
	business_ids.assign(ctx.world.businesses.keys())
	business_ids.sort()
	for id: int in business_ids:
		var b: BusinessData = ctx.world.businesses[id]
		if not by_site.has(b.settlement_id) or rng.randf() > 0.3:
			continue
		var owners: Array = by_site[b.settlement_id]
		var owner_id: int = owners[rng.randi_range(0, owners.size() - 1)]
		b.owner_kind = SimEnums.OwnerKind.CHARACTER
		b.owner_id = owner_id


static func _make_warbands(ctx: SimContext, rng: RandomNumberGenerator) -> void:
	var merchants: Array[int] = []
	var soldiers: Array[int] = []
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.spouse_id < 0 or not ctx.is_adult(c):
			continue
		if c.occupation == &"merchant":
			merchants.append(id)
		elif c.occupation == &"soldier":
			soldiers.append(id)
	var caravans: int = floori(ctx.world.settlements.size() * 0.7)
	for i: int in range(mini(caravans, merchants.size())):
		var leader: CharacterData = ctx.character(merchants[rng.randi_range(0, merchants.size() - 1)])
		if leader.warband_id >= 0:
			continue
		leader.inventory.gold += 200
		var made: ActionResult = Actions.form_warband(ctx, leader.id, SimEnums.WarbandRole.CARAVAN, 200)
		if made.success:
			ctx.warband(made.value).troops[TroopOps.levy_for(ctx, ctx.settlement(leader.settlement_id))] = 8
			ctx.warband(made.value).supplies = 60.0
	for i: int in range(mini(ctx.world.settlements.size() / 5, soldiers.size())):
		var leader: CharacterData = ctx.character(soldiers[rng.randi_range(0, soldiers.size() - 1)])
		if leader.warband_id >= 0:
			continue
		leader.inventory.gold += 80
		var made: ActionResult = Actions.form_warband(ctx, leader.id, SimEnums.WarbandRole.BANDIT, 80)
		if made.success:
			ctx.warband(made.value).troops[TroopOps.levy_for(ctx, ctx.settlement(leader.settlement_id))] = 12
			ctx.warband(made.value).supplies = 60.0


## The player begins as an absolute nobody: no title, little coin, and one living sibling, who is all the family there is.
static func _place_player(ctx: SimContext, rng: RandomNumberGenerator) -> void:
	var sites: Array[int] = ctx.settlement_ids()
	var s: SettlementData = ctx.settlement(sites[rng.randi_range(0, sites.size() - 1)])
	var player: CharacterData = CharacterFactory.promote_commoner(ctx, s, PopService.largest_group(s, SimEnums.LegalStatus.FREE), &"commoner")
	player.inventory.gold = 15
	var free_people: PopGroupData = PopService.find_group(s, GeneticsService.dominant_race(player), SimEnums.LegalStatus.FREE)
	var sibling: CharacterData = CharacterFactory.promote_commoner(ctx, s, free_people, &"commoner", player.dynasty_id)
	if sibling != null:
		sibling.inventory.gold = 8
	ctx.world.player_character_id = player.id
