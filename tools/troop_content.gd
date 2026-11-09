class_name TroopContent
extends RefCounted
## Every people's troop tree and every weapon, as authored data. generate_content.gd calls this, and generate_troops.gd
## runs it alone. Re-running overwrites content/defs/troops and content/defs/weapons.
##
## Each people has a tree of the same shape (ROLES): a tier 1 levy that rises along the shield line, the shooters, the
## polearms, shock troops and, behind the gunpowder techs, the guns, each branch ending at tier 5. What each rank wears
## and carries is the people's own (STYLES, WEAPONS), from garment ids in content/defs/armours. The Marches' tree keeps
## the troop ids the game had before there were trees, so old saves still know their soldiers.

const ROOT: String = "res://content/defs"
const NO_GARMENT: StringName = &""

## Each place in a tree: tier, branch, what it rises to, tech, goods per recruit, strength, wage, hire cost,
## experience to rise and gold to rise.
const ROLES: Dictionary = {
	&"levy": [1, &"levy", [&"footman", &"bowman"], &"", {}, 1.0, 0.3, 4, 20, 6],
	&"footman": [2, &"line", [&"heavy", &"pikeman"], &"", {&"weapons": 1}, 1.6, 0.5, 10, 45, 14],
	&"bowman": [2, &"shot", [&"crossbowman"], &"", {}, 1.5, 0.5, 10, 45, 14],
	&"heavy": [3, &"line", [&"sergeant", &"shock"], &"chainmail", {&"weapons": 1}, 2.5, 0.9, 20, 90, 25],
	&"pikeman": [3, &"pole", [&"halberdier"], &"pike_drill", {&"weapons": 1}, 2.6, 0.8, 18, 90, 25],
	&"crossbowman": [3, &"shot", [&"arbalester", &"arquebusier", &"bombard"], &"crossbow", {&"weapons": 1}, 2.4, 0.8, 18, 90, 25],
	&"sergeant": [4, &"line", [&"knight"], &"chainmail", {&"weapons": 1, &"armor": 1}, 3.6, 1.4, 36, 160, 40],
	&"shock": [4, &"shock", [&"champion"], &"chainmail", {&"weapons": 1, &"armor": 1}, 3.7, 1.4, 36, 160, 40],
	&"halberdier": [4, &"pole", [&"pike_shot"], &"pike_drill", {&"weapons": 1, &"armor": 1}, 3.5, 1.3, 34, 160, 40],
	&"arbalester": [4, &"shot", [&"marksman"], &"windlass", {&"weapons": 1}, 3.3, 1.2, 32, 160, 40],
	&"arquebusier": [4, &"gun", [&"veteran_shot"], &"matchlock", {&"weapons": 1, &"gunpowder": 1}, 4.0, 1.2, 30, 160, 40],
	&"bombard": [4, &"guns", [&"cannoneer"], &"bombards", {&"iron": 2, &"gunpowder": 2}, 6.0, 2.6, 70, 160, 50],
	&"knight": [5, &"line", [], &"early_plate", {&"weapons": 1, &"armor": 1}, 5.0, 2.4, 60, 0, 0],
	&"champion": [5, &"shock", [], &"full_plate", {&"weapons": 1, &"armor": 2}, 5.4, 2.6, 66, 0, 0],
	&"pike_shot": [5, &"gun", [], &"pike_and_shot", {&"weapons": 1, &"gunpowder": 1}, 6.0, 1.8, 45, 0, 0],
	&"marksman": [5, &"shot", [], &"windlass", {&"weapons": 1, &"armor": 1}, 4.4, 1.7, 45, 0, 0],
	&"veteran_shot": [5, &"gun", [], &"matchlock", {&"weapons": 1, &"gunpowder": 1}, 5.2, 1.7, 45, 0, 0],
	&"cannoneer": [5, &"guns", [], &"cannon", {&"iron": 2, &"gunpowder": 2}, 8.0, 3.4, 100, 0, 0],
}
## The Marches' tree wears the old troop ids.
const OLD_IDS: Dictionary = {
	&"levy": &"levy_spearman", &"bowman": &"archer", &"heavy": &"man_at_arms", &"pikeman": &"pikeman", &"crossbowman": &"crossbowman",
	&"arquebusier": &"arquebusier", &"bombard": &"bombard_crew", &"knight": &"plate_knight", &"pike_shot": &"pike_and_shot",
}
const OLD_TREE: StringName = &"hallowed"
## What each place in a tree wears, as keys into a people's style. A key the style leaves empty adds nothing.
const ROLE_GEAR: Dictionary = {
	&"levy": ["under", "legs", "feet1", "belt", "levy_body", "levy_head"],
	&"footman": ["under", "legs", "feet2", "belt", "padded", "helm2", "hands2"],
	&"bowman": ["under", "legs", "feet2", "belt", "shot_body", "shot_head", "hands_shot"],
	&"heavy": ["under", "legs", "feet3", "belt", "mail", "coif", "helm3", "over", "hands3"],
	&"pikeman": ["under", "legs", "feet3", "belt", "pole_body", "pole_head", "hands3"],
	&"crossbowman": ["under", "legs", "feet3", "belt", "padded", "helm_shot", "hands_shot", "cloak3"],
	&"sergeant": ["under", "legs_rich", "feet4", "belt", "heavy4", "legs_armour", "coif", "helm4", "over", "hands4", "cloak4"],
	&"shock": ["under", "legs_rich", "feet4", "belt", "shock_body", "coif", "shock_head", "hands4", "shock_cloak"],
	&"halberdier": ["under", "legs_rich", "feet4", "belt", "heavy_pole", "coif", "helm4", "hands3", "over_pole"],
	&"arbalester": ["under", "legs", "feet4", "belt", "pole_body", "helm_shot", "hands_shot", "cloak3"],
	&"arquebusier": ["under_gun", "legs_rich", "feet_gun", "belt", "gunner", "gun_helm", "hands_shot"],
	&"bombard": ["under", "legs", "feet4", "belt", "heavy_shot", "helm_shot", "hands_shot", "cloak3"],
	&"knight": ["under", "legs_rich", "feet5", "belt", "plate", "legs_armour", "coif", "helm5", "hands5", "over5", "cloak5"],
	&"champion": ["under", "legs_rich", "feet5", "belt", "champion_body", "legs_armour", "coif", "helm5_alt", "hands5"],
	&"pike_shot": ["under_gun", "legs_rich", "feet_gun", "belt", "pike_body", "legs_armour", "coif", "pike_helm", "hands5", "over_pole"],
	&"marksman": ["under", "legs_rich", "feet_gun", "belt", "heavy_shot", "helm4", "hands_shot", "cloak5"],
	&"veteran_shot": ["under_gun", "legs_rich", "feet_gun", "belt", "gunner", "coif", "gun_helm", "hands4"],
	&"cannoneer": ["under", "legs_rich", "feet_gun", "belt", "heavy_shot", "gun_helm", "hands_shot", "cloak5"],
}
## The Marches' way, which every other people's style changes in places.
const BASE_STYLE: Dictionary = {
	"under": [&"braies", &"shirt"], "under_gun": [&"braies", &"doublet"], "legs": &"trousers", "legs_rich": &"hose",
	"feet1": &"turnshoes", "feet2": &"short_boots", "feet3": &"boots", "feet4": &"boots", "feet5": &"sabatons", "feet_gun": &"tall_boots",
	"belt": &"belt", "levy_body": &"", "levy_head": &"leather_cap",
	"padded": &"gambeson", "light": &"leather_armour", "shot_body": &"padded_jack", "pole_body": &"brigandine", "mail": &"haubergeon",
	"heavy4": &"mail_hauberk", "shock_body": &"coat_of_plates", "heavy_pole": &"coat_of_plates", "heavy_shot": &"brigandine",
	"gunner": &"buff_coat", "plate": &"plate_harness", "champion_body": &"half_plate", "pike_body": &"breastplate",
	"legs_armour": &"mail_chausses",
	"coif": &"mail_coif", "helm2": &"helmet", "helm3": &"helmet", "helm4": &"bascinet", "helm5": &"sallet", "helm5_alt": &"bascinet",
	"helm_shot": &"kettle_hat", "shot_head": &"hood", "pole_head": &"kettle_hat", "shock_head": &"bascinet", "gun_helm": &"morion",
	"pike_helm": &"cabasset", "cap": &"cap", "gun_cap": &"felt_hat",
	"hands2": &"", "hands3": &"leather_gloves", "hands4": &"mail_mittens", "hands5": &"gauntlets", "hands_shot": &"leather_gloves",
	"over": &"tabard", "over5": &"surcoat", "over_pole": &"tabard", "cloak3": &"", "cloak4": &"", "cloak5": &"", "shock_cloak": &"",
}
## How each people's soldiers differ from the Marches'.
const STYLES: Dictionary = {
	&"hallowed": {},
	# Fur over mail, spangenhelms and round shields.
	&"rime": {
		"legs_rich": &"fur_trousers", "feet2": &"fur_boots", "feet3": &"fur_boots", "feet5": &"boots", "feet_gun": &"boots",
		"levy_head": &"fur_hat", "shot_head": &"fur_hat", "helm2": &"spangenhelm", "helm3": &"spangenhelm", "helm4": &"helmet",
		"helm5": &"bascinet", "mail": &"haubergeon", "heavy4": &"mail_hauberk", "shock_body": &"mail_hauberk", "shock_head": &"spangenhelm",
		"shock_cloak": &"fur_cloak", "cloak3": &"fur_cloak", "cloak4": &"fur_cloak", "cloak5": &"fur_cloak", "over": &"", "over5": &"",
		"over_pole": &"", "hands2": &"fur_mitts", "heavy_pole": &"mail_hauberk", "pole_body": &"mail_hauberk", "feet4": &"fur_boots",
		"champion_body": &"plate_harness",
	},
	# Felt and lamellar, sashes, tall boots, pointed helms, and no plate till the last rank.
	&"steppe": {
		"belt": &"sash", "feet1": &"short_boots", "feet2": &"boots", "feet4": &"tall_boots", "feet5": &"tall_boots",
		"levy_head": &"felt_hat", "shot_body": &"kaftan", "shot_head": &"fur_hat", "mail": &"lamellar", "heavy4": &"lamellar",
		"shock_body": &"lamellar", "pole_body": &"lamellar", "heavy_pole": &"lamellar", "heavy_shot": &"lamellar", "plate": &"coat_of_plates",
		"champion_body": &"coat_of_plates", "pike_body": &"lamellar", "helm2": &"skullcap", "helm3": &"spangenhelm", "helm4": &"kettle_hat",
		"helm5": &"bascinet", "helm5_alt": &"spangenhelm", "shock_head": &"spangenhelm", "over": &"", "over5": &"", "over_pole": &"",
		"legs_rich": &"trousers", "cap": &"felt_hat", "gun_cap": &"fur_hat", "legs_armour": &"",
	},
	# Wraps and turbans over scale, sandals until the guard.
	&"sunborn": {
		"belt": &"sash", "legs_rich": &"trousers", "feet1": &"sandals", "feet2": &"sandals", "feet3": &"short_boots", "feet5": &"boots",
		"feet_gun": &"boots", "levy_body": &"desert_wrap", "levy_head": &"turban", "shot_body": &"desert_wrap", "shot_head": &"turban",
		"mail": &"scale", "heavy4": &"mail_hauberk", "shock_body": &"scale", "heavy_pole": &"scale", "heavy_shot": &"scale",
		"pole_body": &"gambeson", "plate": &"coat_of_plates", "champion_body": &"breastplate", "pike_body": &"scale", "helm2": &"skullcap",
		"helm4": &"kettle_hat", "helm5": &"bascinet", "over": &"", "over5": &"", "over_pole": &"", "cloak5": &"fine_cloak", "cap": &"turban",
		"gun_cap": &"turban",
	},
	# Light kit for the heat and the decks: kilts, jerkins, brigandines.
	&"tidebound": {
		"under": [&"braies", &"short_tunic"], "legs": &"kilt", "legs_rich": &"trousers", "belt": &"sash", "feet1": &"sandals",
		"feet2": &"sandals", "feet3": &"short_boots", "feet4": &"short_boots", "feet5": &"boots", "feet_gun": &"boots",
		"levy_head": &"straw_hat", "padded": &"padded_jack", "shot_body": &"jerkin", "shot_head": &"cap", "mail": &"brigandine",
		"pole_body": &"brigandine", "heavy_pole": &"brigandine", "heavy4": &"coat_of_plates", "helm2": &"skullcap", "helm3": &"kettle_hat",
		"helm4": &"kettle_hat", "helm5": &"morion", "over": &"", "over5": &"", "over_pole": &"", "hands4": &"leather_gloves",
		"legs_armour": &"", "champion_body": &"breastplate",
	},
	# Black iron and fur: lamellar early, plate for the warlord's chosen.
	&"ashen": {
		"under": [&"braies", &"short_tunic"], "levy_head": &"", "padded": &"leather_armour", "shot_body": &"leather_armour",
		"shot_head": &"leather_cap", "mail": &"lamellar", "heavy4": &"mail_hauberk", "shock_body": &"lamellar", "heavy_pole": &"lamellar",
		"helm2": &"skullcap", "helm4": &"kettle_hat", "helm5_alt": &"bascinet", "shock_head": &"helmet", "cloak3": &"fur_cloak",
		"cloak4": &"fur_cloak", "shock_cloak": &"fur_cloak", "over": &"", "over5": &"", "over_pole": &"", "feet1": &"turnshoes",
		"feet2": &"turnshoes", "champion_body": &"plate_harness",
	},
	# Heavy from the first rank, plate at the end.
	&"freehold": {
		"levy_body": &"padded_jack", "levy_head": &"skullcap", "padded": &"gambeson", "helm2": &"helmet", "mail": &"mail_hauberk",
		"helm3": &"kettle_hat", "hands3": &"mail_mittens", "pole_body": &"mail_hauberk", "heavy4": &"coat_of_plates", "shock_body": &"brigandine",
		"hands2": &"leather_gloves", "over": &"", "over5": &"", "over_pole": &"", "feet2": &"boots", "champion_body": &"plate_harness",
		"shot_body": &"gambeson",
	},
	# Fine cloth, scale and cloaks.
	&"veiled": {
		"levy_body": &"robe", "levy_head": &"hood", "shot_body": &"gambeson", "mail": &"scale", "heavy4": &"mail_hauberk", "shock_body": &"scale",
		"heavy_pole": &"scale", "heavy_shot": &"scale", "helm2": &"skullcap", "cloak3": &"cloak", "cloak4": &"fine_cloak",
		"cloak5": &"fine_cloak", "shock_cloak": &"fine_cloak", "over": &"", "over5": &"", "over_pole": &"", "pole_body": &"gambeson",
		"champion_body": &"half_plate", "pike_body": &"breastplate",
	},
	# Sea folk: their own sea wraps, kelp sashes and bands, scale like their own skin.
	&"reef": {
		"under": [&"braies", &"short_tunic"], "legs": &"sea_wrap", "legs_rich": &"sea_wrap", "belt": &"kelp_sash", "feet1": &"sandals",
		"feet2": &"sandals", "feet3": &"sandals", "feet4": &"short_boots", "feet5": &"boots", "feet_gun": &"short_boots",
		"levy_body": &"net_shawl", "levy_head": &"reef_band", "padded": &"padded_jack", "shot_body": &"", "shot_head": &"reef_band",
		"mail": &"scale", "heavy4": &"scale", "shock_body": &"scale", "pole_body": &"scale", "heavy_pole": &"scale",
		"heavy_shot": &"scale", "plate": &"coat_of_plates", "champion_body": &"coat_of_plates", "pike_body": &"scale", "helm2": &"skullcap",
		"helm4": &"kettle_hat", "helm5": &"bascinet", "over": &"", "over5": &"", "over_pole": &"", "legs_armour": &"",
	},
	# The kheth wear no cloth: harness, bracers and a crest over their own shells, and chitin plates for the guard.
	&"hive": {
		"under": [&"kheth_sash"], "under_gun": [&"kheth_sash"], "legs": &"", "legs_rich": &"", "feet1": &"", "feet2": &"", "feet3": &"",
		"feet4": &"", "feet5": &"", "feet_gun": &"", "belt": &"kheth_belt", "levy_head": &"", "padded": &"kheth_harness",
		"shot_body": &"kheth_harness", "mail": &"kheth_plates", "heavy4": &"kheth_plates", "shock_body": &"kheth_plates",
		"pole_body": &"kheth_harness", "heavy_pole": &"kheth_plates", "heavy_shot": &"kheth_plates", "gunner": &"kheth_harness",
		"plate": &"kheth_plates", "champion_body": &"kheth_plates", "pike_body": &"kheth_plates", "legs_armour": &"", "coif": &"kheth_mantle",
		"helm2": &"", "helm3": &"kheth_crest", "helm4": &"kheth_crest", "helm5": &"kheth_crest", "helm5_alt": &"kheth_crest",
		"helm_shot": &"", "shot_head": &"", "pole_head": &"", "shock_head": &"kheth_crest", "gun_helm": &"kheth_crest",
		"pike_helm": &"kheth_crest", "cap": &"", "gun_cap": &"", "hands2": &"", "hands3": &"kheth_bracers", "hands4": &"kheth_bracers",
		"hands5": &"kheth_bracers", "hands_shot": &"kheth_bracers", "over": &"", "over5": &"",
		"over_pole": &"kheth_harness", "cloak4": &"", "cloak5": &"", "shock_cloak": &"",
	},
}
## What each place in the Marches' tree carries. One is picked for each soldier.
const BASE_WEAPONS: Dictionary = {
	&"levy": [&"spear", &"billhook", &"pitchfork", &"hatchet", &"club", &"short_sword"],
	&"footman": [&"arming_sword", &"axe", &"mace"], &"bowman": [&"hatchet", &"short_sword", &"falchion"],
	&"heavy": [&"arming_sword", &"mace", &"falchion"], &"pikeman": [&"spear", &"billhook"], &"crossbowman": [&"short_sword", &"falchion"],
	&"sergeant": [&"arming_sword", &"mace"], &"shock": [&"war_hammer", &"axe", &"falchion"], &"halberdier": [&"halberd", &"glaive", &"billhook"],
	&"arbalester": [&"falchion", &"short_sword"], &"arquebusier": [&"short_sword", &"falchion"], &"bombard": [&"hatchet", &"club"],
	&"knight": [&"arming_sword", &"mace"], &"champion": [&"war_hammer", &"mace"], &"pike_shot": [&"spear", &"halberd"],
	&"marksman": [&"falchion", &"arming_sword"], &"veteran_shot": [&"arming_sword", &"falchion"], &"cannoneer": [&"hatchet", &"short_sword"],
}
const WEAPONS: Dictionary = {
	&"hallowed": {},
	&"rime": {
		&"levy": [&"spear", &"hatchet", &"axe", &"club", &"short_sword"], &"footman": [&"axe", &"arming_sword"], &"bowman": [&"hatchet", &"short_sword"],
		&"heavy": [&"axe", &"arming_sword"], &"sergeant": [&"axe", &"arming_sword"], &"shock": [&"axe", &"war_hammer"],
		&"halberdier": [&"glaive", &"halberd"], &"knight": [&"arming_sword", &"axe"], &"champion": [&"axe", &"war_hammer"],
	},
	&"steppe": {
		&"levy": [&"spear", &"club", &"hatchet", &"sabre", &"mace"], &"footman": [&"sabre", &"mace", &"axe"], &"bowman": [&"sabre", &"hatchet"],
		&"heavy": [&"sabre", &"mace"], &"pikeman": [&"spear", &"glaive"], &"crossbowman": [&"sabre", &"short_sword"], &"sergeant": [&"sabre", &"mace"],
		&"shock": [&"sabre", &"mace", &"war_hammer"], &"halberdier": [&"glaive"], &"arbalester": [&"sabre"], &"arquebusier": [&"sabre"],
		&"knight": [&"sabre", &"mace"], &"champion": [&"mace", &"sabre"], &"pike_shot": [&"spear", &"glaive"], &"marksman": [&"sabre"],
		&"veteran_shot": [&"sabre"],
	},
	&"sunborn": {
		&"levy": [&"spear", &"club", &"short_sword", &"hatchet", &"sickle_sword"], &"footman": [&"sabre", &"mace", &"falchion"],
		&"bowman": [&"club", &"short_sword", &"sickle_sword"], &"heavy": [&"sabre", &"mace"], &"pikeman": [&"spear", &"glaive"],
		&"crossbowman": [&"sabre", &"short_sword"], &"sergeant": [&"sabre", &"mace"], &"shock": [&"sabre", &"mace", &"falchion"],
		&"halberdier": [&"glaive", &"halberd"], &"knight": [&"sabre", &"mace"], &"champion": [&"mace", &"sabre", &"war_hammer"],
		&"marksman": [&"sabre"], &"veteran_shot": [&"sabre", &"falchion"],
	},
	&"tidebound": {
		&"levy": [&"spear", &"hatchet", &"club", &"short_sword", &"trident"], &"footman": [&"falchion", &"short_sword", &"axe"],
		&"bowman": [&"hatchet", &"short_sword"], &"heavy": [&"falchion", &"arming_sword"], &"pikeman": [&"spear", &"billhook", &"trident"],
		&"sergeant": [&"arming_sword", &"falchion"], &"shock": [&"falchion", &"axe", &"hatchet"], &"knight": [&"arming_sword", &"falchion"],
		&"champion": [&"falchion", &"war_hammer"],
	},
	&"ashen": {
		&"levy": [&"club", &"hatchet", &"spear", &"pick", &"axe"], &"footman": [&"axe", &"mace", &"club"], &"bowman": [&"hatchet", &"club"],
		&"heavy": [&"axe", &"mace"], &"crossbowman": [&"hatchet", &"falchion"], &"sergeant": [&"axe", &"mace"],
		&"shock": [&"axe", &"war_hammer", &"mace"], &"halberdier": [&"halberd", &"glaive"], &"knight": [&"axe", &"mace"],
		&"champion": [&"war_hammer", &"mace", &"axe"], &"bombard": [&"hatchet", &"club", &"pick"],
	},
	&"freehold": {
		&"levy": [&"pick", &"hatchet", &"spear", &"club", &"war_hammer"], &"footman": [&"axe", &"war_hammer", &"mace"],
		&"bowman": [&"hatchet", &"pick", &"short_sword"], &"heavy": [&"axe", &"war_hammer", &"pick"], &"pikeman": [&"spear", &"halberd"],
		&"crossbowman": [&"hatchet", &"short_sword"], &"sergeant": [&"axe", &"war_hammer"], &"shock": [&"pick", &"war_hammer", &"axe"],
		&"halberdier": [&"halberd"], &"knight": [&"war_hammer", &"axe"], &"champion": [&"war_hammer", &"pick"], &"cannoneer": [&"hatchet", &"pick"],
	},
	&"veiled": {
		&"levy": [&"spear", &"short_sword", &"sabre", &"glaive", &"club"], &"footman": [&"sabre", &"arming_sword"],
		&"bowman": [&"short_sword", &"sabre"], &"heavy": [&"sabre", &"arming_sword"], &"pikeman": [&"glaive", &"spear"],
		&"crossbowman": [&"short_sword", &"sabre"], &"sergeant": [&"arming_sword", &"sabre"], &"shock": [&"sabre", &"falchion"],
		&"halberdier": [&"glaive"], &"knight": [&"arming_sword", &"sabre"], &"champion": [&"sabre", &"falchion"], &"pike_shot": [&"glaive", &"spear"],
	},
	&"reef": {
		&"levy": [&"trident", &"club", &"hatchet", &"short_sword", &"spear"], &"footman": [&"short_sword", &"falchion", &"club"],
		&"bowman": [&"short_sword", &"hatchet"], &"heavy": [&"falchion", &"arming_sword"], &"pikeman": [&"trident", &"spear"],
		&"crossbowman": [&"short_sword"], &"sergeant": [&"falchion", &"arming_sword"], &"shock": [&"falchion", &"war_hammer", &"axe"],
		&"halberdier": [&"trident", &"glaive"], &"pike_shot": [&"trident", &"spear"], &"knight": [&"arming_sword", &"falchion"],
		&"champion": [&"war_hammer", &"falchion"],
	},
	&"hive": {
		&"levy": [&"sickle_sword", &"spear", &"club", &"pick"], &"footman": [&"sickle_sword", &"mace", &"axe"], &"bowman": [&"sickle_sword", &"club"],
		&"heavy": [&"sickle_sword", &"mace"], &"pikeman": [&"spear", &"glaive"], &"crossbowman": [&"sickle_sword"],
		&"sergeant": [&"sickle_sword", &"war_hammer"], &"shock": [&"sickle_sword", &"pick", &"axe"], &"halberdier": [&"glaive", &"halberd"],
		&"arbalester": [&"sickle_sword"], &"arquebusier": [&"sickle_sword"], &"knight": [&"sickle_sword", &"war_hammer"],
		&"champion": [&"sickle_sword", &"pick"], &"marksman": [&"sickle_sword"], &"veteran_shot": [&"sickle_sword"],
	},
}
## The shield line carries shields. Levies with one-handed weapons often do.
const SHIELDED: Array[StringName] = [&"footman", &"heavy", &"sergeant", &"knight"]
const LEVY_SHIELDS: float = 0.35
## Names in ROLES order, for each people.
const ROLE_ORDER: Array[StringName] = [
	&"levy", &"footman", &"bowman", &"heavy", &"pikeman", &"crossbowman", &"sergeant", &"shock", &"halberdier", &"arbalester",
	&"arquebusier", &"bombard", &"knight", &"champion", &"pike_shot", &"marksman", &"veteran_shot", &"cannoneer",
]
const NAMES: Dictionary = {
	&"hallowed": ["Marcher Levy", "Marcher Footman", "Marcher Bowman", "Man-at-Arms", "Pikeman", "Crossbowman", "Sergeant", "Foot Knight",
		"Halberdier", "Arbalester", "Arquebusier", "Bombard Crew", "Knight", "Plate Champion", "Pike and Shot Company", "Master Arbalester",
		"Veteran Arquebusier", "Cannoneer"],
	&"rime": ["Bondi Levy", "Shieldman", "Rime Hunter", "Huscarl", "Rime Spearwall", "Rime Crossbowman", "Hirdman", "Berserker",
		"Rime Glaiveman", "Rime Arbalester", "Rime Arquebusier", "Rime Bombard Crew", "Jarl's Huscarl", "Ulfhednar", "Rime Pike and Shot",
		"Rime Master Arbalester", "Rime Veteran Shot", "Rime Cannoneer"],
	&"steppe": ["Clan Levy", "Clan Warrior", "Steppe Archer", "Lamellar Guard", "Steppe Lancer", "Steppe Crossbowman", "Kheshig",
		"Steppe Raider", "Steppe Glaiveman", "Steppe Arbalester", "Steppe Arquebusier", "Steppe Bombard Crew", "Khan's Kheshig", "Bahadur",
		"Steppe Pike and Shot", "Steppe Master Arbalester", "Steppe Veteran Shot", "Steppe Cannoneer"],
	&"sunborn": ["Sun Levy", "Sun Spearman", "Sun Slinger", "Sun Guard", "Sun Pikeman", "Sun Crossbowman", "Throne Guard", "Mamluk",
		"Sun Glaiveman", "Sun Arbalester", "Sun Arquebusier", "Sun Bombard Crew", "Golden Guard", "Lion of the Throne", "Sun Pike and Shot",
		"Sun Master Arbalester", "Sun Veteran Shot", "Sun Cannoneer"],
	&"tidebound": ["Tide Levy", "Tide Marine", "Tide Bowman", "Tide Guard", "Tide Pikeman", "Tide Crossbowman", "League Sergeant",
		"Tide Boarder", "Tide Halberdier", "Tide Arbalester", "Tide Arquebusier", "Tide Bombard Crew", "League Knight", "Corsair Captain",
		"Tide Pike and Shot", "Tide Master Arbalester", "Tide Veteran Shot", "Tide Cannoneer"],
	&"ashen": ["Ashen Grunt", "Ashen Warrior", "Ashen Skirmisher", "Ironhide", "Ashen Spearwall", "Ashen Crossbowman", "Black Guard",
		"Bloodrager", "Ashen Reaver", "Ashen Arbalester", "Ashen Arquebusier", "Ashen Bombard Crew", "Warlord's Chosen", "Skullcrusher",
		"Ashen Pike and Shot", "Ashen Master Arbalester", "Ashen Veteran Shot", "Ashen Cannoneer"],
	&"freehold": ["Hold Militia", "Shieldbearer", "Hold Archer", "Ironbreaker", "Hold Pikeman", "Hold Crossbowman", "Hearthguard",
		"Longbeard", "Hold Halberdier", "Hold Arbalester", "Hold Arquebusier", "Hold Bombard Crew", "Ironclad", "Anvil Champion",
		"Hold Pike and Shot", "Hold Master Arbalester", "Hold Thunderer", "Hold Cannoneer"],
	&"veiled": ["Court Levy", "Court Warden", "Court Archer", "Moon Guard", "Court Spearman", "Court Crossbowman", "Veiled Sentinel",
		"Bladedancer", "Glaivemaster", "Court Arbalester", "Court Arquebusier", "Court Bombard Crew", "Dusk Knight", "Nightblade",
		"Court Pike and Shot", "Court Master Arbalester", "Court Veteran Shot", "Court Cannoneer"],
	&"reef": ["Reef Levy", "Shieldfin", "Reef Harpooner", "Brine Guard", "Reef Tridentman", "Reef Crossbowman", "Drowned Guard",
		"Reef Reaver", "Reef Glaiveman", "Reef Arbalester", "Reef Arquebusier", "Reef Bombard Crew", "Deep Knight", "Deepcaller",
		"Reef Pike and Shot", "Reef Master Arbalester", "Reef Veteran Shot", "Reef Cannoneer"],
	&"hive": ["Drone Levy", "Hive Warrior", "Hive Skirmisher", "Shellguard", "Hive Spearwall", "Hive Crossbowman", "Brood Guard", "Mantis",
		"Hive Glaiveman", "Hive Arbalester", "Hive Arquebusier", "Hive Bombard Crew", "Queen's Guard", "Mantis Lord", "Hive Pike and Shot",
		"Hive Master Arbalester", "Hive Veteran Shot", "Hive Cannoneer"],
}


static func write_all() -> void:
	for d: WeaponDef in weapons():
		_save(d, "weapons", d.id)
	for d: TroopDef in troops():
		_save(d, "troops", d.id)


## Every weapon: swing kind and power, thrust kind and power, reach, speed, look, and whether it is a polearm.
## Levies' tools are weaker than soldiers' arms, and long arms are slow.
static func weapons() -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	out.append(_weapon(&"arming_sword", "Arming sword", &"cut", 32.0, &"pierce", 28.0, 1.35, 1.0, "sword"))
	out.append(_weapon(&"axe", "War axe", &"cut", 40.0, &"crush", 10.0, 1.2, 0.85, "axe"))
	out.append(_weapon(&"mace", "Mace", &"crush", 36.0, &"crush", 10.0, 1.15, 0.9, "mace"))
	out.append(_weapon(&"spear", "Spear", &"cut", 16.0, &"pierce", 31.0, 2.0, 1.0, "spear", true))
	out.append(_weapon(&"hatchet", "Hatchet", &"cut", 33.0, &"crush", 8.0, 1.1, 1.2, "hatchet"))
	out.append(_weapon(&"club", "Club", &"crush", 30.0, &"crush", 8.0, 1.12, 1.12, "club"))
	out.append(_weapon(&"short_sword", "Short sword", &"cut", 26.0, &"pierce", 28.0, 1.05, 1.2, "short_sword"))
	out.append(_weapon(&"falchion", "Falchion", &"cut", 36.0, &"pierce", 18.0, 1.25, 0.95, "falchion"))
	out.append(_weapon(&"sabre", "Sabre", &"cut", 33.0, &"pierce", 16.0, 1.3, 1.1, "sabre"))
	out.append(_weapon(&"sickle_sword", "Sickle sword", &"cut", 34.0, &"pierce", 12.0, 1.2, 1.0, "sickle_sword"))
	out.append(_weapon(&"war_hammer", "War hammer", &"crush", 34.0, &"pierce", 24.0, 1.15, 0.95, "war_hammer"))
	out.append(_weapon(&"pick", "War pick", &"pierce", 34.0, &"crush", 10.0, 1.15, 0.9, "pick"))
	out.append(_weapon(&"pitchfork", "Pitchfork", &"crush", 10.0, &"pierce", 26.0, 1.85, 1.0, "pitchfork", true))
	out.append(_weapon(&"billhook", "Billhook", &"cut", 32.0, &"pierce", 20.0, 1.9, 0.92, "billhook", true))
	out.append(_weapon(&"glaive", "Glaive", &"cut", 38.0, &"pierce", 26.0, 2.1, 0.86, "glaive", true))
	out.append(_weapon(&"halberd", "Halberd", &"cut", 44.0, &"pierce", 32.0, 2.05, 0.8, "halberd", true))
	out.append(_weapon(&"trident", "Trident", &"crush", 12.0, &"pierce", 34.0, 1.95, 1.0, "trident", true))
	return out


static func _weapon(id: StringName, title: String, swing: StringName, swing_power: float, thrust: StringName, thrust_power: float,
		reach: float, speed: float, model: String, polearm: bool = false) -> WeaponDef:
	var d: WeaponDef = WeaponDef.new()
	d.id = id
	d.display_name = title
	d.swing_kind = swing
	d.swing_power = swing_power
	d.thrust_kind = thrust
	d.thrust_power = thrust_power
	d.reach = reach
	d.speed = speed
	d.model = model
	d.polearm = polearm
	return d


## Every people's tree, then the rebels, who belong to none.
static func troops() -> Array[TroopDef]:
	var out: Array[TroopDef] = []
	var cultures: Array[StringName] = []
	cultures.assign(STYLES.keys())
	for culture: StringName in cultures:
		for i: int in range(ROLE_ORDER.size()):
			out.append(_troop(culture, ROLE_ORDER[i], (NAMES[culture] as Array)[i] as String))
	out.append(_rebels())
	return out


static func troop_id(culture: StringName, role: StringName) -> StringName:
	if culture == OLD_TREE and OLD_IDS.has(role):
		return OLD_IDS[role] as StringName
	return StringName("%s_%s" % [culture, role])


static func _troop(culture: StringName, role: StringName, title: String) -> TroopDef:
	var spec: Array = ROLES[role] as Array
	var d: TroopDef = TroopDef.new()
	d.id = troop_id(culture, role)
	d.display_name = title
	d.culture_id = culture
	d.tier = spec[0] as int
	d.branch = spec[1] as StringName
	for next: Variant in spec[2] as Array:
		d.upgrades_to.append(troop_id(culture, next as StringName))
	d.required_tech = spec[3] as StringName
	var goods: Dictionary = spec[4] as Dictionary
	for good: Variant in goods:
		d.required_goods[good as StringName] = goods[good] as int
	d.strength = spec[5] as float
	d.wage = spec[6] as float
	d.recruit_cost = spec[7] as int
	d.upgrade_xp = spec[8] as int
	d.upgrade_cost = spec[9] as int
	d.weapon_choices.assign(_weapons_of(culture, role))
	d.weapon_id = d.weapon_choices[0]
	d.has_shield = SHIELDED.has(role)
	d.shield_share = LEVY_SHIELDS if role == &"levy" else 0.0
	d.armour_ids.assign(kit(culture, role))
	return d


static func _weapons_of(culture: StringName, role: StringName) -> Array:
	var own: Dictionary = WEAPONS.get(culture, {}) as Dictionary
	return own.get(role, BASE_WEAPONS[role]) as Array


## What one place in a people's tree wears, under and over.
static func kit(culture: StringName, role: StringName) -> Array[StringName]:
	var style: Dictionary = BASE_STYLE.duplicate()
	style.merge(STYLES.get(culture, {}) as Dictionary, true)
	var out: Array[StringName] = []
	for key: Variant in ROLE_GEAR[role] as Array:
		var value: Variant = style.get(key as String, NO_GARMENT)
		if value is Array:
			for id: Variant in value as Array:
				out.append(id as StringName)
		elif value as StringName != NO_GARMENT:
			out.append(value as StringName)
	return out


## Rebels belong to no tree and hire out to nobody: they rise up with what they have.
static func _rebels() -> TroopDef:
	var d: TroopDef = TroopDef.new()
	d.id = &"rebel_militia"
	d.display_name = "Rebel Militia"
	d.strength = 0.45
	d.wage = 0.0
	d.recruit_cost = 0
	d.tier = 1
	d.branch = &"levy"
	d.weapon_choices.assign([&"club", &"hatchet", &"pitchfork", &"axe", &"short_sword"])
	d.weapon_id = &"club"
	d.shield_share = 0.15
	d.armour_ids.assign([&"braies", &"short_tunic", &"trousers", &"turnshoes", &"belt"])
	return d


static func _save(res: Resource, folder: String, id: StringName) -> void:
	var dir: String = ROOT + "/" + folder
	DirAccess.make_dir_recursive_absolute(dir)
	var err: Error = ResourceSaver.save(res, dir + "/" + String(id) + ".tres")
	if err != OK:
		push_error("failed to save %s: %s" % [id, err])
