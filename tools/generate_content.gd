extends SceneTree
## One-off authoring helper that writes the starter content as .tres files.
## Run: godot --headless --path . --script res://tools/generate_content.gd
## The .tres files are the source of truth afterwards. Re-running overwrites them.

const ROOT: String = "res://content/defs"


func _init() -> void:
	_races()
	_traits()
	_goods()
	_buildings()
	_techs()
	_cultures()
	_body_parts()
	_armours()
	_troops()
	print("content generated")
	quit(0)


func _save(res: Resource, folder: String, id: StringName) -> void:
	var dir: String = ROOT + "/" + folder
	DirAccess.make_dir_recursive_absolute(dir)
	var err: Error = ResourceSaver.save(res, dir + "/" + String(id) + ".tres")
	if err != OK:
		push_error("failed to save %s: %s" % [id, err])


func _race(id: StringName, title: String, lifespan: float, adult: int, fertility: float, food: float,
		mods: Dictionary[StringName, int], labor: Dictionary[StringName, float],
		compat: Array[StringName], female: Array[String], male: Array[String],
		heritage: Dictionary[StringName, float], bias: Dictionary[StringName, float], tint: Color, beard: float,
		ground: Dictionary[StringName, float] = {}, biome_food: Dictionary[StringName, float] = {}, features: Array[StringName] = [],
		eye_colors: Array[StringName] = [], form: StringName = &"") -> void:
	var d: RaceDef = RaceDef.new()
	d.id = id
	d.display_name = title
	d.lifespan = lifespan
	d.adult_age = adult
	d.fertility = fertility
	d.food_need = food
	var toughness_by_race: Dictionary[StringName, float] = {&"elf": 0.9, &"dwarf": 1.15, &"orc": 1.2, &"kheth": 1.25}
	var toughness: float = toughness_by_race.get(id, 1.0)
	d.toughness = toughness
	d.attribute_mods = mods
	d.labor_aptitude = labor
	d.compatible_races = compat
	d.names_female = female
	d.names_male = male
	d.face_heritage = heritage
	d.face_bias = bias
	d.face_skin_tint = tint
	d.face_beard_chance = beard
	d.ground_speed = ground
	d.biome_food = biome_food
	d.face_features = features
	d.face_eye_colors = eye_colors
	d.form = form
	_save(d, "races", id)


func _races() -> void:
	_race(&"human", "Human", 65.0, 16, 1.0, 1.0,
		{},
		{&"farming": 1.1, &"craft": 1.0, &"mining": 0.9},
		[&"elf", &"orc"],
		["Aldith", "Berta", "Cwen", "Edda", "Hild", "Isolde", "Maud", "Rohese", "Sibyl", "Wynn"],
		["Aldous", "Bertram", "Cedric", "Edric", "Godwin", "Hugh", "Osric", "Roland", "Thurstan", "Wat"],
		{&"african": 1.0, &"asian": 1.0, &"caucasian": 1.0},
		{},
		Color.WHITE, 0.55)
	_race(&"dwarf", "Dwarf", 90.0, 25, 0.6, 1.1,
		{&"might": 2, &"will": 1, &"agility": -1},
		{&"farming": 0.8, &"craft": 1.3, &"mining": 1.5},
		[],
		["Bruna", "Dagna", "Gudrun", "Helga", "Ingrid", "Runa", "Sigrid", "Thyra", "Ulfa", "Yrsa"],
		["Bardin", "Dorn", "Gorrim", "Harald", "Ivar", "Kolbein", "Orm", "Rurik", "Thrain", "Ulf"],
		{&"african": 1.0, &"asian": 1.0, &"caucasian": 1.0},
		{&"head_width": 0.45, &"jaw_bones": 0.6, &"nose_size": 0.55, &"nose_width": 0.45, &"brow_ridge": 0.55,
			&"cheek_full": 0.25, &"ear_size": 0.15, &"neck_width": 0.5, &"forehead_height": -0.2},
		Color.WHITE, 0.95)
	_race(&"orc", "Orc", 50.0, 16, 1.4, 1.3,
		{&"might": 3, &"wits": -1},
		{&"farming": 0.9, &"craft": 0.8, &"mining": 1.3},
		[&"human"],
		["Agra", "Burza", "Dura", "Ghora", "Krasha", "Mogra", "Nagra", "Shara", "Urza", "Zagra"],
		["Azhuk", "Borgul", "Drokh", "Ghazrak", "Krull", "Morgash", "Nazgrim", "Rokhan", "Uzgul", "Zarok"],
		{&"caucasian": 1.0},
		{&"jaw_bones": 0.9, &"chin_width": 0.6, &"chin_forward": 0.5, &"brow_ridge": 0.9, &"nose_width": 0.8,
			&"nose_size": 0.3, &"ear_point": 0.7, &"ear_size": 0.45, &"cheekbones": 0.5, &"head_width": 0.3,
			&"mouth_width": 0.5, &"neck_width": 0.7},
		Color(0.56, 0.64, 0.46), 0.3)
	_race(&"elf", "Elf", 150.0, 30, 0.4, 0.8,
		{&"agility": 2, &"wits": 1, &"might": -1},
		{&"farming": 1.0, &"craft": 1.2, &"mining": 0.6},
		[&"human"],
		["Aelith", "Caelwen", "Elora", "Faelyn", "Ilyana", "Lirael", "Maelis", "Nimue", "Sylwen", "Thalia"],
		["Aerion", "Caelum", "Elorin", "Faelar", "Ithil", "Lorien", "Maelor", "Nerys", "Sylas", "Thalion"],
		{&"african": 1.0, &"asian": 1.0, &"caucasian": 1.0},
		{&"ear_point": 0.95, &"cheekbones": 0.35, &"eye_size": 0.2, &"eye_tilt": 0.45, &"jaw_bones": -0.35,
			&"chin_width": -0.35, &"nose_width": -0.25, &"head_fat": -0.35, &"brow_ridge": -0.2, &"neck_width": -0.2},
		Color.WHITE, 0.05)
	_race(&"merrow", "Merrow", 70.0, 16, 1.2, 0.9,
		{&"agility": 1, &"will": 1, &"might": -1},
		{&"farming": 1.2, &"craft": 1.0, &"mining": 0.5},
		[],
		["Ama", "Cirrel", "Eddra", "Isha", "Lurra", "Mira", "Nessa", "Oshe", "Thulla", "Wenna"],
		["Bresk", "Corrin", "Dulo", "Halm", "Iskar", "Morro", "Nemm", "Orl", "Sallo", "Tharg"],
		{&"asian": 0.5, &"caucasian": 1.0},
		{&"eye_size": 0.7, &"eye_spacing": 0.3, &"eye_open": 0.4, &"nose_size": -0.8, &"nose_depth": -0.7, &"nose_width": 0.3,
			&"nostrils": -0.6, &"mouth_width": -0.4, &"mouth_corners": 0.35, &"upper_lip": -0.2, &"lower_lip": 0.2, &"ear_size": -0.9,
			&"chin_forward": -0.5, &"chin_width": -0.4, &"chin_height": -0.3, &"jaw_bones": -0.5, &"cheek_full": 0.6, &"cheekbones": -0.3,
			&"neck_width": 0.3, &"head_fat": 0.3, &"forehead_height": -0.3, &"brow_ridge": -0.6},
		Color(0.52, 0.7, 0.74), 0.0,
		{&"water": 2.4, &"marsh": 2.0, &"desert": 0.9},
		{&"temperate": 1.1, &"tropical": 1.2, &"steppe": 0.8, &"ash": 0.6, &"desert": 0.5},
		[&"gills", &"fins", &"crest"],
		[&"bluegreen", &"lightblue", &"grey", &"green"], &"merrow")
	_race(&"kheth", "Kheth", 40.0, 12, 1.8, 0.7,
		{&"might": 1, &"will": 2, &"wits": -1},
		{&"farming": 1.0, &"craft": 1.1, &"mining": 1.4},
		[],
		["Kesh", "Ithri", "Saakh", "Tchira", "Vekka", "Zirri", "Khala", "Ressa", "Tikka", "Xeth"],
		["Akkat", "Drekk", "Ithrak", "Khezz", "Rakk", "Szekh", "Tchak", "Vorrik", "Xikk", "Zhet"],
		{&"asian": 1.0, &"caucasian": 1.0},
		{&"eye_size": 0.55, &"eye_tilt": 0.6, &"eye_spacing": 0.3, &"nose_size": -0.75, &"nose_width": -0.5, &"nostrils": -0.5,
			&"mouth_width": -0.35, &"upper_lip": -0.6, &"lower_lip": -0.5, &"chin_width": -0.6, &"chin_forward": 0.3,
			&"cheekbones": 0.8, &"cheek_full": -0.6, &"jaw_bones": 0.4, &"ear_size": -0.95, &"forehead_slope": 0.5, &"head_fat": -0.4},
		Color(0.8, 0.68, 0.48), 0.0,
		{&"hills": 1.3, &"water": 0.6, &"desert": 1.15},
		{&"desert": 2.6, &"ash": 2.4, &"steppe": 1.4, &"alpine": 0.8, &"north": 0.7, &"snow": 0.4},
		[&"antennae", &"mandibles", &"plates"],
		[&"brown", &"brownlight"], &"kheth")


func _trait(id: StringName, title: String, mods: Dictionary[StringName, int], heritable: float,
		fertility: float = 1.0, mortality: float = 1.0, opposites: Array[StringName] = []) -> void:
	var d: TraitDef = TraitDef.new()
	d.id = id
	d.display_name = title
	d.attribute_mods = mods
	d.heritable_chance = heritable
	d.fertility_mult = fertility
	d.mortality_mult = mortality
	d.opposites = opposites
	_save(d, "traits", id)


func _traits() -> void:
	_trait(&"strong", "Strong", {&"might": 2}, 0.35, 1.0, 1.0, [&"frail"])
	_trait(&"frail", "Frail", {&"might": -2}, 0.3, 0.9, 1.5, [&"strong", &"hardy"])
	_trait(&"hardy", "Hardy", {}, 0.35, 1.0, 0.7, [&"frail", &"sickly"])
	_trait(&"sickly", "Sickly", {}, 0.3, 0.8, 1.7, [&"hardy"])
	_trait(&"quick", "Quick", {&"agility": 2}, 0.3, 1.0, 1.0, [&"clumsy"])
	_trait(&"clumsy", "Clumsy", {&"agility": -2}, 0.25, 1.0, 1.0, [&"quick"])
	_trait(&"clever", "Clever", {&"wits": 2}, 0.35, 1.0, 1.0, [&"dull"])
	_trait(&"dull", "Dull", {&"wits": -2}, 0.3, 1.0, 1.0, [&"clever"])
	_trait(&"resolute", "Resolute", {&"will": 2}, 0.2, 1.0, 1.0, [&"craven"])
	_trait(&"craven", "Craven", {&"will": -2}, 0.2, 1.0, 1.0, [&"resolute"])
	_trait(&"fertile", "Fertile", {}, 0.4, 1.4, 1.0, [&"barren"])
	_trait(&"barren", "Barren", {}, 0.05, 0.1, 1.0, [&"fertile"])
	_trait(&"cruel", "Cruel", {&"will": 1}, 0.1, 1.0, 1.0, [&"merciful"])
	_trait(&"merciful", "Merciful", {}, 0.1, 1.0, 1.0, [&"cruel"])
	_trait(&"greedy", "Greedy", {&"wits": 1}, 0.1, 1.0, 1.0)


func _good(id: StringName, title: String, price: float, demand: float, food: bool = false) -> void:
	var d: GoodDef = GoodDef.new()
	d.id = id
	d.display_name = title
	d.base_price = price
	d.demand_per_100 = demand
	d.is_food = food
	_save(d, "goods", id)


func _goods() -> void:
	_good(&"grain", "Grain", 1.0, 16.0, true)
	_good(&"fish", "Fish", 1.4, 4.0, true)
	_good(&"ale", "Ale", 2.0, 4.0)
	_good(&"timber", "Timber", 1.5, 2.0)
	_good(&"stone", "Stone", 1.5, 1.0)
	_good(&"cloth", "Cloth", 3.0, 3.0)
	_good(&"iron_ore", "Iron Ore", 2.0, 0.0)
	_good(&"iron", "Iron", 5.0, 0.5)
	_good(&"weapons", "Weapons", 12.0, 0.3)
	_good(&"armor", "Armor", 18.0, 0.2)
	_good(&"saltpeter", "Saltpeter", 6.0, 0.0)
	_good(&"gunpowder", "Gunpowder", 16.0, 0.1)
	_good(&"luxuries", "Luxuries", 30.0, 0.1)
	_good(&"wool", "Wool", 2.0, 1.5)
	_good(&"salt", "Salt", 1.8, 2.0)
	_good(&"horses", "Horses", 25.0, 0.12)
	_good(&"wine", "Wine", 4.0, 1.2)
	_good(&"furs", "Furs", 8.0, 0.4)


func _building(id: StringName, title: String, cost: int, kind: StringName, labor: int, forced: bool,
		inputs: Dictionary[StringName, int], outputs: Dictionary[StringName, int], tech: StringName = &"", needs_land: StringName = &"") -> void:
	var d: BuildingDef = BuildingDef.new()
	d.id = id
	d.display_name = title
	d.build_cost = cost
	d.labor_kind = kind
	d.labor_demand = labor
	d.allows_forced = forced
	d.inputs = inputs
	d.outputs = outputs
	d.required_tech = tech
	d.needs_land = needs_land
	_save(d, "buildings", id)


func _buildings() -> void:
	_building(&"farm", "Farm", 200, &"farming", 100, true, {}, {&"grain": 100})
	_building(&"plantation", "Plantation", 500, &"farming", 300, true, {}, {&"grain": 330})
	_building(&"fishery", "Fishery", 200, &"farming", 50, false, {}, {&"fish": 45}, &"", &"water")
	_building(&"brewery", "Brewery", 250, &"craft", 30, false, {&"grain": 20}, {&"ale": 25})
	_building(&"lumber_camp", "Lumber Camp", 200, &"mining", 40, true, {}, {&"timber": 35}, &"", &"woods")
	_building(&"quarry", "Quarry", 250, &"mining", 60, true, {}, {&"stone": 40}, &"", &"hills")
	_building(&"weaver", "Weaver", 300, &"craft", 30, false, {}, {&"cloth": 20})
	_building(&"iron_mine", "Iron Mine", 400, &"mining", 80, true, {}, {&"iron_ore": 40}, &"", &"hills")
	_building(&"smelter", "Smelter", 400, &"craft", 30, true, {&"iron_ore": 20, &"timber": 5}, {&"iron": 12})
	_building(&"weaponsmith", "Weaponsmith", 400, &"craft", 20, false, {&"iron": 5, &"timber": 2}, {&"weapons": 8})
	_building(&"armorer", "Armorer", 500, &"craft", 20, false, {&"iron": 6, &"cloth": 2}, {&"armor": 6}, &"chainmail")
	_building(&"saltpeter_works", "Saltpeter Works", 500, &"mining", 50, true, {}, {&"saltpeter": 15}, &"saltpeter_refining")
	_building(&"powder_mill", "Powder Mill", 700, &"craft", 20, false, {&"saltpeter": 10, &"timber": 2}, {&"gunpowder": 10}, &"saltpeter_refining")
	_building(&"artisan_quarter", "Artisan Quarter", 800, &"craft", 30, false, {&"cloth": 3, &"iron": 1}, {&"luxuries": 5})
	# The work a town can be known for.
	_building(&"sheep_run", "Sheep Run", 200, &"farming", 40, true, {}, {&"wool": 30})
	_building(&"horse_ranch", "Horse Ranch", 400, &"farming", 40, false, {}, {&"horses": 3})
	_building(&"salt_works", "Salt Works", 250, &"mining", 40, true, {}, {&"salt": 30}, &"", &"water")
	_building(&"vineyard", "Vineyard", 300, &"farming", 50, true, {}, {&"wine": 18})
	_building(&"trapper_lodge", "Trapper's Lodge", 150, &"farming", 25, false, {}, {&"furs": 6}, &"", &"woods")
	_building(&"pearl_beds", "Pearl Beds", 300, &"farming", 30, true, {}, {&"luxuries": 2}, &"", &"water")


func _tech(id: StringName, title: String, cost: float, prereqs: Array[StringName], start: bool = false,
		gunpowder: bool = false) -> void:
	var d: TechDef = TechDef.new()
	d.id = id
	d.display_name = title
	d.cost = cost
	d.prerequisites = prereqs
	d.known_at_start = start
	d.is_gunpowder = gunpowder
	_save(d, "techs", id)


func _techs() -> void:
	_tech(&"chainmail", "Chainmail", 0.0, [], true)
	_tech(&"crossbow", "Crossbow", 60.0, [])
	_tech(&"blast_furnace", "Blast Furnace", 150.0, [])
	_tech(&"pike_drill", "Pike Drill", 180.0, [&"crossbow"])
	_tech(&"early_plate", "Early Plate", 220.0, [&"blast_furnace"])
	_tech(&"windlass", "Windlass Crossbow", 200.0, [&"crossbow", &"blast_furnace"])
	_tech(&"saltpeter_refining", "Saltpeter Refining", 300.0, [&"blast_furnace"], false, true)
	_tech(&"bombards", "Bombards", 420.0, [&"saltpeter_refining"], false, true)
	_tech(&"matchlock", "Matchlock", 550.0, [&"saltpeter_refining", &"windlass"], false, true)
	_tech(&"full_plate", "Full Plate", 450.0, [&"early_plate"])
	_tech(&"cannon", "Cannon", 700.0, [&"bombards"], false, true)
	_tech(&"pike_and_shot", "Pike and Shot", 800.0, [&"matchlock", &"pike_drill"], false, true)


func _culture(id: StringName, title: String, primary: StringName, standing: Dictionary[StringName, int],
		law: SimEnums.BondageLaw, hereditary: bool, mixed: SimEnums.MixedHeritageRule, tax: float, aggression: float,
		dynasties: Array[String], settlements: Array[String], factions: Array[String], male: Array[String] = [], female: Array[String] = [],
		faces: Dictionary[StringName, float] = {}) -> void:
	var d: CultureDef = CultureDef.new()
	d.id = id
	d.display_name = title
	d.primary_race = primary
	d.race_standing = standing
	d.bondage_law = law
	d.hereditary_bondage = hereditary
	d.mixed_heritage_rule = mixed
	d.tax_rate = tax
	d.aggression = aggression
	d.dynasty_names = dynasties
	d.settlement_names = settlements
	d.faction_names = factions
	d.names_male = male
	d.names_female = female
	d.face_lines = faces
	_save(d, "cultures", id)


func _cultures() -> void:
	_culture(&"hallowed", "Hallowed Marches", &"human",
		{&"human": 4, &"dwarf": 3, &"elf": 2, &"orc": 1, &"merrow": 1, &"kheth": 1},
		SimEnums.BondageLaw.DEBT, false, SimEnums.MixedHeritageRule.LOWEST, 0.12, 0.5,
		["Ashgrove", "Blackmere", "Corbin", "Dunmarch", "Harrowgate", "Ironwood", "Lorn", "Marwick", "Ravensholt", "Thorne", "Vane", "Wulfric"],
		["Harrowmere", "Cinderford", "Gallowfen", "Oxbridge", "Saltmarch", "Thornwick", "Greywater", "Ashby", "Wolfden", "Mirefield", "Dunholt", "Kingsrest"],
		["Hallowed March", "Kingdom of Vane", "Duchy of Lorn"], [], [], {&"african": 0.1, &"asian": 0.1, &"caucasian": 0.8})
	_culture(&"ashen", "Ashen Dominion", &"orc",
		{&"orc": 4, &"human": 0, &"elf": 0, &"dwarf": 1, &"merrow": 0, &"kheth": 1},
		SimEnums.BondageLaw.CHATTEL, true, SimEnums.MixedHeritageRule.LOWEST, 0.08, 0.85,
		["Bloodfang", "Skullrend", "Ashmaw", "Ironjaw", "Grimtusk", "Blackscar", "Warbrand", "Gorefist", "Cindermaw", "Doomhide", "Redspear", "Bonecrusher"],
		["Gorthul", "Ashkar", "Morgrim", "Skarn", "Urzakh", "Dreadhold", "Kragmaw", "Ghulmar", "Vorzakh", "Bonepit", "Nazkar", "Rotgate"],
		["Ashen Dominion", "Horde of Skarn", "Bloodfang Khanate"])
	_culture(&"freehold", "Free Holds", &"dwarf",
		{&"dwarf": 4, &"human": 3, &"elf": 3, &"orc": 2, &"merrow": 2, &"kheth": 2},
		SimEnums.BondageLaw.BANNED, false, SimEnums.MixedHeritageRule.DOMINANT, 0.1, 0.25,
		["Stonehammer", "Deepdelve", "Ironbeard", "Goldvein", "Oakenshield", "Rockhelm", "Anvilborn", "Coalbrand", "Greymantle", "Silverpick", "Thunderforge", "Barrowhand"],
		["Kharzad", "Stonewatch", "Deephollow", "Ironhall", "Grimforge", "Karaz", "Barrowdeep", "Highcairn", "Coldanvil", "Tunnelmouth", "Duskhold", "Emberdelve"],
		["Free Holds", "League of Ironhall", "Barrow Compact"])
	_culture(&"veiled", "Veiled Courts", &"elf",
		{&"elf": 4, &"human": 0, &"orc": 0, &"dwarf": 0, &"merrow": 0, &"kheth": 0},
		SimEnums.BondageLaw.CHATTEL, true, SimEnums.MixedHeritageRule.LOWEST, 0.15, 0.6,
		["Aelindar", "Caelthas", "Duskwhisper", "Evermoor", "Faelwyn", "Moonshade", "Nightbloom", "Silverthorn", "Thalassar", "Veilborn", "Withermere", "Ylvaris"],
		["Aelthas", "Duskmere", "Evenfall", "Moonveil", "Nightspire", "Silvanost", "Thornveil", "Vaelis", "Wither", "Ylmoor", "Palecourt", "Sablewood"],
		["Veiled Court", "Court of Dusk", "Moonveil Conclave"])
	_culture(&"rime", "Rimeholds", &"human",
		{&"dwarf": 3, &"elf": 1, &"human": 4, &"orc": 1, &"merrow": 1, &"kheth": 1},
		SimEnums.BondageLaw.CHATTEL, false, SimEnums.MixedHeritageRule.LOWEST, 0.08, 0.7,
		["Frostborn", "Ravenmark", "Ulfsson", "Coldbrand", "Whitefell", "Skaldi", "Isenhart", "Grimvald", "Stormcrow", "Wintermere", "Hrafnsson", "Bjornsted"],
		["Hrafnhold", "Skeldvik", "Vintra", "Kaldmark", "Frosthaven", "Isvik", "Hvitfell", "Snaerholm", "Jarnby", "Ulfstad", "Kaldvik", "Rimeholt"],
		["Jarldom of the Rime", "Hrafn Kingdom", "Frostmark"],
		["Hrafn", "Ulfgar", "Torvald", "Eirik", "Skuli", "Brand", "Ketil", "Asgrim", "Hakon", "Sigvard"],
		["Astrid", "Sigrun", "Hild", "Ragna", "Thora", "Ingrid", "Solveig", "Gudrun", "Yrsa", "Ylva"],
		{&"caucasian": 1.0})
	_culture(&"steppe", "Steppe Clans", &"human",
		{&"dwarf": 1, &"elf": 1, &"human": 4, &"orc": 2, &"merrow": 1, &"kheth": 1},
		SimEnums.BondageLaw.CHATTEL, false, SimEnums.MixedHeritageRule.LOWEST, 0.06, 0.8,
		["Skarnborn", "Bloodfang", "Redspear", "Windrider", "Greyhorse", "Ironstirrup", "Karaul", "Sunarrow", "Talkhan", "Dustmane", "Ninetails", "Wolfbanner"],
		["Skarn", "Urzakh", "Kragmaw", "Vorzakh", "Tolgar", "Orkhal", "Batuqan", "Kharsa", "Yurtgate", "Sarkhan", "Ongol", "Tengir"],
		["Horde of Skarn", "Khanate of Tolgar", "Windriders"],
		["Temur", "Arslan", "Batu", "Kaidu", "Orda", "Sartak", "Khasar", "Bori", "Toghan", "Jochi"],
		["Altani", "Sorga", "Khulan", "Oyuna", "Bortai", "Yesuin", "Chechen", "Saran", "Qara", "Tuya"],
		{&"asian": 0.8, &"caucasian": 0.2})
	_culture(&"sunborn", "Sunborn Thrones", &"human",
		{&"dwarf": 2, &"elf": 2, &"human": 4, &"orc": 1, &"merrow": 2, &"kheth": 1},
		SimEnums.BondageLaw.DEBT, false, SimEnums.MixedHeritageRule.LOWEST, 0.14, 0.5,
		["Zahrun", "Sunspear", "Qaresh", "Goldensand", "Tamar", "Dunewalker", "Brightveil", "Saffa", "Mirage", "Ashara", "Scarab", "Kestrel"],
		["Zahrun", "Tamarzi", "Qaresh", "Kesh", "Ilmaresh", "Alqarra", "Saffa", "Qasr Nadir", "Mirahd", "Sunwell", "Dunereach", "Amberdeep"],
		["Throne of Zahrun", "Satrapy of Ilmaresh", "Sun Court"],
		["Zahir", "Idris", "Kasim", "Rashid", "Tariq", "Amir", "Haddad", "Faris", "Nadir", "Saqr"],
		["Zahra", "Leyla", "Samira", "Nadia", "Amira", "Yasmin", "Rania", "Safiya", "Dalia", "Inas"],
		{&"african": 0.4, &"asian": 0.15, &"caucasian": 0.45})
	_culture(&"tidebound", "Tidebound League", &"human",
		{&"dwarf": 3, &"elf": 3, &"human": 4, &"orc": 2, &"merrow": 3, &"kheth": 2},
		SimEnums.BondageLaw.BANNED, false, SimEnums.MixedHeritageRule.DOMINANT, 0.12, 0.35,
		["Saltwind", "Coralbright", "Tidemark", "Greenmantle", "Pearlcrest", "Ironwake", "Mangrove", "Deepcurrent", "Jadeprow", "Stormsail", "Kelpbinder", "Sunreef"],
		["Calavar", "Maruva", "Ommoru", "Sethra", "Tavuna", "Coral Gate", "Greenreach", "Palmhaven", "Tidegate", "Orruva", "Saltpine", "Mangrove Hold"],
		["Tidebound League", "Free Ports of Calavar", "Jade Compact"],
		["Tavi", "Mako", "Ruan", "Ilo", "Kesi", "Varo", "Oru", "Talu", "Sefo", "Inar"],
		["Lani", "Mahra", "Suvi", "Ilea", "Nalu", "Teva", "Orsa", "Malu", "Kaia", "Seren"],
		{&"african": 0.5, &"asian": 0.3, &"caucasian": 0.2})
	_culture(&"reef", "Reef Kin", &"merrow",
		{&"merrow": 4, &"human": 2, &"dwarf": 2, &"elf": 2, &"orc": 1, &"kheth": 1},
		SimEnums.BondageLaw.DEBT, false, SimEnums.MixedHeritageRule.DOMINANT, 0.1, 0.45,
		["Deepcall", "Saltgill", "Brinemouth", "Kelpwarden", "Undertow", "Greyfin", "Shellback", "Tidecaller", "Pearleye", "Wrackborn", "Coldcurrent", "Drownhallow"],
		["Ulvasse", "Brinehold", "Skerrow", "Wrackmouth", "Deeping", "Gullhame", "Saltreach", "Kelpholm", "Thalm", "Shoalgate", "Mistskerry", "Pearlgrave"],
		["Drowned Crown", "Skerry Moot", "Brine Compact"])
	_culture(&"hive", "Hive of Kheth", &"kheth",
		{&"kheth": 4, &"orc": 1, &"dwarf": 1, &"human": 0, &"elf": 0, &"merrow": 0},
		SimEnums.BondageLaw.CHATTEL, true, SimEnums.MixedHeritageRule.DOMINANT, 0.16, 0.6,
		["Khetrak", "Szzarin", "Ithrakkan", "Tchekkar", "Vorrikhet", "Zhettik", "Akkathi", "Drekhiss", "Xikkhar", "Rakkesh", "Khalzith", "Sennek"],
		["Sunwell", "Ikthar", "Szekkra", "Moundmother", "Tchakka", "Vessekh", "Duneheart", "Khizzak", "Chitterdeep", "Ressakh", "Zirrath", "Broodhollow"],
		["Hive of Sunwell", "Brood of Ikthar", "The Long Swarm"])


func _part(id: StringName, title: String, parent: StringName, toughness: float, weight: float, sever: float, bleed: float, stump: float,
		capacities: Dictionary[StringName, float], vital: bool = false) -> void:
	var d: BodyPartDef = BodyPartDef.new()
	d.id = id
	d.display_name = title
	d.parent = parent
	d.toughness = toughness
	d.hit_weight = weight
	d.sever_at = sever
	d.bleed_rate = bleed
	d.stump_bleed = stump
	d.capacities = capacities
	d.vital = vital
	_save(d, "body_parts", id)


func _body_parts() -> void:
	_part(&"torso", "chest", &"", 70.0, 22.0, 0.0, 0.1, 0.0, {&"wind": 0.8}, true)
	_part(&"abdomen", "belly", &"torso", 55.0, 12.0, 0.0, 0.14, 0.0, {&"wind": 0.4}, true)
	_part(&"neck", "neck", &"torso", 28.0, 2.0, 1.0, 0.6, 0.0, {&"mind": 0.3, &"wind": 0.3}, true)
	_part(&"head", "head", &"neck", 42.0, 8.0, 0.0, 0.12, 0.0, {&"mind": 0.85}, true)
	for side: String in ["l", "r"]:
		var title: String = "left " if side == "l" else "right "
		var arm: StringName = StringName("left_arm" if side == "l" else "right_arm")
		var leg: StringName = StringName("left_leg" if side == "l" else "right_leg")
		_part(StringName("arm_" + side), title + "arm", &"torso", 45.0, 8.0, 1.0, 0.12, 0.5, {arm: 1.0})
		_part(StringName("forearm_" + side), title + "forearm", StringName("arm_" + side), 34.0, 8.0, 0.95, 0.09, 0.3, {arm: 1.0})
		_part(StringName("hand_" + side), title + "hand", StringName("forearm_" + side), 26.0, 4.0, 1.2, 0.06, 0.16, {arm: 1.0})
		_part(StringName("thigh_" + side), title + "thigh", &"abdomen", 55.0, 7.0, 1.1, 0.2, 0.8, {leg: 1.0})
		_part(StringName("shin_" + side), title + "shin", StringName("thigh_" + side), 40.0, 6.0, 0.9, 0.09, 0.35, {leg: 1.0})
		_part(StringName("foot_" + side), title + "foot", StringName("shin_" + side), 28.0, 2.0, 1.15, 0.05, 0.14, {leg: 0.9})


## The wardrobe lives in garment_content.gd, so it can be written again without touching the rest.
func _armours() -> void:
	GarmentContent.write_all()


## Every people's troop tree and the weapons they carry live in troop_content.gd. After the wardrobe, since troop kits
## name garments.
func _troops() -> void:
	TroopContent.write_all()
