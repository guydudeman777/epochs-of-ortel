class_name TownGround
extends RefCounted
## The ground of a walkable town: one plane drawn with town_ground.gdshader over a mask painted from the layout.
## Streets and lanes are trodden earth, the market and the rich quarter's streets are cobbled, a rich town's square
## is flagged, and the poor lanes, the craft yards and the backs of the poor houses are mud.

const SHADER: Shader = preload("res://src/view/town/town_ground.gdshader")
## Metres to a texel of the mask.
const TEXEL: float = 0.5
## Soft edge of each painted path, in metres.
const SOFT: float = 1.2
## The open ground of each people's land: [overworld ground layer, colour]. Layers as OverworldLand.Layer.
const OPEN: Dictionary[StringName, Array] = {
	&"hallowed": [0, Color(0.3, 0.35, 0.19)], &"freehold": [0, Color(0.32, 0.34, 0.24)],
	&"rime": [5, Color(0.72, 0.74, 0.78)], &"veiled": [0, Color(0.22, 0.3, 0.17)],
	&"ashen": [6, Color(0.2, 0.18, 0.17)], &"steppe": [0, Color(0.42, 0.4, 0.22)],
	&"sunborn": [3, Color(0.66, 0.55, 0.38)], &"hive": [3, Color(0.6, 0.48, 0.34)],
	&"tidebound": [0, Color(0.2, 0.3, 0.14)], &"reef": [8, Color(0.55, 0.52, 0.44)],
}
## Trodden earth, stone and mud by land, where it differs from the Marches'.
const DIRT: Dictionary[StringName, Color] = {
	&"sunborn": Color(0.58, 0.47, 0.33), &"hive": Color(0.52, 0.41, 0.29), &"ashen": Color(0.22, 0.2, 0.19),
	&"rime": Color(0.42, 0.38, 0.33), &"reef": Color(0.5, 0.45, 0.36),
}
const STONE: Dictionary[StringName, Color] = {
	&"ashen": Color(0.22, 0.2, 0.2), &"sunborn": Color(0.6, 0.52, 0.42), &"hive": Color(0.55, 0.45, 0.33),
	&"veiled": Color(0.55, 0.55, 0.52), &"reef": Color(0.56, 0.48, 0.44),
}


static func build(parent: Node3D, layout: TownLayout) -> MeshInstance3D:
	var size: float = (layout.edge + 12.0) * 2.0
	var n: int = ceili(size / TEXEL)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 4)
	bytes.fill(0)
	var paved: float = 1.0 if layout.wealth > 0.55 else 0.0
	for i: int in range(layout.streets.size()):
		_paint_line(bytes, n, size, layout.streets[i], TownLayout.STREET_HALF, layout, true, paved)
	for lane: PackedVector2Array in layout.lanes:
		_paint_line(bytes, n, size, lane, TownLayout.LANE_HALF, layout, false, 0.0)
	# The square: flags in a rich town, cobbles in most, beaten earth in a poor one.
	var square_channel: int = 2 if layout.wealth > 0.45 else (1 if layout.poverty < 0.7 else 0)
	_paint_disc(bytes, n, size, Vector2.ZERO, layout.square_radius * 1.02, square_channel, 1.0)
	for plaza: Vector2 in layout.plazas:
		_paint_disc(bytes, n, size, plaza, TownLayout.PLAZA_RADIUS, 1 if layout.poverty < 0.6 else 0, 1.0)
	for piece: TownLayout.Piece in layout.pieces:
		if piece.quarter == &"poor" or piece.quarter == &"craft" or piece.kind == &"pen" or piece.kind == &"shed":
			_paint_disc(bytes, n, size, piece.to_town(0.0, piece.low.z - 1.8), 3.2, 3, 0.8)
		if TownLayout.is_yard(piece.kind) or piece.kind == &"pen":
			_paint_disc(bytes, n, size, piece.to_town(0.0, piece.high.z + 1.5), 4.5, 3, 0.7)
	var image: Image = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"mask", ImageTexture.create_from_image(image))
	material.set_shader_parameter(&"mask_size", float(n) * TEXEL)
	material.set_shader_parameter(&"ground_albedo", load(OverworldLand.GROUND_ALBEDO))
	material.set_shader_parameter(&"ground_normal", load(OverworldLand.GROUND_NORMAL))
	material.set_shader_parameter(&"surface_albedo", load(TownSurfaces.ALBEDO))
	material.set_shader_parameter(&"surface_normal", load(TownSurfaces.NORMAL))
	var open: Array = OPEN.get(layout.culture, OPEN[&"hallowed"]) as Array
	material.set_shader_parameter(&"open_layer", open[0] as int)
	material.set_shader_parameter(&"open_color", open[1] as Color)
	material.set_shader_parameter(&"dirt_color", DIRT.get(layout.culture, Color(0.4, 0.33, 0.25)))
	material.set_shader_parameter(&"stone_color", STONE.get(layout.culture, Color(0.45, 0.43, 0.4)))
	material.set_shader_parameter(&"town_radius", maxf(layout.build_radius * 0.75, layout.square_radius + 10.0))
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2.ONE * (layout.edge * 2.0 + 200.0)
	ground.mesh = plane
	ground.material_override = material
	parent.add_child(ground)
	return ground


static func _texel(point: Vector2, n: int, size: float) -> Vector2i:
	return Vector2i(floori((point.x / size + 0.5) * float(n)), floori((point.y / size + 0.5) * float(n)))


static func _write(bytes: PackedByteArray, n: int, x: int, y: int, channel: int, value: float) -> void:
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	var at: int = (y * n + x) * 4 + channel
	bytes[at] = maxi(bytes[at], clampi(roundi(value * 255.0), 0, 255))


## A path, trodden, and cobbled where it runs through the market or the rich quarter (or all of it in a rich town).
static func _paint_line(bytes: PackedByteArray, n: int, size: float, line: PackedVector2Array, half: float, layout: TownLayout, street: bool, paved: float) -> void:
	for i: int in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var reach: float = half + SOFT
		var lo: Vector2i = _texel(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach, n, size)
		var hi: Vector2i = _texel(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach, n, size)
		var quarter: StringName = layout.quarter_at((a + b) * 0.5)
		var cobbled: float = paved
		if street and (quarter == &"market" or quarter == &"rich"):
			cobbled = 1.0
		var muddy: float = 0.75 if quarter == &"poor" else (0.35 if quarter == &"craft" else 0.0)
		for y: int in range(maxi(lo.y, 0), mini(hi.y, n - 1) + 1):
			for x: int in range(maxi(lo.x, 0), mini(hi.x, n - 1) + 1):
				var point: Vector2 = (Vector2(x + 0.5, y + 0.5) / float(n) - Vector2.ONE * 0.5) * size
				var gap: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))
				var amount: float = clampf((reach - gap) / SOFT, 0.0, 1.0)
				if amount <= 0.0:
					continue
				_write(bytes, n, x, y, 0, amount)
				if cobbled > 0.0:
					_write(bytes, n, x, y, 1, amount * cobbled * clampf((half - gap) / SOFT + 0.6, 0.0, 1.0))
				if muddy > 0.0:
					_write(bytes, n, x, y, 3, amount * muddy)


static func _paint_disc(bytes: PackedByteArray, n: int, size: float, at: Vector2, radius: float, channel: int, value: float) -> void:
	var lo: Vector2i = _texel(at - Vector2.ONE * (radius + SOFT), n, size)
	var hi: Vector2i = _texel(at + Vector2.ONE * (radius + SOFT), n, size)
	for y: int in range(maxi(lo.y, 0), mini(hi.y, n - 1) + 1):
		for x: int in range(maxi(lo.x, 0), mini(hi.x, n - 1) + 1):
			var point: Vector2 = (Vector2(x + 0.5, y + 0.5) / float(n) - Vector2.ONE * 0.5) * size
			var amount: float = clampf((radius - point.distance_to(at)) / SOFT + 0.5, 0.0, 1.0)
			if amount > 0.0:
				_write(bytes, n, x, y, channel, amount * value)
				_write(bytes, n, x, y, 0, amount)
