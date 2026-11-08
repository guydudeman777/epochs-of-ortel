extends SceneTree
## Prints how long the roads of the land are, against the straight line between their towns.


func _init() -> void:
	var land: LandDef = load("res://content/defs/land/ortel.res") as LandDef
	var total: float = 0.0
	var straight: float = 0.0
	var longest: float = 0.0
	for road: Vector2i in land.roads:
		var line: PackedVector2Array = land.road_bends[road]
		var length: float = 0.0
		for i: int in range(line.size() - 1):
			length += line[i].distance_to(line[i + 1])
		total += length
		longest = maxf(longest, length)
		if length > 260.0:
			print("  long: %s - %s %.0f (straight %.0f)" % [land.places[road.x].display_name, land.places[road.y].display_name, length, land.places[road.x].position.distance_to(land.places[road.y].position)])
		straight += land.places[road.x].position.distance_to(land.places[road.y].position)
	print("roads %d, mean length %.0f, mean straight %.0f, longest %.0f" % [land.roads.size(), total / land.roads.size(), straight / land.roads.size(), longest])
	quit(0)
