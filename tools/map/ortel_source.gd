class_name OrtelSource
extends RefCounted
## The map of Ortel as it is drawn: the coast, ranges, rivers, woods and every named place. Change things here and run
## tools/map/bake_land.gd. x runs east and y runs south, over a sheet 2000 by 1800. The north is cold and the south is hot.
## Humans are most of the world, in many peoples. Dwarves, elves and orcs are older and fewer, and hold the high, deep and
## burnt places.

const SIZE: Vector2 = Vector2(2000.0, 1800.0)

const COAST: Array[Vector2] = [
	Vector2(150, 260), Vector2(280, 170), Vector2(420, 120), Vector2(560, 140), Vector2(650, 200), Vector2(700, 300),
	Vector2(760, 190), Vector2(860, 110), Vector2(1050, 80), Vector2(1250, 90), Vector2(1450, 110), Vector2(1650, 150),
	Vector2(1800, 230), Vector2(1880, 350), Vector2(1860, 480), Vector2(1900, 600), Vector2(1870, 720), Vector2(1800, 800),
	Vector2(1730, 860), Vector2(1770, 950), Vector2(1860, 1020), Vector2(1940, 1150), Vector2(1950, 1300), Vector2(1880, 1420),
	Vector2(1760, 1450), Vector2(1660, 1380), Vector2(1600, 1300), Vector2(1500, 1320), Vector2(1400, 1370), Vector2(1250, 1390),
	Vector2(1100, 1420), Vector2(950, 1400), Vector2(800, 1430), Vector2(650, 1390), Vector2(500, 1400), Vector2(350, 1360),
	Vector2(230, 1260), Vector2(150, 1120), Vector2(110, 980), Vector2(150, 860), Vector2(270, 830), Vector2(390, 780),
	Vector2(270, 720), Vector2(150, 690), Vector2(100, 560), Vector2(110, 420),
]

## Each range: its line, how far it spreads, how high it stands.
const RANGES: Array = [
	# The Cairnspine, which splits the continent.
	[[Vector2(895, 240), Vector2(920, 330), Vector2(880, 500), Vector2(940, 680), Vector2(900, 850), Vector2(840, 980)], 70.0, 40.0],
	# The Whitecrowns, over the Northwold.
	[[Vector2(1340, 285), Vector2(1500, 300), Vector2(1650, 285)], 55.0, 38.0],
	# The Teeth, between the Marches and the steppe.
	[[Vector2(180, 900), Vector2(320, 915), Vector2(460, 900), Vector2(560, 940)], 38.0, 30.0],
	# The Wolfcrags.
	[[Vector2(380, 240), Vector2(500, 232)], 34.0, 27.0],
	# Mount Ghulmar.
	[[Vector2(1050, 1180), Vector2(1060, 1185)], 60.0, 52.0],
]

## Ways through the ranges: x, y, radius.
const PASSES: Array = [
	[900.0, 420.0, 78.0], # Kharzad Gate
	[920.0, 770.0, 80.0], # The Coldgap
	[1500.0, 300.0, 75.0], # Frostgate
]

## x, y, reach east and west, reach north and south, height.
const HILLS: Array = [
	[340.0, 340.0, 150.0, 100.0, 11.0], # The Vane moors
	[700.0, 165.0, 110.0, 45.0, 9.0],
	[1050.0, 1010.0, 260.0, 50.0, 14.0], # The rim of the Cinder Reach
	[380.0, 1240.0, 110.0, 50.0, 11.0], # The Skarn badlands
	[1660.0, 1185.0, 100.0, 55.0, 12.0], # The mesas of the Sahr
	[1880.0, 1240.0, 55.0, 90.0, 10.0],
	[1150.0, 330.0, 90.0, 40.0, 12.0],
	[1560.0, 200.0, 100.0, 40.0, 10.0],
]

## The line of each river from its source to the water it runs into, and its width at each end.
const RIVERS: Array = [
	[[Vector2(840, 610), Vector2(780, 590), Vector2(730, 620), Vector2(660, 660), Vector2(590, 660), Vector2(520, 650), Vector2(460, 700), Vector2(390, 780)], 3.0, 9.0], # The Greywater
	[[Vector2(520, 320), Vector2(570, 410), Vector2(630, 500), Vector2(640, 580), Vector2(655, 655)], 2.5, 5.0], # The Harrow
	[[Vector2(360, 290), Vector2(280, 370), Vector2(120, 400)], 2.5, 6.0], # The Wolfwater
	[[Vector2(1000, 440), Vector2(1100, 500), Vector2(1200, 560), Vector2(1230, 590)], 3.0, 6.0], # The Vael above the lake
	[[Vector2(1355, 610), Vector2(1480, 700), Vector2(1600, 720), Vector2(1810, 790)], 6.0, 9.0], # The Vael below the lake
	[[Vector2(1150, 300), Vector2(1120, 200), Vector2(1075, 75)], 2.5, 6.0], # The Rimewater
	[[Vector2(980, 1010), Vector2(950, 1120), Vector2(920, 1250), Vector2(905, 1430)], 2.5, 6.0], # The Morgh
	[[Vector2(620, 960), Vector2(520, 1050), Vector2(430, 1150), Vector2(400, 1380)], 2.5, 5.0], # The Skarnwash
	[[Vector2(1500, 950), Vector2(1480, 1100), Vector2(1450, 1250), Vector2(1430, 1380)], 3.0, 8.0], # The Sahr
	[[Vector2(1790, 1060), Vector2(1765, 1200), Vector2(1730, 1330), Vector2(1715, 1440)], 3.0, 7.0], # The Jadewater
]

## x, y, reach east and west, reach north and south.
const LAKES: Array = [
	[1290.0, 600.0, 75.0, 50.0], # Evenmere
	[560.0, 228.0, 26.0, 16.0], # The Tarn of Wolfden
	[1660.0, 1065.0, 24.0, 16.0], # The Well of Alqarra
	[1250.0, 330.0, 40.0, 25.0], # Mirrormere
]

## Shallows that can be waded: line, then width.
const SHOALS: Array = [
	[[Vector2(935, 1390), Vector2(915, 1470), Vector2(890, 1560)], 15.0], # The Wading Road, from the dead shore to the Skerries
	[[Vector2(990, 1640), Vector2(1060, 1655)], 12.0],
	[[Vector2(690, 1655), Vector2(760, 1640)], 12.0],
]

## Ground that stands up out of the sea on its own: x, y, reach, reach, height.
const ISLES: Array = [
	[870.0, 1620.0, 140.0, 70.0, 9.0], # Ulvasse, the great skerry
	[1135.0, 1660.0, 95.0, 55.0, 7.0],
	[620.0, 1660.0, 80.0, 45.0, 7.0],
]

## x, y, reach, reach, how thick from 0 to 1.
const WOODS: Array = [
	[1300.0, 640.0, 300.0, 280.0, 1.0], # The Sablewood
	[1340.0, 390.0, 380.0, 80.0, 0.85], # The Northwold
	[450.0, 345.0, 90.0, 50.0, 0.7], # Ravensholt
	[690.0, 430.0, 85.0, 70.0, 0.8], # Harrow Wood
	[700.0, 830.0, 85.0, 55.0, 0.8], # Gallowood
	[1000.0, 560.0, 60.0, 90.0, 0.75],
	[1820.0, 1230.0, 170.0, 230.0, 1.0], # The Verdant Reach
	[860.0, 250.0, 110.0, 40.0, 0.6],
	[1700.0, 280.0, 90.0, 50.0, 0.7],
]

const MARSHES: Array = [
	[260.0, 575.0, 90.0, 40.0], # Gallowfen
	[390.0, 870.0, 60.0, 28.0], # The Mirefield
	[1400.0, 1010.0, 70.0, 28.0], # The Reek
	[1650.0, 1350.0, 70.0, 28.0], # The mangroves
	[905.0, 1655.0, 40.0, 18.0], # The Weedmeres of Ulvasse
]

## x, y, reach, reach, LandDef.Biome. Later ones win where they overlap.
const BIOMES: Array = [
	[1000.0, 40.0, 1150.0, 220.0, 7],
	[1350.0, 360.0, 420.0, 140.0, 1],
	[230.0, 230.0, 200.0, 130.0, 1],
	[420.0, 1130.0, 330.0, 230.0, 2],
	[1520.0, 1130.0, 300.0, 230.0, 4],
	[1820.0, 1260.0, 190.0, 260.0, 5],
	[1050.0, 1150.0, 260.0, 200.0, 3],
	[900.0, 560.0, 90.0, 470.0, 6],
	[1500.0, 290.0, 220.0, 90.0, 6],
]

const REALMS: Array = [
	[&"hallowed_march", "Hallowed March", &"hallowed", "Thorne",
		"The old river kingdom, rich in grain and in debt. Its kings still call themselves heirs of all Ortel, and its courts hold more people to their debts than its walls hold to their oaths."],
	[&"vane", "Kingdom of Vane", &"hallowed", "Vane",
		"Moor lords and salt-traders who broke from the March three generations ago, and have been arguing about it since."],
	[&"rime", "Jarldom of the Rime", &"rime", "Hrafnsson",
		"The cold coast. Its jarls take thralls on their raids, and free them again in a few years, as their fathers did."],
	[&"free_holds", "Free Holds", &"freehold", "Stonehammer",
		"The last league of the dwarves, holding the passes of the Cairnspine. They allow no slave within their gates, and they charge toll on all else."],
	[&"veiled_court", "Veiled Court", &"veiled", "Moonshade",
		"The last court of the elves, in the Sablewood. It remembers when the wood reached both seas, and it holds its lesser peoples in bondage that outlasts their lives."],
	[&"ashen_dominion", "Ashen Dominion", &"ashen", "Cindermaw",
		"The orc khans who rule the ash under Mount Ghulmar. Little grows there, so what they need they take, and the people to work it too."],
	[&"skarn", "Horde of Skarn", &"steppe", "Bloodfang",
		"Steppe riders whose camps became towns only within living memory, and not all of them like it."],
	[&"zahrun", "Throne of Zahrun", &"sunborn", "Zahrun",
		"The river-kings of the Sahr. Every field in the desert is theirs, because every drop of water is."],
	[&"ilmaresh", "Satrapy of Ilmaresh", &"sunborn", "Saffa",
		"Merchant princes on the eastern sea, who owe Zahrun an old oath and pay it in excuses."],
	[&"tidebound", "Tidebound League", &"tidebound", "Saltwind",
		"Free ports in the green south, ruled by their captains' council. They will trade with anyone, and they buy no people."],
	[&"drowned_crown", "Drowned Crown", &"reef", "Deepcall",
		"The merrow of the Cinder Skerries, who came up out of the grey sea when the ash first fell on it. They hold their debtors to the nets, and they hold the Wading Road against the khans."],
	[&"sunwell_hive", "Hive of Sunwell", &"hive", "Khetrak",
		"The kheth, who built their mounds on the bones of a dead city where the sand meets the ash. They eat what the desert grows, and they breed the people they take into the brood's service for good."],
]

## Name, realm, x, y, tier (0 village, 1 town, 2 capital), trades, lore. Each realm's capital comes ahead of its other places.
const PLACES: Array = [
	["Harrowmere", &"hallowed_march", 600, 690, 2, [&"brewery", &"weaver", &"weaponsmith", &"armorer", &"fishery"],
		"Seat of the March, where the Harrow meets the Greywater. The debt courts sit here in the old king's hall."],
	["Greywater", &"hallowed_march", 470, 735, 1, [&"fishery", &"weaver", &"brewery"], "A grey port at the head of the Gulf of Salt, and the March's one door to the sea."],
	["Oxbridge", &"hallowed_march", 700, 665, 1, [&"fishery", &"brewery", &"weaver"], "Named for the long stone bridge, which every drover on the Greywater pays to cross."],
	["Ashby", &"hallowed_march", 560, 520, 0, [&"brewery", &"weaver"], "Grain country. It was burned twice in the Vane war, and the name stuck."],
	["Thornwick", &"hallowed_march", 740, 470, 1, [&"lumber_camp", &"smelter", &"weaver"], "Edge of Harrow Wood, where the charcoal burners sell to the dwarves."],
	["Cinderford", &"hallowed_march", 610, 800, 1, [&"weaponsmith", &"brewery", &"weaver"], "The last ford before the Bonegate. Its walls face south and are never quite finished."],
	["Kingsrest", &"hallowed_march", 740, 760, 0, [&"lumber_camp", &"weaver", &"brewery"], "A king died here on the way to a war he had already lost. His tomb draws pilgrims and pickpockets."],
	["Mirefield", &"hallowed_march", 440, 850, 0, [&"fishery", &"weaver"], "Peat and eels on the edge of the fen, under the shadow of the Teeth."],

	["Dunholt", &"vane", 400, 410, 2, [&"quarry", &"weaver", &"weaponsmith", &"lumber_camp"], "A black keep on the moor. The kings of Vane were crowned here in the rain, and consider it lucky."],
	["Saltmarch", &"vane", 245, 240, 1, [&"fishery", &"weaver", &"brewery"], "Salt pans and whalers. The richest town in Vane, and the first to say so."],
	["Wolfden", &"vane", 560, 290, 1, [&"fishery", &"iron_mine", &"smelter"], "A mining town under the Wolfcrags, on the dark Tarn."],
	["Gallowfen", &"vane", 300, 505, 0, [&"fishery", &"weaver"], "Fen folk who hang their dead in the alders, and their thieves beside them."],
	["Corbinstead", &"vane", 490, 425, 0, [&"lumber_camp", &"brewery"], "Border town. It has flown both banners, and keeps both in the same chest."],

	["Hrafnhold", &"rime", 1080, 205, 2, [&"fishery", &"weaponsmith", &"armorer", &"lumber_camp"], "The jarl's hall at the mouth of the Rimewater, roofed with upturned ships."],
	["Skeldvik", &"rime", 800, 210, 1, [&"fishery", &"iron_mine", &"smelter"], "A raiders' harbour under the north end of the Cairnspine."],
	["Vintra", &"rime", 1290, 135, 1, [&"fishery", &"brewery", &"weaver"], "Winter town. The sea freezes to its doorsteps for three months of the year."],
	["Kaldmark", &"rime", 1480, 185, 0, [&"quarry", &"iron_mine", &"brewery"], "Watches the road up to Frostgate, and the elves who sometimes come down it."],
	["Frosthaven", &"rime", 1720, 215, 0, [&"fishery", &"lumber_camp", &"weaver"], "The far east end of the Rime, where the pines meet the sea."],

	["Kharzad", &"free_holds", 900, 420, 2, [&"iron_mine", &"quarry", &"smelter", &"armorer", &"weaponsmith"], "The Gate itself: a hold cut through the Cairnspine, with one door to the west and one to the east. All who cross pay here."],
	["Ironhall", &"free_holds", 815, 320, 1, [&"iron_mine", &"smelter", &"weaponsmith", &"quarry"], "The oldest working delve, whose hammers are heard before it is seen."],
	["Stonewatch", &"free_holds", 1000, 330, 1, [&"quarry", &"lumber_camp", &"weaver"], "The eastern watch, looking out over the wood, with a long memory of what came out of it."],
	["Deephollow", &"free_holds", 815, 560, 0, [&"iron_mine", &"quarry", &"fishery"], "Where the Greywater comes out of the rock."],
	["Highcairn", &"free_holds", 1010, 665, 1, [&"quarry", &"iron_mine", &"lumber_camp", &"smelter"], "Cairns of the dwarven dead run for miles up the slope behind it."],
	["Coldanvil", &"free_holds", 830, 785, 0, [&"iron_mine", &"quarry", &"weaponsmith"], "The western mouth of the Coldgap, snowbound for a third of the year."],

	["Palecourt", &"veiled_court", 1290, 515, 2, [&"weaver", &"fishery", &"lumber_camp", &"armorer"], "The court of the veil, on the north shore of Evenmere. No one who was not born there has seen its inner gardens and left."],
	["Moonveil", &"veiled_court", 1110, 470, 1, [&"lumber_camp", &"weaver", &"fishery"], "Silver-barked halls on the upper Vael. They have not changed in a thousand years, and they do not plan to."],
	["Evenfall", &"veiled_court", 1500, 470, 1, [&"lumber_camp", &"weaver", &"brewery"], "Where the wood climbs towards the Whitecrowns, and the sun sets early behind them."],
	["Duskmere", &"veiled_court", 1420, 690, 1, [&"fishery", &"lumber_camp", &"weaver"], "A river town under the eaves, where the Court's barges meet its slave markets."],
	["Nightspire", &"veiled_court", 1140, 650, 0, [&"lumber_camp", &"weaver", &"smelter"], "One white tower among the black trees, watching the passes."],
	["Thornveil", &"veiled_court", 1330, 830, 0, [&"lumber_camp", &"weaponsmith"], "The southern hedge of the Sablewood, grown thick on purpose, with the ash beyond it."],

	["Gorthul", &"ashen_dominion", 980, 1110, 2, [&"quarry", &"weaponsmith", &"armorer", &"smelter", &"iron_mine"], "City of the khans, built of black stone on the shoulder of Ghulmar. The mountain has buried it twice, and it was dug out twice by others' hands."],
	["Ashkar", &"ashen_dominion", 1150, 1050, 1, [&"iron_mine", &"smelter", &"quarry"], "Slag heaps and slave pits, and the wealth of the Dominion."],
	["Morgrim", &"ashen_dominion", 940, 1340, 1, [&"fishery", &"brewery", &"weaver"], "A fishing town on the dead shore, and the only place in the Dominion with a smell other than smoke."],
	["Dreadhold", &"ashen_dominion", 1260, 950, 1, [&"lumber_camp", &"weaponsmith", &"smelter"], "A fortress raised against the wood. It burns the Sablewood's edge each year, and each year it grows back."],
	["Bonepit", &"ashen_dominion", 780, 1120, 0, [&"weaver", &"brewery"], "An old battlefield, mined for what it still holds."],

	["Skarn", &"skarn", 440, 1090, 2, [&"fishery", &"weaver", &"weaponsmith", &"armorer"], "Half a city and half a camp. The great tents still stand inside the new walls."],
	["Urzakh", &"skarn", 230, 980, 1, [&"quarry", &"iron_mine", &"weaver"], "Under the south face of the Teeth, where the horse-lords winter."],
	["Kragmaw", &"skarn", 640, 1060, 1, [&"smelter", &"weaver", &"brewery"], "Holds the south end of the Bonegate, and takes what passes."],
	["Vorzakh", &"skarn", 420, 1320, 0, [&"fishery", &"weaver", &"brewery"], "A raiders' harbour on the southern shore, in the lee of the badlands."],
	["Tolgar", &"skarn", 250, 1180, 0, [&"weaver", &"brewery"], "The great horse fair, which never quite ends."],

	["Zahrun", &"zahrun", 1505, 1180, 2, [&"fishery", &"weaver", &"brewery", &"weaponsmith", &"armorer"], "The Throne on the Sahr. Its canals water a hundred miles of fields that would otherwise be sand."],
	["Tamarzi", &"zahrun", 1530, 1010, 1, [&"fishery", &"weaver"], "Where the Sahr rises, and where the kings of Zahrun are buried in the cliffs."],
	["Qaresh", &"zahrun", 1390, 1290, 1, [&"fishery", &"weaver", &"brewery"], "The river port at the mouth of the Sahr, full of ships from the Tidebound south."],
	["Kesh", &"zahrun", 1300, 1215, 0, [&"smelter", &"weaver"], "Salt and glass, on the dry edge where the desert meets the ash."],

	["Ilmaresh", &"ilmaresh", 1700, 960, 2, [&"fishery", &"weaver", &"brewery", &"weaponsmith"], "A white city on the eastern sea, richer than its masters in Zahrun and careful not to show it."],
	["Alqarra", &"ilmaresh", 1650, 1110, 1, [&"fishery", &"weaver"], "An oasis town around a well so old that its first builders are not remembered."],
	["Saffa", &"ilmaresh", 1580, 860, 0, [&"weaver", &"brewery"], "Caravans gather here before the long road north into the elves' wood."],

	["Calavar", &"tidebound", 1820, 1180, 2, [&"fishery", &"lumber_camp", &"weaver", &"brewery"], "The council port of the League, half built on the river and half on the jungle."],
	["Maruva", &"tidebound", 1860, 1050, 1, [&"fishery", &"lumber_camp"], "Shipyards and pearl divers on the northern shore of the Verdant Reach."],
	["Ommoru", &"tidebound", 1895, 1340, 1, [&"fishery", &"lumber_camp", &"weaver"], "The southernmost town in Ortel, hot, green and in no hurry."],
	["Sethra", &"tidebound", 1700, 1320, 0, [&"fishery", &"lumber_camp"], "Stilt houses in the mangroves at the mouth of the Jadewater."],

	["The Old Ford", &"", 530, 770, 0, [], "A crossing that has had a town on it three times."],
	["Barrowdeep", &"", 1030, 900, 0, [], "A delve the dwarves walked out of, and will not speak of."],
	["Wither", &"", 1620, 560, 0, [], "A dead elven city, grown over. Nobody at court will say what happened to it."],
	["Vaelis", &"", 1570, 760, 0, [], "A fine river landing with no one in it."],
	["Ylmoor", &"", 1240, 380, 0, [], "Cold pine country by Mirrormere, with old standing stones."],
	["Nazkar", &"", 690, 960, 0, [], "Scorched ground in the throat of the Bonegate."],
	["Tunnelmouth", &"", 760, 280, 0, [], "A dressed stone arch in the cliff, blocked from the inside."],
	["Duskhold", &"", 1060, 525, 0, [], "A clearing that does not grow over, in the shade of the Cairnspine."],
	["Lorn", &"", 165, 420, 0, [], "The last of the old duchy, a chapel and a wall, looking at the Sundering Sea."],
	["Emberdelve", &"", 960, 950, 0, [], "Hot springs and bad air where the Coldgap comes down into the ash."],
	["Isvik", &"", 640, 240, 0, [], "A good harbour that the Rime and Vane have both burned."],
	["The Jade Steps", &"", 1760, 1390, 0, [], "Stairs cut into a jungle hill, leading to nothing anyone has found."],

	["Ulvasse", &"drowned_crown", 860, 1615, 2, [&"fishery", &"weaver", &"brewery", &"armorer"], "The Crown's seat on the great skerry, half under water at high tide. Its queens are crowned in the sea and dried off after."],
	["Wrackmouth", &"drowned_crown", 990, 1640, 1, [&"fishery", &"weaver"], "Drying racks and wreck-salvage. Half the timber in its halls came off ships that did not mean to stop."],
	["Skerrow", &"drowned_crown", 1195, 1650, 1, [&"fishery", &"brewery"], "The eastern skerry, where the ash drifts in deepest and the fishing is best."],
	["Gullhame", &"drowned_crown", 610, 1660, 0, [&"fishery"], "A rock full of birds and the merrow who eat their eggs."],

	["Sunwell", &"sunwell_hive", 1350, 1120, 2, [&"weaver", &"smelter", &"weaponsmith", &"brewery"], "A dry well with a city's worth of foundations around it, and the kheth mounds risen on top. The brood-mother has never been seen outside."],
	["Ikthar", &"sunwell_hive", 1420, 1045, 1, [&"weaver", &"brewery"], "Mounds along the dry edge of the Reek, humming day and night."],
	["Szekkra", &"sunwell_hive", 1265, 1095, 0, [&"smelter", &"weaver"], "The hive's door to the ash, where slag from Ashkar is traded for slaves going the other way."],
]

## The roads that are there on the first day, by place name.
const ROADS: Array = [
	["Harrowmere", "Greywater"], ["Harrowmere", "Oxbridge"], ["Harrowmere", "Ashby"], ["Harrowmere", "Cinderford"],
	["Oxbridge", "Kingsrest"], ["Oxbridge", "Thornwick"], ["Ashby", "Thornwick"], ["Greywater", "Mirefield"],
	["Cinderford", "Mirefield"], ["Cinderford", "Kingsrest"],
	["Dunholt", "Saltmarch"], ["Dunholt", "Wolfden"], ["Dunholt", "Gallowfen"], ["Dunholt", "Corbinstead"],
	["Wolfden", "Corbinstead"], ["Corbinstead", "Ashby"], ["Gallowfen", "Greywater"],
	["Hrafnhold", "Skeldvik"], ["Hrafnhold", "Vintra"], ["Vintra", "Kaldmark"], ["Kaldmark", "Frosthaven"],
	["Skeldvik", "Wolfden"], ["Skeldvik", "Ironhall"], ["Hrafnhold", "Stonewatch"],
	["Thornwick", "Ironhall"], ["Thornwick", "Deephollow"], ["Oxbridge", "Deephollow"], ["Kingsrest", "Coldanvil"],
	["Ironhall", "Kharzad"], ["Deephollow", "Kharzad"], ["Kharzad", "Stonewatch"], ["Deephollow", "Coldanvil"],
	["Coldanvil", "Highcairn"], ["Highcairn", "Nightspire"],
	["Stonewatch", "Moonveil"], ["Moonveil", "Palecourt"], ["Palecourt", "Evenfall"], ["Palecourt", "Duskmere"],
	["Evenfall", "Duskmere"], ["Moonveil", "Nightspire"], ["Nightspire", "Thornveil"], ["Duskmere", "Thornveil"],
	["Evenfall", "Kaldmark"],
	["Thornveil", "Dreadhold"], ["Dreadhold", "Ashkar"], ["Ashkar", "Gorthul"], ["Gorthul", "Morgrim"],
	["Gorthul", "Bonepit"], ["Morgrim", "Bonepit"], ["Coldanvil", "Bonepit"],
	["Skarn", "Urzakh"], ["Skarn", "Kragmaw"], ["Skarn", "Vorzakh"], ["Skarn", "Tolgar"], ["Urzakh", "Tolgar"],
	["Kragmaw", "Cinderford"], ["Kragmaw", "Bonepit"], ["Vorzakh", "Tolgar"],
	["Zahrun", "Tamarzi"], ["Zahrun", "Qaresh"], ["Zahrun", "Kesh"], ["Qaresh", "Kesh"], ["Kesh", "Ashkar"],
	["Ilmaresh", "Alqarra"], ["Ilmaresh", "Saffa"], ["Saffa", "Tamarzi"], ["Alqarra", "Zahrun"], ["Saffa", "Duskmere"],
	["Dreadhold", "Tamarzi"],
	["Calavar", "Maruva"], ["Calavar", "Ommoru"], ["Calavar", "Sethra"], ["Sethra", "Ommoru"], ["Maruva", "Ilmaresh"],
	["Calavar", "Alqarra"], ["Sethra", "Zahrun"],
	["Ulvasse", "Wrackmouth"], ["Wrackmouth", "Skerrow"], ["Ulvasse", "Gullhame"], ["Ulvasse", "Morgrim"],
	["Sunwell", "Ikthar"], ["Sunwell", "Szekkra"], ["Sunwell", "Kesh"], ["Szekkra", "Ashkar"], ["Ikthar", "Tamarzi"],
]

## Name, x, y, how large to write it, and what is said of it.
const LABELS: Array = [
	["The Sundering Sea", 45, 700, 1.7, "West of everything. Ships that go out on it are not expected back."],
	["The Gulf of Salt", 235, 765, 1.0, "The March's one way to the sea, and Vane's reason to want it."],
	["The Cold Reach", 1000, 35, 1.6, "Ice for half the year."],
	["The Sunward Sea", 1960, 700, 1.4, "Warm water and the ships of three peoples on it."],
	["The Sea of Cinders", 1300, 1520, 1.4, "Ash falls on it from Ghulmar, and floats."],
	["The Cairnspine", 900, 620, 1.5, "The wall down the middle of Ortel. There are two ways through, and both belong to the dwarves."],
	["The Whitecrowns", 1500, 255, 1.1, "Snow that never melts, and one pass under it."],
	["The Sablewood", 1280, 760, 1.6, "Once it touched both seas. It is still the largest thing in the world that is alive."],
	["The Northwold", 1350, 395, 1.1, "Cold pines between the Rime and the elves."],
	["The Rime", 1100, 130, 1.3, "The frozen north coast, and the people who live on it anyway."],
	["The Hallowed Marches", 560, 610, 1.3, "The grain lands of the Greywater, the first country anyone ever fought over."],
	["The Vane Moors", 330, 330, 1.1, "Wind, sheep and grudges."],
	["The Wolfcrags", 440, 200, 0.9, "Iron, and worse."],
	["The Skarn Steppe", 420, 1190, 1.3, "Grass to the horizon, and riders on it."],
	["The Teeth", 360, 885, 0.9, "No road crosses them."],
	["The Bonegate", 700, 930, 1.0, "The gap between the Teeth and the Cairnspine, which every southern army has come through."],
	["The Cinder Reach", 1000, 1260, 1.2, "Ash country under the mountain."],
	["Mount Ghulmar", 1055, 1150, 1.0, "The mountain that burns."],
	["Lake Evenmere", 1290, 600, 0.9, "Still, black and very deep."],
	["The Sahr Waste", 1520, 1080, 1.3, "Sand, except where the river is."],
	["The Verdant Reach", 1830, 1210, 1.2, "Jungle so thick the roads have to be cut again every year."],
	["Kharzad Gate", 900, 392, 0.8, "The northern pass of the Cairnspine."],
	["The Coldgap", 920, 742, 0.8, "The southern pass."],
	["Frostgate", 1500, 272, 0.8, "The pass under the Whitecrowns."],
	["The Cinder Skerries", 880, 1730, 1.1, "Grey rocks in a grey sea, and the merrow on them."],
	["The Wading Road", 960, 1490, 0.7, "Shallows from the dead shore to the Skerries. Waist deep at low tide, and nobody goes at high."],
]
