class_name OrtelSource
extends RefCounted
## The map of Ortel as it is drawn: the coast, the inner sea, ranges, rivers, woods and every named place. Change things
## here and run tools/map/bake_land.gd. x runs east and y runs south, over a sheet 4200 by 3200. The north is cold and
## the south is hot. The land is a ring round the Drowned Sea, which opens to the ocean only through the Narrows in the
## west. Humans are most of the world, in many peoples. Dwarves, elves and orcs are older and fewer, and hold the high,
## deep and burnt places; the merrow hold isles in the sea and the kheth a hive where the desert meets the ash.
##
## Places are cities (the seats, with walls and markets) and towns (the work places, each bound to the nearest city of its
## realm). A town's first trade is the work it is known for. The bake moves a place a little if the drawing put it in the
## water or on a peak, and pulls a fishing or salt town down to the shore.

const SIZE: Vector2 = Vector2(4200.0, 3200.0)

## The outer coast, round the whole land.
const COAST: Array[Vector2] = [
	Vector2(260, 520), Vector2(330, 360), Vector2(480, 250), Vector2(640, 190), Vector2(800, 230), Vector2(880, 320),
	Vector2(960, 220), Vector2(1150, 140), Vector2(1350, 110), Vector2(1560, 150), Vector2(1700, 240), Vector2(1830, 160),
	Vector2(2050, 100), Vector2(2300, 110), Vector2(2550, 140), Vector2(2750, 120), Vector2(2950, 170), Vector2(3150, 250),
	Vector2(3300, 220), Vector2(3500, 290), Vector2(3660, 410), Vector2(3790, 560), Vector2(3900, 720), Vector2(3860, 900),
	Vector2(3950, 1060), Vector2(4000, 1250), Vector2(3930, 1420), Vector2(3990, 1600), Vector2(3950, 1800), Vector2(3890, 1950),
	Vector2(3960, 2150), Vector2(4000, 2350), Vector2(3940, 2550), Vector2(3830, 2700), Vector2(3660, 2820), Vector2(3480, 2900),
	Vector2(3300, 2870), Vector2(3120, 2960), Vector2(2900, 3010), Vector2(2700, 2980), Vector2(2500, 3040), Vector2(2300, 3000),
	Vector2(2100, 3050), Vector2(1900, 2990), Vector2(1700, 3030), Vector2(1500, 2980), Vector2(1300, 3020), Vector2(1100, 2960),
	Vector2(900, 2990), Vector2(700, 2930), Vector2(520, 2850), Vector2(380, 2720), Vector2(260, 2560), Vector2(200, 2380),
	Vector2(240, 2200), Vector2(180, 2000), Vector2(230, 1850), Vector2(290, 1760), Vector2(230, 1640), Vector2(170, 1460),
	Vector2(220, 1260), Vector2(160, 1060), Vector2(200, 880), Vector2(170, 700),
]

## Seas inside the coast: the Drowned Sea, and the Narrows that join it to the ocean.
const SEAS: Array = [
	[
		Vector2(760, 1720), Vector2(820, 1640), Vector2(950, 1560), Vector2(1100, 1450), Vector2(1250, 1330),
		Vector2(1380, 1210), Vector2(1500, 1110), Vector2(1650, 1060), Vector2(1800, 1090), Vector2(1950, 1030),
		Vector2(2100, 980), Vector2(2250, 1000), Vector2(2400, 1060), Vector2(2550, 1020), Vector2(2700, 1060),
		Vector2(2850, 1130), Vector2(3000, 1180), Vector2(3150, 1250), Vector2(3280, 1360), Vector2(3350, 1500),
		Vector2(3330, 1650), Vector2(3250, 1800), Vector2(3150, 1950), Vector2(3020, 2080), Vector2(2850, 2150),
		Vector2(2700, 2120), Vector2(2550, 2180), Vector2(2400, 2250), Vector2(2250, 2300), Vector2(2100, 2280),
		Vector2(1950, 2220), Vector2(1800, 2160), Vector2(1650, 2120), Vector2(1500, 2060), Vector2(1350, 2000),
		Vector2(1200, 1950), Vector2(1050, 1900), Vector2(950, 1860), Vector2(850, 1800),
	],
	[
		Vector2(60, 1680), Vector2(300, 1670), Vector2(450, 1685), Vector2(600, 1670), Vector2(800, 1665),
		Vector2(830, 1780), Vector2(600, 1800), Vector2(450, 1810), Vector2(300, 1795), Vector2(60, 1800),
	],
]

## Each range: its line, how far it spreads, how high it stands.
const RANGES: Array = [
	# The Cairnspine, the dwarves' wall down the west.
	[[Vector2(600, 640), Vector2(640, 820), Vector2(590, 1000), Vector2(650, 1200), Vector2(620, 1380), Vector2(690, 1560)], 75.0, 40.0],
	# The Whitecrowns, between the Rime and the Northwold.
	[[Vector2(1830, 440), Vector2(2100, 400), Vector2(2400, 440), Vector2(2750, 410)], 60.0, 38.0],
	# The Wolfcrags of Vane.
	[[Vector2(380, 520), Vector2(500, 500)], 34.0, 27.0],
	# The Teeth, between the steppe and the Narrows.
	[[Vector2(450, 2060), Vector2(700, 2120), Vector2(900, 2080)], 40.0, 30.0],
	# Mount Ghulmar.
	[[Vector2(2050, 2620), Vector2(2060, 2625)], 70.0, 52.0],
	# The Greyfangs, between the elves and Ilmaresh.
	[[Vector2(3480, 1300), Vector2(3620, 1260), Vector2(3780, 1240)], 45.0, 30.0],
]

## Ways through the ranges: x, y, radius.
const PASSES: Array = [
	[600.0, 1000.0, 80.0], # Kharzad Gate
	[640.0, 1330.0, 75.0], # The Coldgap
	[2250.0, 420.0, 75.0], # Frostgate
	[3630.0, 1265.0, 60.0], # The Fang Pass
]

## x, y, reach east and west, reach north and south, height.
const HILLS: Array = [
	[380.0, 860.0, 160.0, 120.0, 11.0], # The Vane moors
	[480.0, 600.0, 90.0, 60.0, 10.0],
	[1350.0, 600.0, 160.0, 70.0, 9.0], # The March uplands
	[1250.0, 320.0, 120.0, 50.0, 10.0], # The Rime fells
	[2620.0, 300.0, 120.0, 50.0, 10.0],
	[2050.0, 2440.0, 300.0, 60.0, 14.0], # The rim of the Cinder Reach
	[600.0, 2700.0, 140.0, 70.0, 11.0], # The Skarn badlands
	[1270.0, 2580.0, 110.0, 55.0, 11.0], # Redcliff
	[3200.0, 2620.0, 130.0, 70.0, 12.0], # The mesas of the Sahr
	[2900.0, 2870.0, 110.0, 50.0, 10.0],
	[3550.0, 760.0, 120.0, 70.0, 10.0],
	[3800.0, 1650.0, 70.0, 110.0, 10.0],
	[3850.0, 2450.0, 60.0, 80.0, 10.0],
	[2450.0, 2520.0, 60.0, 40.0, 9.0],
	[2320.0, 2770.0, 70.0, 45.0, 10.0],
	[1720.0, 2700.0, 70.0, 50.0, 11.0],
	[820.0, 1290.0, 70.0, 60.0, 9.0],
	[3430.0, 900.0, 70.0, 50.0, 8.0],
]

## The line of each river from its source to the water it runs into, and its width at each end.
const RIVERS: Array = [
	[[Vector2(1650, 520), Vector2(1580, 700), Vector2(1520, 860), Vector2(1480, 1000), Vector2(1470, 1120)], 3.0, 9.0], # The Greywater
	[[Vector2(1050, 620), Vector2(1120, 780), Vector2(1200, 930), Vector2(1300, 1050), Vector2(1360, 1230)], 2.5, 6.0], # The Harrow
	[[Vector2(520, 720), Vector2(380, 770), Vector2(250, 820), Vector2(150, 860)], 2.5, 6.0], # The Wolfwater
	[[Vector2(1620, 430), Vector2(1580, 300), Vector2(1560, 120)], 2.5, 6.0], # The Rimewater
	[[Vector2(3450, 640), Vector2(3320, 740), Vector2(3200, 830)], 2.5, 5.0], # The Vael above the lake
	[[Vector2(3090, 890), Vector2(3010, 980), Vector2(2950, 1060), Vector2(2900, 1150)], 4.0, 9.0], # The Vael below the lake
	[[Vector2(3150, 2950), Vector2(3100, 2750), Vector2(3050, 2550), Vector2(3000, 2350), Vector2(2970, 2130)], 4.0, 10.0], # The Sahr
	[[Vector2(1950, 2500), Vector2(1900, 2350), Vector2(1880, 2180)], 2.5, 6.0], # The Morgh
	[[Vector2(900, 2700), Vector2(950, 2450), Vector2(1000, 2200), Vector2(1050, 1910)], 2.5, 6.0], # The Skarnwash
	[[Vector2(3600, 2300), Vector2(3650, 2500), Vector2(3700, 2700), Vector2(3720, 2830)], 3.0, 7.0], # The Jadewater
	[[Vector2(3750, 1900), Vector2(3600, 1800), Vector2(3420, 1720), Vector2(3320, 1700)], 2.5, 6.0], # The Ilm
]

## x, y, reach east and west, reach north and south.
const LAKES: Array = [
	[3150.0, 850.0, 90.0, 60.0], # Evenmere
	[570.0, 610.0, 30.0, 18.0], # The Tarn of Wolfden
	[3650.0, 1950.0, 28.0, 18.0], # The Well of Alqarra
	[2400.0, 620.0, 45.0, 28.0], # Mirrormere
	[3320.0, 2450.0, 20.0, 14.0], # The Sweetwater oasis
]

## Shallows that can be waded: line, then width.
const SHOALS: Array = [
	[[Vector2(2310, 2310), Vector2(2280, 2220), Vector2(2250, 2140)], 15.0], # The Wading Road, from the dead shore to Ulvasse
	[[Vector2(2500, 2000), Vector2(2560, 1975), Vector2(2610, 1955)], 10.0], # The causeway to Kelpholm
]

## Ground that stands up out of the sea on its own: x, y, reach, reach, height.
const ISLES: Array = [
	[2230.0, 2070.0, 150.0, 65.0, 9.0], # Ulvasse, the great skerry
	[2440.0, 2010.0, 80.0, 45.0, 7.0], # Skerrow
	[2030.0, 2025.0, 70.0, 40.0, 7.0], # Wrackmouth
	[2610.0, 1950.0, 70.0, 40.0, 7.0], # Kelpholm
	[2000.0, 1600.0, 110.0, 70.0, 10.0], # The Drowned Throne
	[2950.0, 1500.0, 90.0, 50.0, 8.0], # The Saltisles
	[1120.0, 1700.0, 60.0, 35.0, 7.0], # Gull Rock
	[1780.0, 1300.0, 70.0, 40.0, 7.0], # Kingfisher Isle
]

## x, y, reach, reach, how thick from 0 to 1.
const WOODS: Array = [
	[3150.0, 1000.0, 420.0, 330.0, 1.0], # The Sablewood
	[2500.0, 680.0, 380.0, 170.0, 0.85], # The Northwold
	[330.0, 700.0, 90.0, 60.0, 0.7], # Ravensholt
	[1100.0, 700.0, 110.0, 80.0, 0.8], # Harrow Wood
	[1050.0, 1250.0, 100.0, 70.0, 0.8], # Gallowood
	[1850.0, 800.0, 140.0, 90.0, 0.75], # The Kingswood
	[1000.0, 380.0, 150.0, 60.0, 0.6],
	[1430.0, 390.0, 110.0, 45.0, 0.6],
	[2420.0, 300.0, 120.0, 45.0, 0.6],
	[2850.0, 250.0, 120.0, 50.0, 0.6],
	[3700.0, 2550.0, 230.0, 300.0, 1.0], # The Verdant Reach
	[3580.0, 1470.0, 90.0, 60.0, 0.6], # The cedars of Ilm
	[1000.0, 2250.0, 60.0, 40.0, 0.5],
	[700.0, 1080.0, 60.0, 40.0, 0.5],
]

const MARSHES: Array = [
	[260.0, 1050.0, 80.0, 40.0], # Gallowfen
	[1250.0, 1280.0, 60.0, 30.0], # The Mirefield
	[1830.0, 2250.0, 60.0, 25.0], # The Reek
	[2940.0, 2210.0, 70.0, 30.0], # The Sahr delta
	[3600.0, 2780.0, 70.0, 28.0], # The mangroves
	[2280.0, 2085.0, 40.0, 18.0], # The Weedmeres of Ulvasse
]

## x, y, reach, reach, LandDef.Biome. Later ones win where they overlap.
const BIOMES: Array = [
	[1950.0, 420.0, 1500.0, 330.0, 1],
	[350.0, 520.0, 300.0, 260.0, 1],
	[2550.0, 720.0, 450.0, 250.0, 1],
	[2100.0, 40.0, 2300.0, 230.0, 7],
	[850.0, 2450.0, 760.0, 520.0, 2],
	[2950.0, 2550.0, 470.0, 470.0, 4],
	[3700.0, 1820.0, 260.0, 260.0, 4],
	[2050.0, 2650.0, 430.0, 400.0, 3],
	[2230.0, 2070.0, 260.0, 110.0, 3],
	[3700.0, 2650.0, 330.0, 380.0, 5],
	[640.0, 1120.0, 110.0, 520.0, 6],
	[2300.0, 420.0, 520.0, 90.0, 6],
]

const REALMS: Array = [
	[&"hallowed_march", "Hallowed March", &"hallowed", "Thorne",
		"The old river kingdom on the north shore of the Drowned Sea, rich in grain and in debt. Its kings still call themselves heirs of all Ortel, and its courts hold more people to their debts than its walls hold to their oaths."],
	[&"vane", "Kingdom of Vane", &"hallowed", "Vane",
		"Moor lords and salt-traders west of the Cairnspine, who broke from the March three generations ago, and have been arguing about it since."],
	[&"rime", "Jarldom of the Rime", &"rime", "Hrafnsson",
		"The cold north coast. Its jarls take thralls on their raids, and free them again in a few years, as their fathers did."],
	[&"free_holds", "Free Holds", &"freehold", "Stonehammer",
		"The last league of the dwarves, holding the passes of the Cairnspine and the cliffs over the Narrows. They allow no slave within their gates, and they charge toll on all else, ships included."],
	[&"veiled_court", "Veiled Court", &"veiled", "Moonshade",
		"The last court of the elves, in the Sablewood. It remembers when the wood reached both seas, and it holds its lesser peoples in bondage that outlasts their lives."],
	[&"ashen_dominion", "Ashen Dominion", &"ashen", "Cindermaw",
		"The orc khans who rule the ash under Mount Ghulmar. Little grows there, so what they need they take, and the people to work it too."],
	[&"skarn", "Horde of Skarn", &"steppe", "Bloodfang",
		"Steppe riders south of the Narrows, whose camps became towns only within living memory, and not all of them like it."],
	[&"zahrun", "Throne of Zahrun", &"sunborn", "Zahrun",
		"The river-kings of the Sahr. Every field in the desert is theirs, because every drop of water is."],
	[&"ilmaresh", "Satrapy of Ilmaresh", &"sunborn", "Saffa",
		"Merchant princes at the east end of the Drowned Sea, who owe Zahrun an old oath and pay it in excuses."],
	[&"tidebound", "Tidebound League", &"tidebound", "Saltwind",
		"Free ports in the green south-east, ruled by their captains' council. They will trade with anyone, and they buy no people."],
	[&"drowned_crown", "Drowned Crown", &"reef", "Deepcall",
		"The merrow of the Cinder Skerries, who came up out of the grey sea when the ash first fell on it. They hold their debtors to the nets, and they hold the Wading Road against the khans."],
	[&"sunwell_hive", "Hive of Sunwell", &"hive", "Khetrak",
		"The kheth, who built their mounds on the bones of a dead city where the sand meets the ash. They eat what the desert grows, and they breed the people they take into the brood's service for good."],
]

## Name, realm, x, y, tier (0 town, 1 city, 2 capital), trades, lore. Each realm's capital comes ahead of its other
## places. A town's first trade is the work it is known for, and it is bound to the nearest city of its realm.
const PLACES: Array = [
	["Harrowmere", &"hallowed_march", 1330, 1060, 2, [&"brewery", &"weaver", &"weaponsmith", &"armorer", &"smelter"],
		"Seat of the March, where the Harrow runs down to the sea. The debt courts sit here in the old king's hall."],
	["Greywater", &"hallowed_march", 1560, 1050, 1, [&"fishery", &"weaver", &"brewery", &"smelter"], "The grey port at the mouth of the Greywater, and the March's door to the Drowned Sea."],
	["Oxbridge", &"hallowed_march", 1150, 780, 1, [&"brewery", &"weaver", &"weaponsmith"], "Named for the long stone bridge, which every drover on the Harrow pays to cross."],
	["Thornwick", &"hallowed_march", 1750, 700, 1, [&"smelter", &"weaver", &"armorer"], "Edge of the Kingswood, where the charcoal burners sell to anyone with iron."],
	["Cinderford", &"hallowed_march", 1020, 1450, 1, [&"fishery", &"weaponsmith", &"brewery"], "A walled port on the west shore. Its walls face the sea and are never quite finished."],
	["Ashby", &"hallowed_march", 1210, 950, 0, [&"farm"], "Grain country. It was burned twice in the Vane war, and the name stuck."],
	["Kingsrest", &"hallowed_march", 1450, 950, 0, [&"farm"], "A king died here on the way to a war he had already lost. His tomb draws pilgrims and pickpockets."],
	["Mirefield", &"hallowed_march", 1240, 1210, 0, [&"fishery"], "Peat and eels on the edge of the fen, where the Harrow loses itself before the sea."],
	["Saltholm", &"hallowed_march", 1720, 1030, 0, [&"salt_works"], "Salt pans on the flats east of Greywater, white as a bleached sheet."],
	["Wheatley", &"hallowed_march", 1640, 880, 0, [&"farm"], "Wide fields along the Greywater, and a mill on every bend."],
	["Harrowford", &"hallowed_march", 1060, 900, 0, [&"farm"], "The first ford on the Harrow. Every army that wanted Oxbridge camped here first."],
	["Ewemoor", &"hallowed_march", 990, 640, 0, [&"sheep_run"], "High grazing under the Cairnspine, where the March's wool comes from."],
	["Oakhurst", &"hallowed_march", 1180, 650, 0, [&"lumber_camp"], "Woodcutters in Harrow Wood, who sell to the shipwrights downriver."],
	["Kingswood", &"hallowed_march", 1880, 790, 0, [&"lumber_camp"], "A royal forest, and a royal forester who hangs poachers on its oaks."],
	["Brackenfold", &"hallowed_march", 1640, 590, 0, [&"sheep_run"], "Sheep on the uplands, and shepherds who see the Whitecrowns from their doors."],
	["Holloway", &"hallowed_march", 1450, 560, 0, [&"iron_mine"], "A deep cut in the March uplands, worked by debtors who will not live to pay."],
	["Gallowmere", &"hallowed_march", 1080, 1240, 0, [&"lumber_camp"], "Charcoal and gibbets in the Gallowood."],
	["Wynmouth", &"hallowed_march", 900, 1500, 0, [&"fishery"], "Boats on the shingle, and the Narrows' fog coming in every evening."],
	["Stonebridge", &"hallowed_march", 820, 1290, 0, [&"quarry"], "Grey stone off the Cairnspine's foot, cut for every wall in the March."],

	["Dunholt", &"vane", 380, 950, 2, [&"quarry", &"weaver", &"weaponsmith", &"brewery"], "A black keep on the moor. The kings of Vane were crowned here in the rain, and consider it lucky."],
	["Saltmarch", &"vane", 270, 1250, 1, [&"fishery", &"weaver", &"brewery", &"salt_works"], "Salt pans and whalers on the western ocean. The richest town in Vane, and the first to say so."],
	["Wolfden", &"vane", 440, 640, 1, [&"iron_mine", &"smelter", &"weaver"], "A mining town under the Wolfcrags, on the dark Tarn."],
	["Moorcross", &"vane", 330, 820, 0, [&"sheep_run"], "Where four drove roads cross the moor, and four lords' sheep get mixed up."],
	["Corbinstead", &"vane", 470, 1090, 0, [&"farm"], "Border town. It has flown both banners, and keeps both in the same chest."],
	["Gallowfen", &"vane", 300, 1080, 0, [&"fishery"], "Fen folk who hang their dead in the alders, and their thieves beside them."],
	["Whalesend", &"vane", 260, 1460, 0, [&"fishery"], "Whale bones for rafters, and oil for every lamp in Vane."],
	["Brinepans", &"vane", 250, 1360, 0, [&"salt_works"], "Boiling houses on the shore, smoking all year."],
	["Ravensholt", &"vane", 330, 700, 0, [&"trapper_lodge"], "Trappers in the old wood, who pay their tithe in marten skins."],
	["Blackpit", &"vane", 500, 560, 0, [&"iron_mine"], "The oldest mine in Vane, and the only thing in it that is not haunted is the ore."],
	["Gullwick", &"vane", 440, 1630, 0, [&"fishery"], "Huts on the north cliff of the Narrows, watching ships the dwarves will tax."],

	["Kharzad", &"free_holds", 600, 1000, 2, [&"iron_mine", &"quarry", &"smelter", &"armorer", &"weaponsmith"], "The Gate itself: a hold cut through the Cairnspine, with one door to the west and one to the east. All who cross pay here."],
	["Ironhall", &"free_holds", 720, 760, 1, [&"iron_mine", &"smelter", &"weaponsmith"], "The north hold, where the furnaces never go out."],
	["Stonewatch", &"free_holds", 700, 1620, 1, [&"quarry", &"armorer", &"fishery"], "A fortress on the cliff over the Narrows. Every ship that passes below pays it, or sinks."],
	["Deephollow", &"free_holds", 720, 1100, 0, [&"iron_mine"], "A delve so deep its miners keep their own calendar."],
	["Highcairn", &"free_holds", 520, 1160, 0, [&"quarry"], "Stone for the holds, cut in steps down the mountain."],
	["Copperdeep", &"free_holds", 720, 650, 0, [&"iron_mine"], "Ore carts on rails and a smell of hot stone."],
	["Greyshaft", &"free_holds", 540, 820, 0, [&"quarry"], "A quarry where the dwarves cut their great doors."],
	["Coldanvil", &"free_holds", 650, 1330, 0, [&"quarry"], "The hold in the Coldgap, where the wind never stops."],
	["Narrowgate", &"free_holds", 820, 1630, 0, [&"fishery"], "A harbour of chains and booms at the east end of the Narrows."],

	["Hrafnhold", &"rime", 1520, 200, 2, [&"fishery", &"weaponsmith", &"armorer", &"weaver"], "The jarl's hall at the mouth of the Rimewater, roofed with upturned ships."],
	["Skeldvik", &"rime", 1060, 260, 1, [&"fishery", &"smelter", &"brewery"], "A raiders' harbour on a cold fjord."],
	["Vintra", &"rime", 2200, 170, 1, [&"fishery", &"brewery", &"weaver"], "Winter town. The sea freezes to its doorsteps for three months of the year."],
	["Kaldmark", &"rime", 2700, 270, 1, [&"quarry", &"brewery", &"weaver"], "Watches the road over the Whitecrowns, and the elves who sometimes come down it."],
	["Frosthaven", &"rime", 1720, 290, 0, [&"fishery"], "Cod on racks as far as you can see, frozen hard as planks."],
	["Ulfstead", &"rime", 1400, 380, 0, [&"trapper_lodge"], "Wolf skins and bear skins, and the men who took them."],
	["Nordvik", &"rime", 900, 300, 0, [&"fishery"], "The last harbour west, under the black cliffs."],
	["Grimsby", &"rime", 1250, 340, 0, [&"iron_mine"], "Bog iron and fell iron, smelted in pits."],
	["Isfjord", &"rime", 1960, 170, 0, [&"fishery"], "A fjord with ice in it until midsummer."],
	["Kolby", &"rime", 2420, 320, 0, [&"trapper_lodge"], "Trappers in the pines under the Whitecrowns."],
	["Hrimfell", &"rime", 2600, 340, 0, [&"iron_mine"], "A mine on the fell, worked only in summer."],
	["Selvik", &"rime", 2900, 230, 0, [&"fishery"], "Seal hunters at the east end of the Rime."],

	["Palecourt", &"veiled_court", 3150, 960, 2, [&"weaver", &"armorer", &"lumber_camp", &"brewery"], "The court of the elves on Lake Evenmere, where the trees are older than the stone."],
	["Moonveil", &"veiled_court", 2800, 720, 1, [&"lumber_camp", &"weaver", &"weaponsmith"], "A city in the branches at the edge of the Northwold."],
	["Duskmere", &"veiled_court", 3430, 1140, 1, [&"weaver", &"brewery", &"artisan_quarter"], "Where the elves meet the merchants of Ilm, and pretend not to need them."],
	["Evenfall", &"veiled_court", 2990, 1120, 1, [&"fishery", &"lumber_camp", &"weaver"], "The court's one port on the Drowned Sea, white quays under black trees."],
	["Thornveil", &"veiled_court", 3260, 1060, 0, [&"lumber_camp"], "Fellers who ask each tree's leave, and take it anyway."],
	["Starwater", &"veiled_court", 3230, 780, 0, [&"fishery"], "Fishers on the black lake, who never fish at night."],
	["Nightspire", &"veiled_court", 2700, 600, 0, [&"trapper_lodge"], "A tower in the pines, and the trappers who live in its shadow."],
	["Silverbough", &"veiled_court", 2920, 650, 0, [&"lumber_camp"], "The elves' great timber, floated down to the court."],
	["Ashgrove", &"veiled_court", 3560, 1040, 0, [&"vineyard"], "Vines on the warm slopes east of the wood."],
	["Wychfold", &"veiled_court", 3420, 900, 0, [&"trapper_lodge"], "Furs for the court, from a lodge the wood has half swallowed."],
	["Mistharbor", &"veiled_court", 2850, 1090, 0, [&"fishery"], "Fog every morning, and boats that come back out of it with full nets."],
	["Gloaming", &"veiled_court", 3130, 1170, 0, [&"vineyard"], "Pale wine, pressed by bonded hands that never taste it."],

	["Ilmaresh", &"ilmaresh", 3400, 1600, 2, [&"fishery", &"weaver", &"brewery", &"weaponsmith", &"artisan_quarter"], "A white city at the east end of the Drowned Sea, richer than its masters in Zahrun and careful not to show it."],
	["Saffa", &"ilmaresh", 3870, 1500, 1, [&"fishery", &"weaver", &"brewery"], "The satraps' port on the Sunward Sea, and caravans gathering for the long road north."],
	["Alqarra", &"ilmaresh", 3650, 1980, 1, [&"weaver", &"brewery"], "An oasis town around a well so old that its first builders are not remembered."],
	["Cedarhold", &"ilmaresh", 3560, 1450, 0, [&"lumber_camp"], "Cedar for the satraps' ships, cut on the slopes under the Greyfangs."],
	["Pearlstrand", &"ilmaresh", 3330, 1760, 0, [&"pearl_beds"], "Divers who go down holding their breath and a stone."],
	["Amberlee", &"ilmaresh", 3800, 1350, 0, [&"vineyard"], "Sweet wine for the satraps' tables, and sour wine for everyone else."],
	["Saltwhite", &"ilmaresh", 3920, 1660, 0, [&"salt_works"], "Salt pans on the Sunward shore."],
	["Qasr", &"ilmaresh", 3760, 2060, 0, [&"horse_ranch"], "Desert horses, small and tireless, sold for their weight in silver."],
	["Dunewell", &"ilmaresh", 3540, 2010, 0, [&"farm"], "Fields round a deep well, watered by bonded hands."],

	["Zahrun", &"zahrun", 3000, 2170, 2, [&"fishery", &"weaver", &"brewery", &"weaponsmith", &"armorer"], "The Throne on the Sahr delta. Its canals water a hundred miles of fields that would otherwise be sand."],
	["Tamarzi", &"zahrun", 2700, 2450, 1, [&"weaver", &"brewery"], "Where the kings of Zahrun are buried in the cliffs."],
	["Qaresh", &"zahrun", 3250, 2520, 1, [&"weaver", &"smelter"], "An upriver city of the Sahr, full of grain barges going down."],
	["Kesh", &"zahrun", 2930, 2780, 1, [&"weaver", &"brewery"], "Salt and glass, on the dry edge of the south coast."],
	["Nuhar", &"zahrun", 2880, 2170, 0, [&"fishery"], "Reed boats in the delta, and fish dried on the roofs."],
	["Khemra", &"zahrun", 3080, 2380, 0, [&"plantation"], "River fields worked by gangs in the heat."],
	["Sabkha", &"zahrun", 2780, 2190, 0, [&"salt_works"], "Salt flats where the desert meets the sea."],
	["Rimal", &"zahrun", 2620, 2600, 0, [&"horse_ranch"], "The kings' horse runs, out on the sand."],
	["Mesa", &"zahrun", 3200, 2660, 0, [&"quarry"], "Red stone cut from the mesas for the tombs of kings."],
	["Ouda", &"zahrun", 3060, 2550, 0, [&"farm"], "Wheat on the river, taxed twice before it is cut."],
	["Wadi Sur", &"zahrun", 3080, 2760, 0, [&"farm"], "A walled field in a dry valley, fed by one spring."],
	["Hamra", &"zahrun", 2880, 2900, 0, [&"quarry"], "A quarry by the south sea, where convicts cut sandstone."],

	["Calavar", &"tidebound", 3700, 2700, 2, [&"fishery", &"lumber_camp", &"weaver", &"brewery"], "The council port of the League, half built on the river and half on the jungle."],
	["Maruva", &"tidebound", 3900, 2290, 1, [&"fishery", &"lumber_camp", &"weaver"], "Shipyards and pearl divers on the Sunward shore."],
	["Sethra", &"tidebound", 3460, 2840, 1, [&"fishery", &"weaver"], "Stilt houses in the mangroves on the south coast."],
	["Jadeford", &"tidebound", 3650, 2520, 0, [&"plantation"], "Cane fields on the Jadewater, worked by free hands for a share."],
	["Rotmire", &"tidebound", 3600, 2760, 0, [&"fishery"], "Crabs and eels in the mangroves."],
	["Palmhaven", &"tidebound", 3940, 2150, 0, [&"fishery"], "A beach of black sand and a hundred boats."],
	["Greenhollow", &"tidebound", 3780, 2420, 0, [&"lumber_camp"], "Hardwood for keels, dragged out of the jungle by oxen."],
	["Brightwater", &"tidebound", 3340, 2860, 0, [&"pearl_beds"], "Pearl divers' town on a clear bay."],
	["Sweetcane", &"tidebound", 3500, 2650, 0, [&"plantation"], "Sugar boiled in great pans, and sold as far as the Rime."],

	["Sunwell", &"sunwell_hive", 2520, 2620, 2, [&"weaver", &"smelter", &"weaponsmith", &"brewery"], "A dry well with a city's worth of foundations around it, and the kheth mounds risen on top. The brood-mother has never been seen outside."],
	["Ikthar", &"sunwell_hive", 2660, 2900, 1, [&"fishery", &"weaver"], "Mounds along the south shore, humming day and night."],
	["Szekkra", &"sunwell_hive", 2380, 2830, 1, [&"smelter", &"weaver"], "The hive's door to the ash, where slag is traded for slaves going the other way."],
	["Khel", &"sunwell_hive", 2620, 2730, 0, [&"farm"], "Fungus beds in the shade of the mounds, and a little grain."],
	["Ssarith", &"sunwell_hive", 2440, 2540, 0, [&"quarry"], "A pit where the kheth cut stone with their jaws."],
	["Kesset", &"sunwell_hive", 2540, 2960, 0, [&"fishery"], "The brood's fishers, who do not swim and do not need to."],
	["Vrakk", &"sunwell_hive", 2300, 2760, 0, [&"iron_mine"], "A mine on the ash's edge, its workers bred for it."],

	["Gorthul", &"ashen_dominion", 1950, 2470, 2, [&"iron_mine", &"smelter", &"weaponsmith", &"armorer"], "The khan's hall under Mount Ghulmar, black stone on black ash."],
	["Ashkar", &"ashen_dominion", 2330, 2350, 1, [&"fishery", &"smelter", &"weaver"], "The dead shore's port, at the foot of the Wading Road."],
	["Morgrim", &"ashen_dominion", 1820, 2800, 1, [&"smelter", &"weaponsmith"], "A fortress-camp of the khans, built of the ruin it stands on."],
	["Bonepit", &"ashen_dominion", 2150, 2990, 1, [&"fishery", &"smelter"], "A slave market on the south coast, and the ships that feed it."],
	["Cinderpit", &"ashen_dominion", 2010, 2380, 0, [&"iron_mine"], "Iron from the ash rim, dug by people bought in Bonepit."],
	["Bloodgrass", &"ashen_dominion", 1830, 2470, 0, [&"farm"], "Red grass that grows on ash, and the thin grain that grows with it."],
	["Dreadhold", &"ashen_dominion", 2130, 2290, 0, [&"fishery"], "Grey fish from a grey sea, and the khans' war galleys drawn up on the shingle."],
	["Grimsalt", &"ashen_dominion", 2470, 2290, 0, [&"salt_works"], "Salt boiled on the dead shore with driftwood fires."],
	["Skullrock", &"ashen_dominion", 1720, 2680, 0, [&"quarry"], "A quarry with a face, and the face is not natural."],
	["Ashfield", &"ashen_dominion", 1920, 2860, 0, [&"farm"], "Fields on the old lava, more stone than soil."],
	["Gravelmaw", &"ashen_dominion", 2270, 2840, 0, [&"iron_mine"], "A hole in the ground that has eaten more slaves than any market sold."],
	["Charnel", &"ashen_dominion", 2000, 2970, 0, [&"fishery"], "Fish and bones on the south shore."],

	["Ulvasse", &"drowned_crown", 2230, 2060, 2, [&"fishery", &"weaver", &"brewery", &"armorer"], "The Crown's seat on the great skerry, half under water at high tide. Its queens are crowned in the sea and dried off after."],
	["Skerrow", &"drowned_crown", 2450, 2005, 1, [&"fishery", &"brewery"], "The eastern skerry, where the ash drifts in deepest and the fishing is best."],
	["Wrackmouth", &"drowned_crown", 2030, 2020, 0, [&"fishery"], "Drying racks and wreck-salvage. Half the timber in its halls came off ships that did not mean to stop."],
	["Gullhame", &"drowned_crown", 2320, 2100, 0, [&"pearl_beds"], "Grey pearls from the weedmeres, worth more than the rest of the Crown together."],
	["Kelpholm", &"drowned_crown", 2610, 1950, 0, [&"fishery"], "A rock full of birds and the merrow who eat their eggs."],

	["Skarn", &"skarn", 900, 2400, 2, [&"weaver", &"weaponsmith", &"brewery", &"armorer"], "The Horde's town of tents and stone, on the Skarnwash."],
	["Urzakh", &"skarn", 480, 2260, 1, [&"weaver", &"weaponsmith"], "A camp that would not move on, under the Teeth."],
	["Kragmaw", &"skarn", 1350, 2070, 1, [&"fishery", &"weaver", &"smelter"], "The Horde's port on the Drowned Sea, where riders learned to row."],
	["Tolgar", &"skarn", 1250, 2700, 1, [&"weaver", &"brewery"], "A market for horses and captives, on the south steppe."],
	["Ordu", &"skarn", 1020, 2340, 0, [&"horse_ranch"], "The khagan's herds, ten thousand strong in a good year."],
	["Vorzakh", &"skarn", 700, 2640, 0, [&"horse_ranch"], "Horse camps in the badlands, wild as the horses."],
	["Yurtfield", &"skarn", 820, 2540, 0, [&"sheep_run"], "Flocks on the grass, and felt made from them."],
	["Teethgate", &"skarn", 620, 2190, 0, [&"quarry"], "Stone from the Teeth, for the walls the Horde says it does not need."],
	["Wolfgrass", &"skarn", 380, 2400, 0, [&"sheep_run"], "Sheep on the west steppe, and the wolves that follow them."],
	["Gullmouth", &"skarn", 420, 1900, 0, [&"fishery"], "Fishers on the south cliff of the Narrows."],
	["Skarnmouth", &"skarn", 1090, 1970, 0, [&"fishery"], "Boats at the mouth of the Skarnwash."],
	["Tarkhan", &"skarn", 1480, 2250, 0, [&"horse_ranch"], "Horses for the Horde's port, and for sale across the sea."],
	["Redcliff", &"skarn", 1300, 2580, 0, [&"iron_mine"], "Iron out of a red cliff, and red rivers under it."],
	["Kumys", &"skarn", 1150, 2820, 0, [&"sheep_run"], "Sheep and mares' milk, on the far south grass."],

	["The Drowned Throne", &"", 2000, 1600, 0, [], "An isle in the middle of the sea, all that stands of old Ortel's capital. Its towers go down into the water further than they go up."],
	["Mirrormere", &"", 2400, 700, 0, [], "Cold pine country by the still lake, with old standing stones."],
	["Pinemarch", &"", 2150, 720, 0, [], "Good land in the Northwold that three realms claim and none hold."],
	["Wolfrun", &"", 2620, 900, 0, [], "A clearing in the pines where nothing grows back."],
	["Saltmeadow", &"", 2200, 900, 0, [], "Sea meadows on the north shore, with nobody on them."],
	["Gull Rock", &"", 1120, 1700, 0, [], "A rock in the west of the sea with a broken light on it."],
	["Kingfisher Isle", &"", 1780, 1300, 0, [], "A green isle off the March, with a ruined abbey."],
	["The Saltisles", &"", 2950, 1500, 0, [], "Low isles in the east of the sea, all salt grass and birds."],
	["Cinderwaste", &"", 1600, 2450, 0, [], "Scorched ground between the steppe and the ash."],
	["Sandwell", &"", 3380, 2340, 0, [], "A well in the desert that someone filled with stones."],
	["The Jade Steps", &"", 3560, 2340, 0, [], "Stairs cut into a jungle hill, leading to nothing anyone has found."],
	["Lorn", &"", 300, 2640, 0, [], "The last of an old duchy, a chapel and a wall, looking at the ocean."],
	["Isvik", &"", 260, 540, 0, [], "A good harbour that the Rime and Vane have both burned."],
	["The Fang Pass", &"", 3620, 1300, 0, [], "A tollhouse in the pass that nobody tolls."],
]

## Roads between cities that are there on the first day, by place name. Every town has a road to its city as well.
const ROADS: Array = [
	["Harrowmere", "Greywater"], ["Harrowmere", "Oxbridge"], ["Harrowmere", "Cinderford"], ["Greywater", "Thornwick"],
	["Oxbridge", "Thornwick"], ["Oxbridge", "Kharzad"], ["Cinderford", "Stonewatch"], ["Oxbridge", "Ironhall"],
	["Dunholt", "Saltmarch"], ["Dunholt", "Wolfden"], ["Dunholt", "Kharzad"], ["Wolfden", "Ironhall"], ["Saltmarch", "Stonewatch"],
	["Kharzad", "Ironhall"], ["Kharzad", "Stonewatch"],
	["Hrafnhold", "Skeldvik"], ["Hrafnhold", "Vintra"], ["Vintra", "Kaldmark"], ["Skeldvik", "Wolfden"], ["Hrafnhold", "Thornwick"],
	["Vintra", "Thornwick"], ["Kaldmark", "Moonveil"],
	["Palecourt", "Moonveil"], ["Palecourt", "Duskmere"], ["Palecourt", "Evenfall"], ["Evenfall", "Duskmere"], ["Moonveil", "Thornwick"],
	["Duskmere", "Ilmaresh"],
	["Ilmaresh", "Saffa"], ["Ilmaresh", "Alqarra"], ["Saffa", "Alqarra"], ["Alqarra", "Maruva"], ["Alqarra", "Zahrun"],
	["Zahrun", "Tamarzi"], ["Zahrun", "Qaresh"], ["Qaresh", "Kesh"], ["Tamarzi", "Kesh"], ["Qaresh", "Calavar"], ["Kesh", "Sethra"],
	["Calavar", "Maruva"], ["Calavar", "Sethra"],
	["Sunwell", "Ikthar"], ["Sunwell", "Szekkra"], ["Sunwell", "Tamarzi"], ["Sunwell", "Ashkar"], ["Ikthar", "Kesh"],
	["Gorthul", "Ashkar"], ["Gorthul", "Morgrim"], ["Gorthul", "Bonepit"], ["Morgrim", "Bonepit"], ["Bonepit", "Szekkra"],
	["Gorthul", "Kragmaw"], ["Morgrim", "Tolgar"],
	["Skarn", "Urzakh"], ["Skarn", "Kragmaw"], ["Skarn", "Tolgar"], ["Tolgar", "Kragmaw"],
	["Ulvasse", "Ashkar"], ["Ulvasse", "Skerrow"],
]

## Name, x, y, how large to write it, and what is said of it.
const LABELS: Array = [
	["The Drowned Sea", 2150, 1750, 2.4, "Old Ortel lies under it. On still days the fishers see roofs."],
	["The Narrows", 470, 1735, 1.0, "The one way from the Drowned Sea to the ocean, between dwarf cliffs and steppe cliffs."],
	["The Sundering Sea", 70, 1200, 1.7, "West of everything. Ships that go out on it are not expected back."],
	["The Cold Reach", 2100, 50, 1.6, "Ice for half the year."],
	["The Sunward Sea", 4110, 1700, 1.4, "Warm water and the ships of three peoples on it."],
	["The Sea of Cinders", 2200, 2200, 1.2, "Ash falls on it from Ghulmar, and floats."],
	["The Southern Deep", 2300, 3130, 1.5, "Past the south coast nobody has found a far shore."],
	["The Cairnspine", 560, 1200, 1.5, "The dwarves' wall down the west. There are two ways through, and both belong to the dwarves."],
	["The Whitecrowns", 2300, 380, 1.1, "Snow that never melts, and one pass under it."],
	["The Sablewood", 3200, 1000, 1.6, "Once it touched both seas. It is still the largest thing in the world that is alive."],
	["The Northwold", 2450, 760, 1.2, "Cold pines between the Rime and the elves, claimed by many and held by none."],
	["The Rime", 1700, 180, 1.3, "The frozen north coast, and the people who live on it anyway."],
	["The Hallowed Marches", 1400, 860, 1.4, "The grain lands of the Harrow and the Greywater, the first country anyone ever fought over."],
	["The Vane Moors", 340, 900, 1.1, "Wind, sheep and grudges."],
	["The Wolfcrags", 440, 470, 0.9, "Iron, and worse."],
	["The Skarn Steppe", 850, 2500, 1.4, "Grass to the horizon, and riders on it."],
	["The Teeth", 680, 2080, 0.9, "No road crosses them."],
	["The Cinder Reach", 2000, 2700, 1.2, "Ash country under the mountain."],
	["Mount Ghulmar", 2055, 2600, 1.0, "The mountain that burns."],
	["Lake Evenmere", 3150, 850, 0.9, "Still, black and very deep."],
	["The Sahr Waste", 2950, 2600, 1.3, "Sand, except where the river is."],
	["The Verdant Reach", 3700, 2550, 1.2, "Jungle so thick the roads have to be cut again every year."],
	["Kharzad Gate", 600, 975, 0.8, "The northern pass of the Cairnspine."],
	["The Coldgap", 640, 1305, 0.8, "The southern pass."],
	["Frostgate", 2250, 395, 0.8, "The pass under the Whitecrowns."],
	["The Greyfangs", 3630, 1235, 0.8, "Low, sharp hills between the elves and the satraps."],
	["The Cinder Skerries", 2250, 1990, 1.1, "Grey rocks in a grey sea, and the merrow on them."],
	["The Wading Road", 2300, 2210, 0.7, "Shallows from the dead shore to Ulvasse. Waist deep at low tide, and nobody goes at high."],
]
