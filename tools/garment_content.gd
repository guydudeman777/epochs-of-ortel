class_name GarmentContent
extends RefCounted
## The wardrobe as authored data: every GarmentDef, and what each kind of soldier wears. generate_content.gd calls
## this, and generate_garments.gd runs it alone. Re-running overwrites content/defs/armours and the troops' armour.
##
## The look each garment is drawn as must be one the garment build wrote (assets/models/garments_mh_manifest.json),
## and its hides bits are read from there.

const ROOT: String = "res://content/defs"
const MANIFEST: String = "res://assets/models/garments_mh_manifest.json"

const TRUNK: Array[StringName] = [&"torso", &"abdomen"]
const ARMS: Array[StringName] = [&"arm_l", &"arm_r", &"forearm_l", &"forearm_r"]
const UPPER_ARMS: Array[StringName] = [&"arm_l", &"arm_r"]
const THIGHS: Array[StringName] = [&"thigh_l", &"thigh_r"]
const SHINS: Array[StringName] = [&"shin_l", &"shin_r"]
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const HANDS: Array[StringName] = [&"hand_l", &"hand_r"]
const FOREARMS: Array[StringName] = [&"forearm_l", &"forearm_r"]
const HEAD: Array[StringName] = [&"head"]
const HEAD_NECK: Array[StringName] = [&"head", &"neck"]

## Dyes. Plain folk wear undyed or cheap colours; the rich wear dear ones.
const UNDYED: Array[Color] = [Color(0.72, 0.66, 0.54), Color(0.46, 0.43, 0.38), Color(0.37, 0.28, 0.19), Color(0.6, 0.55, 0.45)]
const PLAIN: Array[Color] = [Color(0.46, 0.43, 0.38), Color(0.37, 0.28, 0.19), Color(0.5, 0.22, 0.14), Color(0.26, 0.31, 0.42), Color(0.33, 0.38, 0.22), Color(0.6, 0.55, 0.45)]
const DEAR: Array[Color] = [Color(0.58, 0.06, 0.07), Color(0.08, 0.12, 0.36), Color(0.3, 0.08, 0.3), Color(0.06, 0.06, 0.07), Color(0.08, 0.26, 0.12), Color(0.72, 0.52, 0.1)]
const NORTH: Array[Color] = [Color(0.46, 0.45, 0.44), Color(0.24, 0.3, 0.42), Color(0.35, 0.27, 0.2), Color(0.62, 0.6, 0.55), Color(0.4, 0.14, 0.12)]
const STEPPE: Array[Color] = [Color(0.16, 0.26, 0.5), Color(0.55, 0.15, 0.1), Color(0.72, 0.56, 0.18), Color(0.8, 0.76, 0.66), Color(0.2, 0.36, 0.3)]
const DESERT: Array[Color] = [Color(0.86, 0.82, 0.72), Color(0.14, 0.18, 0.4), Color(0.75, 0.55, 0.22), Color(0.55, 0.12, 0.1), Color(0.62, 0.5, 0.36)]
const JUNGLE: Array[Color] = [Color(0.1, 0.46, 0.44), Color(0.72, 0.36, 0.1), Color(0.62, 0.12, 0.1), Color(0.78, 0.66, 0.18), Color(0.82, 0.76, 0.62)]
const ELVEN: Array[Color] = [Color(0.62, 0.66, 0.68), Color(0.18, 0.32, 0.24), Color(0.1, 0.14, 0.3), Color(0.82, 0.82, 0.8), Color(0.32, 0.28, 0.4)]
const ASHEN: Array[Color] = [Color(0.08, 0.07, 0.07), Color(0.4, 0.12, 0.06), Color(0.66, 0.6, 0.5), Color(0.3, 0.25, 0.2)]
const DEEP: Array[Color] = [Color(0.34, 0.24, 0.16), Color(0.4, 0.1, 0.08), Color(0.12, 0.24, 0.16), Color(0.32, 0.32, 0.34)]
## Underwear linen: coarse and grey for the poor, undyed for most, bleached white for the rich. The view wears it
## further the cheaper it is.
const COARSE_LINEN: Array[Color] = [Color(0.74, 0.71, 0.63), Color(0.68, 0.66, 0.6), Color(0.77, 0.72, 0.62)]
const LINEN: Array[Color] = [Color(0.86, 0.82, 0.72), Color(0.82, 0.79, 0.7), Color(0.84, 0.82, 0.76)]
const BLEACHED: Array[Color] = [Color(0.94, 0.92, 0.87), Color(0.95, 0.94, 0.9)]
const SEA: Array[Color] = [Color(0.16, 0.4, 0.38), Color(0.72, 0.42, 0.34), Color(0.62, 0.62, 0.52), Color(0.26, 0.3, 0.4)]

const KHETH_MANIFEST: String = "res://assets/models/kheth_gear_manifest.json"
## The merrow's own: sea colours, kelp and shell.
const REEF: Array[Color] = [Color(0.16, 0.4, 0.38), Color(0.1, 0.26, 0.3), Color(0.55, 0.5, 0.38), Color(0.42, 0.2, 0.22), Color(0.22, 0.32, 0.18)]
## The kheth hive's: ochre, rust and soot.
const HIVE: Array[Color] = [Color(0.55, 0.36, 0.14), Color(0.42, 0.14, 0.08), Color(0.12, 0.1, 0.08), Color(0.62, 0.55, 0.38)]

static var _manifest: Dictionary = {}
static var _kheth_manifest: Dictionary = {}


## Writes every garment. Troop kits are TroopContent's (tools/troop_content.gd), which writes whole troop defs; this
## never touches them, so running the wardrobe again cannot undo the troop trees.
static func write_all() -> void:
	write_garments()


## Writes only content/defs/armours. The troops are another lane's.
static func write_garments() -> void:
	for d: GarmentDef in garments():
		_save(d, "armours", d.id)


## The old soldiers' kits from before troop trees, for viewers that line them up. The troops themselves wear what
## TroopContent gives them.
static func troop_kits() -> Dictionary[StringName, Array]:
	return {
		&"rebel_militia": [&"braies", &"short_tunic", &"trousers", &"turnshoes", &"belt"],
		&"levy_spearman": [&"braies", &"shirt", &"gambeson", &"trousers", &"turnshoes", &"skullcap", &"belt"],
		&"archer": [&"braies", &"shirt", &"gambeson", &"trousers", &"boots", &"hood", &"belt", &"leather_gloves"],
		&"crossbowman": [&"braies", &"shirt", &"gambeson", &"trousers", &"boots", &"kettle_hat", &"belt"],
		&"man_at_arms": [&"braies", &"shirt", &"mail_hauberk", &"surcoat", &"trousers", &"boots", &"mail_coif", &"helmet", &"belt", &"leather_gloves"],
		&"plate_knight": [&"braies", &"shirt", &"plate_harness", &"hose", &"sabatons", &"gauntlets", &"mail_coif", &"sallet", &"belt"],
		&"pikeman": [&"braies", &"shirt", &"brigandine", &"hose", &"short_boots", &"kettle_hat", &"belt"],
		&"arquebusier": [&"braies", &"shirt", &"buff_coat", &"hose", &"tall_boots", &"morion", &"belt"],
		&"pike_and_shot": [&"braies", &"doublet", &"coat_of_plates", &"hose", &"tall_boots", &"cabasset", &"belt", &"leather_gloves"],
		&"bombard_crew": [&"braies", &"shirt", &"leather_armour", &"trousers", &"boots", &"cap", &"belt", &"leather_gloves"],
	}


static func garments() -> Array[GarmentDef]:
	var any: Array = []
	var out: Array[GarmentDef] = []
	# Underwear: plain linen, no protection, worn by everyone, under everything.
	out.append(_g(&"loincloth", "Loincloth", &"underwear_bottom", "loincloth", [], 0.0, 0.0, 0.0, 0.05, 0.1, 1, any, COARSE_LINEN))
	out.append(_g(&"drawers", "Drawers", &"underwear_bottom", "drawers", [], 0.0, 0.0, 0.0, 0.08, 0.15, 2, any, LINEN))
	out.append(_g(&"braies", "Braies", &"underwear_bottom", "braies", THIGHS, 0.01, 0.0, 0.01, 0.1, 0.3, 3, any, LINEN))
	out.append(_g(&"breast_band", "Breast band", &"underwear_top", "breastband", [&"torso"], 0.0, 0.0, 0.0, 0.05, 0.1, 1, any, COARSE_LINEN))
	out.append(_g(&"undershirt", "Undershirt", &"underwear_top", "undershirt", TRUNK + UPPER_ARMS, 0.01, 0.0, 0.01, 0.12, 0.2, 3, any, LINEN))
	out.append(_g(&"shift", "Shift", &"underwear_top", "shift", TRUNK + UPPER_ARMS + THIGHS, 0.01, 0.0, 0.01, 0.15, 0.3, 4, any, LINEN))
	out.append(_g(&"sark", "Sark", &"underwear_top", "sark", TRUNK + UPPER_ARMS + THIGHS, 0.01, 0.0, 0.01, 0.14, 0.25, 4, any, LINEN))
	out.append(_g(&"chemise", "Chemise", &"underwear_top", "chemise", TRUNK + UPPER_ARMS + THIGHS, 0.01, 0.0, 0.01, 0.15, 0.25, 30, any, BLEACHED))
	# Clothes worn next to the skin or the underwear.
	out.append(_g(&"shirt", "Shirt", &"shirt", "shirt", TRUNK + ARMS, 0.05, 0.03, 0.02, 0.2, 0.4, 5, any, UNDYED))
	out.append(_g(&"tunic", "Tunic", &"shirt", "tunic", TRUNK + ARMS + THIGHS, 0.07, 0.04, 0.04, 0.35, 0.8, 8, any, PLAIN))
	out.append(_g(&"short_tunic", "Short tunic", &"shirt", "tunic_short", TRUNK + UPPER_ARMS, 0.05, 0.03, 0.03, 0.25, 0.6, 6, any, PLAIN))
	out.append(_g(&"gown", "Gown", &"shirt", "gown", TRUNK + ARMS + THIGHS + SHINS, 0.06, 0.04, 0.04, 0.4, 1.2, 10, any, PLAIN))
	out.append(_g(&"fine_gown", "Fine gown", &"shirt", "fine_gown", TRUNK + ARMS + THIGHS + SHINS, 0.05, 0.03, 0.03, 0.45, 1.0, 60, any, DEAR))
	out.append(_g(&"doublet", "Doublet", &"shirt", "doublet", TRUNK + ARMS, 0.14, 0.09, 0.1, 0.4, 1.2, 30, any, DEAR + PLAIN))
	out.append(_g(&"trousers", "Trousers", &"trousers", "trousers", THIGHS + SHINS, 0.05, 0.03, 0.02, 0.3, 0.6, 5, any, UNDYED))
	out.append(_g(&"hose", "Hose", &"trousers", "hose", THIGHS + SHINS, 0.03, 0.02, 0.01, 0.2, 0.3, 8, any, PLAIN + DEAR))
	out.append(_g(&"skirt", "Skirt", &"trousers", "skirt", THIGHS + SHINS, 0.04, 0.02, 0.02, 0.3, 0.8, 6, any, PLAIN))
	out.append(_g(&"kilt", "Kilt", &"trousers", "kilt", THIGHS, 0.04, 0.02, 0.02, 0.15, 0.5, 4, any, JUNGLE + PLAIN))
	out.append(_g(&"fur_trousers", "Fur trousers", &"trousers", "fur_trousers", THIGHS + SHINS, 0.12, 0.06, 0.08, 0.6, 1.2, 12, [&"rime", &"steppe", &"ashen"], []))
	# Over everything else.
	out.append(_g(&"surcoat", "Surcoat", &"over", "surcoat", TRUNK + THIGHS, 0.03, 0.02, 0.01, 0.15, 0.8, 15, any, DEAR))
	out.append(_g(&"coat", "Coat", &"over", "coat", TRUNK + ARMS + THIGHS, 0.08, 0.05, 0.05, 0.6, 2.0, 14, any, PLAIN))
	out.append(_g(&"robe", "Robe", &"over", "robe", TRUNK + ARMS + THIGHS + SHINS, 0.06, 0.04, 0.04, 0.5, 1.8, 12, any, PLAIN))
	out.append(_g(&"fine_robe", "Fine robe", &"over", "fine_robe", TRUNK + ARMS + THIGHS + SHINS, 0.06, 0.04, 0.04, 0.5, 1.5, 70, any, DEAR))
	out.append(_g(&"kaftan", "Kaftan", &"over", "kaftan", TRUNK + ARMS + THIGHS + SHINS, 0.1, 0.06, 0.06, 0.5, 1.6, 40, [&"steppe", &"sunborn"], STEPPE + DESERT))
	out.append(_g(&"desert_wrap", "Desert wrap", &"over", "desert_wrap", TRUNK + ARMS + THIGHS + SHINS, 0.05, 0.03, 0.03, 0.25, 1.0, 6, [&"sunborn"], DESERT))
	out.append(_g(&"fur_coat", "Fur coat", &"over", "fur_coat", TRUNK + ARMS + THIGHS, 0.15, 0.08, 0.1, 1.0, 3.0, 25, [&"rime", &"steppe", &"ashen"], []))
	out.append(_g(&"jerkin", "Jerkin", &"over", "jerkin", TRUNK, 0.2, 0.12, 0.1, 0.3, 1.5, 12, any, []))
	# Feet.
	out.append(_g(&"sandals", "Sandals", &"feet", "sandals", FEET, 0.05, 0.03, 0.02, 0.0, 0.3, 2, any, []))
	out.append(_g(&"turnshoes", "Turnshoes", &"feet", "turnshoes", FEET, 0.1, 0.06, 0.05, 0.1, 0.4, 4, any, []))
	out.append(_g(&"short_boots", "Short boots", &"feet", "short_boots", FEET, 0.2, 0.12, 0.08, 0.2, 0.8, 8, any, []))
	out.append(_g(&"boots", "Boots", &"feet", "boots", FEET + SHINS, 0.3, 0.2, 0.12, 0.3, 1.2, 12, any, []))
	out.append(_g(&"tall_boots", "Tall boots", &"feet", "tall_boots", FEET + SHINS, 0.35, 0.22, 0.14, 0.35, 1.6, 20, any, []))
	out.append(_g(&"fur_boots", "Fur boots", &"feet", "fur_boots", FEET + SHINS, 0.3, 0.18, 0.15, 0.8, 1.6, 16, [&"rime", &"steppe", &"ashen", &"freehold"], []))
	out.append(_g(&"sabatons", "Sabatons", &"feet", "sabatons", FEET, 0.85, 0.65, 0.35, 0.05, 1.2, 40, any, [], &"full_plate"))
	# Hands.
	out.append(_g(&"cloth_gloves", "Cloth gloves", &"hands", "gloves", HANDS, 0.03, 0.02, 0.02, 0.2, 0.1, 4, any, PLAIN))
	out.append(_g(&"leather_gloves", "Leather gloves", &"hands", "leather_gloves", HANDS, 0.15, 0.1, 0.05, 0.2, 0.2, 6, any, []))
	out.append(_g(&"fur_mitts", "Fur mitts", &"hands", "fur_mitts", HANDS, 0.1, 0.05, 0.08, 0.6, 0.3, 8, [&"rime", &"steppe", &"ashen", &"freehold"], []))
	out.append(_g(&"mail_mittens", "Mail mittens", &"hands", "mail_mittens", HANDS, 0.7, 0.35, 0.1, 0.05, 0.6, 25, any, [], &"chainmail"))
	out.append(_g(&"gauntlets", "Gauntlets", &"hands", "gauntlets", HANDS + FOREARMS, 0.88, 0.7, 0.38, 0.05, 1.2, 45, any, [], &"early_plate"))
	# Hats and hoods.
	out.append(_g(&"hood", "Hood", &"head", "hood", HEAD_NECK, 0.03, 0.02, 0.02, 0.3, 0.3, 4, any, PLAIN))
	out.append(_g(&"cap", "Cap", &"head", "cap", HEAD, 0.02, 0.01, 0.02, 0.1, 0.1, 2, any, PLAIN))
	out.append(_g(&"felt_hat", "Felt hat", &"head", "felt_hat", HEAD, 0.04, 0.02, 0.04, 0.2, 0.3, 6, any, PLAIN))
	out.append(_g(&"turban", "Turban", &"head", "turban", HEAD, 0.08, 0.04, 0.06, 0.2, 0.5, 8, [&"sunborn"], DESERT))
	out.append(_g(&"fur_hat", "Fur hat", &"head", "fur_hat", HEAD, 0.06, 0.03, 0.05, 0.6, 0.4, 10, [&"rime", &"steppe", &"ashen"], []))
	out.append(_g(&"straw_hat", "Straw hat", &"head", "straw_hat", HEAD, 0.02, 0.01, 0.02, 0.0, 0.2, 2, any, []))
	out.append(_g(&"veil", "Veil", &"head", "veil", HEAD_NECK, 0.02, 0.01, 0.01, 0.1, 0.2, 5, any, UNDYED + ELVEN))
	out.append(_g(&"circlet", "Circlet", &"head", "circlet", HEAD, 0.05, 0.02, 0.03, 0.0, 0.3, 120, any, []))
	out.append(_g(&"crown", "Crown", &"head", "crown", HEAD, 0.1, 0.05, 0.05, 0.05, 1.2, 400, any, DEAR))
	out.append(_g(&"mail_coif", "Mail coif", &"head", "mail_coif", HEAD_NECK, 0.72, 0.38, 0.1, 0.05, 1.5, 20, any, [], &"chainmail"))
	# Helmets, from the first iron caps to the gunpowder age.
	out.append(_g(&"skullcap", "Skullcap", &"head_armour", "skullcap", HEAD, 0.7, 0.5, 0.3, 0.05, 1.0, 12, any, []))
	out.append(_g(&"helmet", "Nasal helm", &"head_armour", "helm_nasal", HEAD, 0.8, 0.6, 0.35, 0.05, 1.5, 18, any, []))
	out.append(_g(&"kettle_hat", "Kettle hat", &"head_armour", "kettle_hat", HEAD, 0.8, 0.62, 0.35, 0.05, 1.8, 20, any, []))
	out.append(_g(&"bascinet", "Bascinet", &"head_armour", "bascinet", HEAD_NECK, 0.85, 0.7, 0.4, 0.05, 2.4, 35, any, [], &"early_plate"))
	out.append(_g(&"sallet", "Sallet", &"head_armour", "sallet", HEAD_NECK, 0.88, 0.72, 0.4, 0.05, 2.2, 45, any, [], &"full_plate"))
	out.append(_g(&"morion", "Morion", &"head_armour", "morion", HEAD, 0.85, 0.65, 0.35, 0.05, 2.0, 30, any, [], &"matchlock"))
	out.append(_g(&"cabasset", "Cabasset", &"head_armour", "cabasset", HEAD, 0.82, 0.62, 0.33, 0.05, 1.8, 28, any, [], &"matchlock"))
	# Body armour.
	out.append(_g(&"gambeson", "Gambeson", &"body_armour", "gambeson", TRUNK + ARMS, 0.5, 0.42, 0.35, 0.6, 3.0, 20, any, UNDYED))
	out.append(_g(&"leather_armour", "Leather armour", &"body_armour", "leather_armour", TRUNK, 0.4, 0.3, 0.2, 0.3, 4.0, 18, any, []))
	out.append(_g(&"brigandine", "Brigandine", &"body_armour", "brigandine", TRUNK + ARMS, 0.78, 0.6, 0.3, 0.3, 9.0, 60, any, DEAR, &"early_plate"))
	out.append(_g(&"lamellar", "Lamellar", &"body_armour", "lamellar", TRUNK + UPPER_ARMS + THIGHS, 0.7, 0.5, 0.25, 0.2, 10.0, 45, any, []))
	out.append(_g(&"scale", "Scale", &"body_armour", "scale", TRUNK + UPPER_ARMS + THIGHS, 0.68, 0.45, 0.2, 0.2, 11.0, 45, any, []))
	out.append(_g(&"mail_hauberk", "Mail hauberk", &"body_armour", "mail", TRUNK + ARMS + THIGHS, 0.72, 0.38, 0.12, 0.1, 12.0, 50, any, [], &"chainmail"))
	out.append(_g(&"coat_of_plates", "Coat of plates", &"body_armour", "coat_of_plates", TRUNK + ARMS + THIGHS, 0.8, 0.62, 0.3, 0.2, 14.0, 70, any, DEAR, &"early_plate"))
	out.append(_g(&"plate_harness", "Plate harness", &"body_armour", "plate", TRUNK + ARMS + THIGHS + SHINS + [&"neck"], 0.92, 0.72, 0.38, 0.1, 22.0, 160, any, [], &"full_plate"))
	out.append(_g(&"buff_coat", "Buff coat", &"body_armour", "buff_coat", TRUNK + ARMS + THIGHS, 0.45, 0.25, 0.3, 0.5, 5.0, 35, any, [], &"matchlock"))
	# Cloaks and belts.
	out.append(_g(&"cloak", "Cloak", &"cloak", "cloak", [&"torso"], 0.03, 0.02, 0.03, 0.5, 1.5, 8, any, PLAIN))
	out.append(_g(&"fine_cloak", "Fine cloak", &"cloak", "cloak", [&"torso"], 0.03, 0.02, 0.03, 0.55, 1.4, 50, any, DEAR))
	out.append(_g(&"fur_cloak", "Fur cloak", &"cloak", "fur_cloak", [&"torso"], 0.08, 0.04, 0.06, 1.0, 3.0, 30, [&"rime", &"steppe", &"ashen", &"freehold"], []))
	out.append(_g(&"belt", "Belt", &"belt", "belt", [], 0.0, 0.0, 0.0, 0.0, 0.3, 3, any, []))
	out.append(_g(&"sash", "Sash", &"belt", "sash", [], 0.0, 0.0, 0.0, 0.05, 0.2, 5, [&"sunborn", &"steppe", &"tidebound", &"reef", &"veiled"], DESERT + JUNGLE))
	# For soldiers rising in rank: a padded jack for the levy, short mail, a breastplate and half plate before the
	# full harness, mail for the legs, a spangenhelm, and a tabard to wear a lord's colours over it all.
	out.append(_g(&"padded_jack", "Padded jack", &"body_armour", "padded_jack", TRUNK + ARMS, 0.42, 0.36, 0.3, 0.5, 2.6, 12, any, UNDYED + PLAIN))
	out.append(_g(&"haubergeon", "Haubergeon", &"body_armour", "haubergeon", TRUNK + UPPER_ARMS + THIGHS, 0.68, 0.34, 0.1, 0.1, 9.0, 36, any, [], &"chainmail"))
	out.append(_g(&"breastplate", "Breastplate", &"body_armour", "breastplate", TRUNK + [&"neck"], 0.88, 0.7, 0.36, 0.05, 9.0, 58, any, [], &"early_plate"))
	out.append(_g(&"half_plate", "Half plate", &"body_armour", "half_plate", TRUNK + ARMS + THIGHS + [&"neck"], 0.9, 0.7, 0.37, 0.1, 17.0, 115, any, [], &"full_plate"))
	out.append(_g(&"mail_chausses", "Mail chausses", &"legs_armour", "mail_chausses", THIGHS + SHINS, 0.7, 0.36, 0.1, 0.1, 5.0, 26, any, [], &"chainmail"))
	out.append(_g(&"tabard", "Tabard", &"over", "tabard", TRUNK + THIGHS, 0.02, 0.01, 0.01, 0.1, 0.6, 10, any, PLAIN + DEAR))
	out.append(_g(&"spangenhelm", "Spangenhelm", &"head_armour", "spangenhelm", HEAD, 0.78, 0.58, 0.34, 0.05, 1.6, 16, any, []))
	out.append(_g(&"leather_cap", "Leather cap", &"head", "leather_cap", HEAD, 0.15, 0.08, 0.12, 0.1, 0.3, 4, any, []))
	# The merrow's own: a wrap of sea-dyed linen, a net over the shoulders strung with shells, kelp, a shell band.
	out.append(_r(_g(&"sea_wrap", "Sea wrap", &"trousers", "sea_wrap", THIGHS + SHINS, 0.03, 0.02, 0.02, 0.15, 0.5, 4, [&"reef"], REEF), &"merrow"))
	out.append(_r(_g(&"net_shawl", "Net shawl", &"over", "net_shawl", [&"torso"], 0.02, 0.01, 0.01, 0.05, 0.4, 9, [&"reef"], REEF), &"merrow"))
	out.append(_r(_g(&"kelp_sash", "Kelp sash", &"belt", "kelp_sash", [], 0.0, 0.0, 0.0, 0.0, 0.2, 3, [&"reef"], REEF), &"merrow"))
	out.append(_r(_g(&"reef_band", "Shell band", &"head", "reef_band", HEAD, 0.02, 0.01, 0.02, 0.0, 0.2, 24, [&"reef"], []), &"merrow"))
	# The kheth's own, hung on their shells: straps and a belt, a sash, leather bracers, bronze plates, a crest and
	# a mantle down the back.
	out.append(_r(_g(&"kheth_harness", "Shell harness", &"over", "kheth_harness", TRUNK, 0.05, 0.03, 0.03, 0.0, 0.8, 6, [&"hive"], []), &"kheth"))
	out.append(_r(_g(&"kheth_belt", "Hive belt", &"belt", "kheth_belt", [], 0.0, 0.0, 0.0, 0.0, 0.3, 3, [&"hive"], []), &"kheth"))
	out.append(_r(_g(&"kheth_sash", "Hive sash", &"underwear_bottom", "kheth_sash", [], 0.0, 0.0, 0.0, 0.05, 0.2, 4, [&"hive"], HIVE), &"kheth"))
	out.append(_r(_g(&"kheth_bracers", "Bracers", &"hands", "kheth_bracers", FOREARMS, 0.2, 0.12, 0.08, 0.0, 0.4, 7, [&"hive"], []), &"kheth"))
	out.append(_r(_g(&"kheth_plates", "Bronze plates", &"body_armour", "kheth_plates", TRUNK + UPPER_ARMS, 0.7, 0.5, 0.3, 0.0, 6.0, 40, [&"hive"], []), &"kheth"))
	out.append(_r(_g(&"kheth_crest", "Bronze crest", &"head_armour", "kheth_crest", HEAD, 0.7, 0.5, 0.3, 0.0, 1.2, 22, [&"hive"], []), &"kheth"))
	out.append(_r(_g(&"kheth_mantle", "Hive mantle", &"cloak", "kheth_mantle", [&"torso"], 0.03, 0.02, 0.02, 0.2, 1.0, 14, [&"hive"], HIVE), &"kheth"))
	return out


## Marks a garment as made for one race's body alone.
static func _r(d: GarmentDef, race: StringName) -> GarmentDef:
	d.race_ids.assign([race])
	return d


## covers and cultures hold StringNames, colors Colors. They come untyped, as sums of the lists above.
static func _g(id: StringName, title: String, slot: StringName, model: String, covers: Array, cut: float, pierce: float, crush: float,
		warmth: float, weight: float, value: int, cultures: Array, colors: Array, tech: StringName = &"") -> GarmentDef:
	var d: GarmentDef = GarmentDef.new()
	d.id = id
	d.display_name = title
	d.slot = slot
	d.layer = _layer_of(slot)
	d.model = model
	d.covers.assign(covers)
	if cut > 0.0 or pierce > 0.0 or crush > 0.0:
		d.stops = {&"cut": cut, &"pierce": pierce, &"crush": crush}
	d.warmth = warmth
	d.weight = weight
	d.value = value
	d.culture_ids.assign(cultures)
	d.tech_id = tech
	d.colors = PackedColorArray(colors)
	d.hides = _bits_of(model)
	return d


static func _layer_of(slot: StringName) -> int:
	match slot:
		&"underwear_top", &"underwear_bottom":
			return 0
		&"body_armour", &"head_armour", &"legs_armour":
			return 2
		&"over", &"belt":
			return 3
		&"cloak":
			return 4
	return 1


static func _bits_of(model: String) -> int:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
	var look: Dictionary = (_manifest["looks"] as Dictionary).get(model, {}) as Dictionary
	if look.is_empty():
		# The kheth's gear hangs on their shell and hides nothing.
		if _kheth_manifest.is_empty() and FileAccess.file_exists(KHETH_MANIFEST):
			_kheth_manifest = JSON.parse_string(FileAccess.get_file_as_string(KHETH_MANIFEST)) as Dictionary
		if (_kheth_manifest.get("looks", {}) as Dictionary).has(model):
			return 0
		push_error("no look %s in the garment build" % model)
		return 0
	var bits: int = 0
	for row: Variant in look["parts"] as Array:
		bits |= ((_manifest["parts"] as Dictionary).get((row as Array)[0], {}) as Dictionary).get("bits", 0) as int
	return bits


static func _save(res: Resource, folder: String, id: StringName) -> void:
	var dir: String = ROOT + "/" + folder
	DirAccess.make_dir_recursive_absolute(dir)
	var err: Error = ResourceSaver.save(res, dir + "/" + String(id) + ".tres")
	if err != OK:
		push_error("failed to save %s: %s" % [id, err])
