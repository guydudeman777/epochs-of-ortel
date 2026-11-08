class_name OverworldLand
extends RefCounted
## Draws the land the simulation's terrain describes: the ground, water, roads, woods and towns. It reads and changes nothing.
## The ground and the woods are cut into square pieces, so that when people change the land only the pieces they touched
## are drawn again.

const GROUND_STEP: float = 4.0
## Map units a side of one piece.
const PIECE: float = 96.0
const ROAD_STEP: float = 3.0
const ROAD_HALF_WIDTH: float = 2.0
const ROAD_LIFT: float = 0.5
const TREE_STEP: float = 6.5
const TREE_SCALE_LOW: float = 0.55
const TREE_SCALE_HIGH: float = 0.95
const ROCK_STEP: float = 13.0
## No tree or rock stands this near a town's middle, where its houses and walls go.
const TOWN_KEPT_CLEAR: float = 42.0
const COLORS: Dictionary[OverworldTerrain.Kind, Color] = {
	OverworldTerrain.Kind.OPEN: Color(0.235, 0.255, 0.135),
	OverworldTerrain.Kind.FOREST: Color(0.115, 0.155, 0.085),
	OverworldTerrain.Kind.HILLS: Color(0.29, 0.265, 0.215),
	OverworldTerrain.Kind.WATER: Color(0.2, 0.2, 0.15),
	OverworldTerrain.Kind.ROAD: Color(0.25, 0.235, 0.15),
	OverworldTerrain.Kind.MARSH: Color(0.16, 0.18, 0.11),
	OverworldTerrain.Kind.DEEP: Color(0.05, 0.075, 0.09),
	OverworldTerrain.Kind.PEAK: Color(0.31, 0.3, 0.29),
}
## What each country does to the colour of its ground, and how far.
## By LandDef.Biome: temperate, north, steppe, ash, desert, tropical, alpine, snow.
const BIOME_TINT: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.0), Color(0.33, 0.35, 0.33, 0.35), Color(0.42, 0.36, 0.17, 0.6), Color(0.1, 0.09, 0.09, 0.72),
	Color(0.6, 0.48, 0.29, 0.82), Color(0.12, 0.26, 0.08, 0.4), Color(0.3, 0.32, 0.27, 0.3), Color(0.72, 0.74, 0.78, 0.85),
]
const BLEND_OFFSETS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(14.0, 0.0), Vector2(-14.0, 0.0), Vector2(0.0, 14.0), Vector2(0.0, -14.0), Vector2(10.0, 10.0), Vector2(-10.0, -10.0)]
## Desert ground this near the water grows palms.
const OASIS_HEIGHT: float = 3.5
const SHORE_COLOR: Color = Color(0.4, 0.36, 0.25)
const SHORE_HEIGHT: float = 1.6
const FIELD_COLOR: Color = Color(0.33, 0.31, 0.14)
const FIELD_BARE_COLOR: Color = Color(0.25, 0.21, 0.13)
const FIELD_SIZE: float = 9.0
const ROAD_COLOR: Color = Color(0.56, 0.47, 0.32)
const WATER_COLOR: Color = Color(0.13, 0.22, 0.27, 0.86)
const SKY_COLOR: Color = Color(0.07, 0.12, 0.15)
const SNOW_FROM: float = 21.0
const SNOW_COLOR: Color = Color(0.62, 0.63, 0.65)
## The high ground of the ash country carries cinders, not snow, and the highest of it glows.
const CINDER_COLOR: Color = Color(0.07, 0.06, 0.06)
const EMBER_COLOR: Color = Color(0.62, 0.2, 0.05)
const EMBER_FROM: float = 44.0
const MAP_NAME_HEIGHT: float = 26.0
## From how far up the names of the seas and the countries can be read.
const MAP_NAMES_FROM: float = 230.0
const FOG_NEAR: float = 0.0016
const FOG_PER_ZOOM: float = 0.2


## Height a band or a building stands at. Never under the water.
static func stand_height(terrain: OverworldTerrain, point: Vector2) -> float:
	return maxf(terrain.height(point), OverworldTerrain.WATER_LEVEL)


static func build(parent: Node3D, ctx: SimContext) -> void:
	var terrain: OverworldTerrain = ctx.terrain()
	var ground: Node3D = Node3D.new()
	ground.name = "Ground"
	parent.add_child(ground)
	var woods: Node3D = Node3D.new()
	woods.name = "Woods"
	parent.add_child(woods)
	var pieces_x: int = ceili((terrain.high.x - terrain.low.x) / PIECE)
	var pieces_y: int = ceili((terrain.high.y - terrain.low.y) / PIECE)
	for x: int in range(pieces_x):
		for y: int in range(pieces_y):
			_build_piece(ground, woods, ctx, Vector2i(x, y))
	_build_water(parent, terrain)
	build_roads(parent, ctx)
	_build_map_names(parent, terrain)
	_build_light(parent)


## Draws again every piece of land within reach of a point.
static func redraw_around(parent: Node3D, ctx: SimContext, center: Vector2, reach: float) -> void:
	var terrain: OverworldTerrain = ctx.terrain()
	var ground: Node = parent.get_node("Ground")
	var woods: Node = parent.get_node("Woods")
	var first: Vector2i = Vector2i(((center - Vector2(reach, reach) - terrain.low) / PIECE).floor())
	var last: Vector2i = Vector2i(((center + Vector2(reach, reach) - terrain.low) / PIECE).floor())
	var pieces: Vector2i = Vector2i(((terrain.high - terrain.low) / PIECE).ceil())
	for x: int in range(maxi(first.x, 0), mini(last.x + 1, pieces.x)):
		for y: int in range(maxi(first.y, 0), mini(last.y + 1, pieces.y)):
			for holder: Node in [ground, woods]:
				var old: Node = holder.get_node_or_null("P%d_%d" % [x, y])
				if old != null:
					holder.remove_child(old)
					old.free()
			_build_piece(ground as Node3D, woods as Node3D, ctx, Vector2i(x, y))


static func _build_piece(ground: Node3D, woods: Node3D, ctx: SimContext, piece: Vector2i) -> void:
	var terrain: OverworldTerrain = ctx.terrain()
	var corner: Vector2 = terrain.low + Vector2(piece) * PIECE
	_build_ground(ground, ctx, terrain, corner, "P%d_%d" % [piece.x, piece.y])
	_build_woods(woods, terrain, corner, "P%d_%d" % [piece.x, piece.y], piece)


static func _build_ground(parent: Node3D, ctx: SimContext, terrain: OverworldTerrain, corner: Vector2, node_name: String) -> void:
	var side: int = roundi(PIECE / GROUND_STEP) + 1
	# One row more on every side, so that neighbouring pieces work out the same slope along their shared edge.
	var wide: int = side + 2
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(wide * wide)
	for y: int in range(wide):
		for x: int in range(wide):
			heights[x + y * wide] = terrain.height(corner + Vector2(x - 1, y - 1) * GROUND_STEP)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	vertices.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	for y: int in range(side):
		for x: int in range(side):
			var index: int = x + y * side
			var at: Vector2 = corner + Vector2(x, y) * GROUND_STEP
			var middle: int = (x + 1) + (y + 1) * wide
			var ground: float = heights[middle]
			vertices[index] = Vector3(at.x, ground, at.y)
			normals[index] = Vector3(heights[middle - 1] - heights[middle + 1], 2.0 * GROUND_STEP, heights[middle - wide] - heights[middle + wide]).normalized()
			colors[index] = _ground_color(ctx, terrain, at, ground)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((side - 1) * (side - 1) * 6)
	var at_index: int = 0
	for y: int in range(side - 1):
		for x: int in range(side - 1):
			var a: int = x + y * side
			var b: int = a + 1
			var c: int = a + side
			var d: int = c + 1
			indices[at_index] = a
			indices[at_index + 1] = b
			indices[at_index + 2] = c
			indices[at_index + 3] = b
			indices[at_index + 4] = d
			indices[at_index + 5] = c
			at_index += 6
	_add_mesh(parent, node_name, vertices, normals, colors, indices, _ground_material())


static var _ground_mat: StandardMaterial3D = null
static var _mottle: FastNoiseLite = null


static func _ground_material() -> StandardMaterial3D:
	if _ground_mat == null:
		_ground_mat = StandardMaterial3D.new()
		_ground_mat.vertex_color_use_as_albedo = true
		_ground_mat.vertex_color_is_srgb = true
		_ground_mat.roughness = 1.0
	return _ground_mat


static func _ground_color(ctx: SimContext, terrain: OverworldTerrain, at: Vector2, ground: float) -> Color:
	if _mottle == null:
		_mottle = FastNoiseLite.new()
		_mottle.frequency = 0.06
	var kind: OverworldTerrain.Kind = terrain.kind_at(at)
	var color: Color = COLORS[kind]
	var biome: int = terrain.land.biomes[terrain.land.cell_index(at)] if terrain.land != null else LandDef.Biome.TEMPERATE
	if terrain.land != null:
		var by_shore: bool = kind != OverworldTerrain.Kind.ROAD and ground < OverworldTerrain.WATER_LEVEL + SHORE_HEIGHT and ground >= OverworldTerrain.WATER_LEVEL - 0.6
		if kind == OverworldTerrain.Kind.OPEN and not by_shore and _is_tilled(ctx, at):
			color = _field_color(at)
		var tint: Color = _blended_tint(terrain, at)
		if kind != OverworldTerrain.Kind.DEEP and kind != OverworldTerrain.Kind.WATER and tint.a > 0.0:
			color = color.lerp(Color(tint.r, tint.g, tint.b), tint.a)
		if by_shore:
			color = color.lerp(SHORE_COLOR, 0.7)
	if biome == LandDef.Biome.ASH:
		if ground > SNOW_FROM:
			color = color.lerp(CINDER_COLOR, minf((ground - SNOW_FROM) / 8.0, 1.0))
		if ground > EMBER_FROM:
			color = color.lerp(EMBER_COLOR, minf((ground - EMBER_FROM) / 6.0, 1.0))
	elif ground > SNOW_FROM:
		color = color.lerp(SNOW_COLOR, minf((ground - SNOW_FROM) / 5.0, 1.0))
	return color.darkened(0.12 * (_mottle.get_noise_2dv(at) + 0.5))


## The tint of the countries around a point, mixed, so one country fades into the next.
static func _blended_tint(terrain: OverworldTerrain, at: Vector2) -> Color:
	var sum: Color = Color(0.0, 0.0, 0.0, 0.0)
	for offset: Vector2 in BLEND_OFFSETS:
		var tint: Color = BIOME_TINT[terrain.biome_at(at + offset)]
		# Untinted ground counts as its own colour at no strength, so it thins the mix rather than darkening it.
		sum += Color(tint.r * tint.a, tint.g * tint.a, tint.b * tint.a, tint.a)
	var share: float = 1.0 / BLEND_OFFSETS.size()
	if sum.a <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a, sum.a * share)


## True on the ground a town has cleared around itself, which is what its fields stand on.
static func _is_tilled(ctx: SimContext, at: Vector2) -> bool:
	var map: MapData = ctx.world.map
	for id: int in map.clearings:
		var reach: float = map.clearings[id]
		if map.positions[id].distance_squared_to(at) < reach * reach:
			return true
	return false


## A patchwork, so that farmland reads as farmland from high up.
static func _field_color(at: Vector2) -> Color:
	var x: int = floori(at.x / FIELD_SIZE)
	var y: int = floori((at.y + (x % 3) * 3.0) / (FIELD_SIZE * 0.7))
	return FIELD_COLOR if (x * 7 + y * 13) % 3 != 0 else FIELD_BARE_COLOR


static func _add_mesh(parent: Node3D, mesh_name: String, vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array, material: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = mesh_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _build_water(parent: Node3D, terrain: OverworldTerrain) -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = (terrain.high - terrain.low) * 8.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = WATER_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	material.metallic = 0.3
	plane.material = material
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = plane
	var middle: Vector2 = (terrain.low + terrain.high) * 0.5
	node.position = Vector3(middle.x, OverworldTerrain.WATER_LEVEL, middle.y)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Every road as a strip laid over the ground. Called again when someone founds a town.
static func build_roads(parent: Node3D, ctx: SimContext) -> void:
	var old: Node = parent.get_node_or_null("Roads")
	if old != null:
		parent.remove_child(old)
		old.free()
	var terrain: OverworldTerrain = ctx.terrain()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for road: Vector2i in ctx.world.map.roads:
		var line: PackedVector2Array = OverworldTerrain.road_points(ctx.world.map, road)
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(line.size() - 1):
			var steps: int = maxi(ceili(line[i].distance_to(line[i + 1]) / ROAD_STEP), 1)
			for step: int in range(steps):
				points.append(line[i].lerp(line[i + 1], float(step) / float(steps)))
		points.append(line[line.size() - 1])
		for i: int in range(points.size()):
			var along: Vector2 = points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
			var across: Vector2 = along.normalized().orthogonal() * ROAD_HALF_WIDTH
			var left: Vector2 = points[i] + across
			var right: Vector2 = points[i] - across
			var first: int = vertices.size()
			vertices.append(Vector3(left.x, stand_height(terrain, left) + ROAD_LIFT, left.y))
			vertices.append(Vector3(right.x, stand_height(terrain, right) + ROAD_LIFT, right.y))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			colors.append(ROAD_COLOR)
			colors.append(ROAD_COLOR)
			if i > 0:
				indices.append_array(PackedInt32Array([first - 2, first - 1, first, first - 1, first + 1, first]))
	if vertices.is_empty():
		return
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(parent, "Roads", vertices, normals, colors, indices, material)


## The trees and rocks of one piece. The same in every game, until someone cuts them down.
static func _build_woods(parent: Node3D, terrain: OverworldTerrain, corner: Vector2, node_name: String, piece: Vector2i) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	parent.add_child(holder)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(piece) + 2237
	var trees: Dictionary[String, Array] = {}
	var rocks: Array[Transform3D] = []
	var x: float = 0.0
	while x < PIECE:
		var y: float = 0.0
		while y < PIECE:
			var at: Vector2 = corner + Vector2(x, y) + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			var kind: OverworldTerrain.Kind = terrain.kind_at(at)
			var model: String = _tree_for(terrain, at, kind, rng.randf(), rng.randf())
			if not model.is_empty() and terrain.town_distance(at) > TOWN_KEPT_CLEAR:
				var tree: Transform3D = _prop_at(terrain, at, rng, TREE_SCALE_LOW, TREE_SCALE_HIGH)
				if not trees.has(model):
					trees[model] = []
				trees[model].append(tree)
			y += TREE_STEP
		x += TREE_STEP
	x = 0.0
	while x < PIECE:
		var y: float = 0.0
		while y < PIECE:
			var at: Vector2 = corner + Vector2(x, y) + Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
			var kind: OverworldTerrain.Kind = terrain.kind_at(at)
			if (kind == OverworldTerrain.Kind.HILLS or kind == OverworldTerrain.Kind.PEAK) and rng.randf() < 0.5 and terrain.town_distance(at) > TOWN_KEPT_CLEAR:
				rocks.append(_prop_at(terrain, at, rng, 1.5, 3.6))
			y += ROCK_STEP
		x += ROCK_STEP
	var models: Array[String] = []
	models.assign(trees.keys())
	models.sort()
	for model: String in models:
		var places: Array[Transform3D] = []
		places.assign(trees[model])
		_add_many(holder, model, places)
	_add_many(holder, "rock", rocks)


## Which tree, if any, grows at a spot. Each country grows its own.
static func _tree_for(terrain: OverworldTerrain, at: Vector2, kind: OverworldTerrain.Kind, pick: float, which: float) -> String:
	var biome: LandDef.Biome = terrain.biome_at(at)
	if kind == OverworldTerrain.Kind.FOREST:
		match biome:
			LandDef.Biome.ASH:
				return "dead_tree"
			LandDef.Biome.SNOW:
				return "snow_pine"
			LandDef.Biome.NORTH, LandDef.Biome.ALPINE:
				return "snow_pine" if terrain.height(at) > SNOW_FROM - 7.0 else ("pine_a" if which < 0.6 else "pine_b")
			LandDef.Biome.TROPICAL:
				return "jungle_tree" if which < 0.65 else "palm"
			LandDef.Biome.DESERT:
				return "palm"
		return "broadleaf" if which < 0.5 else ("pine_a" if which < 0.8 else "pine_b")
	if kind == OverworldTerrain.Kind.OPEN:
		match biome:
			LandDef.Biome.DESERT:
				return "palm" if pick < 0.25 and terrain.height(at) < OverworldTerrain.WATER_LEVEL + OASIS_HEIGHT else ""
			LandDef.Biome.TROPICAL:
				return "palm" if pick < 0.04 else ""
			LandDef.Biome.ASH:
				return "dead_tree" if pick < 0.03 else ""
			LandDef.Biome.STEPPE:
				return "dead_tree" if pick < 0.004 else ""
			LandDef.Biome.SNOW:
				return "snow_pine" if pick < 0.01 else ""
		return ("broadleaf" if biome == LandDef.Biome.TEMPERATE else "pine_a") if pick < 0.018 else ""
	if (kind == OverworldTerrain.Kind.HILLS and pick < 0.06) or (kind == OverworldTerrain.Kind.MARSH and pick < 0.12):
		return "palm" if biome == LandDef.Biome.TROPICAL else "dead_tree"
	return ""


static func _prop_at(terrain: OverworldTerrain, at: Vector2, rng: RandomNumberGenerator, low: float, high: float) -> Transform3D:
	var size: float = rng.randf_range(low, high)
	var turned: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(size, size, size))
	return Transform3D(turned, Vector3(at.x, stand_height(terrain, at) - 0.2, at.y))


static func _add_many(parent: Node3D, model: String, places: Array[Transform3D]) -> void:
	if places.is_empty():
		return
	var many: MultiMesh = MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = mesh_of_cached(model)
	many.instance_count = places.size()
	for i: int in range(places.size()):
		many.set_instance_transform(i, places[i])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = many
	parent.add_child(node)


## The names of the seas, ranges and countries, for reading the map from high up.
static func _build_map_names(parent: Node3D, terrain: OverworldTerrain) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "MapNames"
	holder.visible = false
	parent.add_child(holder)
	if terrain.land == null:
		return
	for def: LandLabelDef in terrain.land.labels:
		var label: Label3D = Label3D.new()
		label.text = def.display_name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = 0.0009
		label.font_size = roundi(24.0 * def.size)
		label.outline_size = 6
		label.modulate = Color(0.92, 0.88, 0.76, 0.8)
		label.position = Vector3(def.position.x, MAP_NAME_HEIGHT, def.position.y)
		holder.add_child(label)


## What changes with how high up you are looking from. The names show, and the haze thins so the whole land can be seen.
static func set_view_height(parent: Node3D, zoom: float) -> void:
	(parent.get_node("MapNames") as Node3D).visible = zoom >= MAP_NAMES_FROM
	var holder: WorldEnvironment = parent.get_node("Sky") as WorldEnvironment
	holder.environment.fog_density = FOG_NEAR * minf(1.0, FOG_PER_ZOOM + 135.0 / maxf(zoom, 1.0))


## The one mesh a prop model holds.
static func mesh_of(model: String) -> Mesh:
	var scene: Node3D = (load("res://assets/models/%s.glb" % model) as PackedScene).instantiate() as Node3D
	var found: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh
	scene.free()
	return mesh


## A town as its people build it. See TownView.
static func build_town(parent: Node3D, ctx: SimContext, s: SettlementData) -> Node3D:
	return TownView.build(parent, ctx, s)


static var _meshes: Dictionary[String, Mesh] = {}


static func mesh_of_cached(model: String) -> Mesh:
	if not _meshes.has(model):
		_meshes[model] = mesh_of(model)
	return _meshes[model]


static func _build_light(parent: Node3D) -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	sun.light_color = Color(1.0, 0.86, 0.72)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 320.0
	parent.add_child(sun)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.62, 0.72)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = SKY_COLOR
	environment.fog_density = FOG_NEAR
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.name = "Sky"
	holder.environment = environment
	parent.add_child(holder)
