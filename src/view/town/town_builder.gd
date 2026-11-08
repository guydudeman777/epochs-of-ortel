class_name TownBuilder
extends RefCounted
## Builds a TownLayout at person scale: ground, streets, the square, and each piece as its walkable model where lane B
## has made one (walk_<culture>_<piece>, then walk_any_<piece>), or as a grey box of the same name until then.
## Every building stops you walking through it.

const MODELS: String = "res://assets/models/%s.glb"
## Ground, street and square colours by the people's land.
const GROUND: Dictionary[StringName, Color] = {
	&"sunborn": Color(0.62, 0.52, 0.36), &"hive": Color(0.56, 0.47, 0.34), &"rime": Color(0.62, 0.64, 0.62),
	&"ashen": Color(0.24, 0.22, 0.2), &"steppe": Color(0.47, 0.45, 0.27), &"reef": Color(0.6, 0.56, 0.44),
	&"tidebound": Color(0.24, 0.34, 0.17), &"freehold": Color(0.36, 0.36, 0.34),
}
const GRASS: Color = Color(0.3, 0.36, 0.19)
const STREET: Color = Color(0.36, 0.29, 0.21)
const SQUARE: Color = Color(0.42, 0.37, 0.3)
## Grey boxes, a little warmer or colder by people, so towns of different peoples read apart even before their art.
const WALLS: Dictionary[StringName, Color] = {
	&"sunborn": Color(0.74, 0.64, 0.5), &"hive": Color(0.6, 0.47, 0.3), &"rime": Color(0.52, 0.5, 0.48),
	&"ashen": Color(0.25, 0.23, 0.23), &"freehold": Color(0.55, 0.55, 0.53), &"veiled": Color(0.5, 0.56, 0.46),
	&"reef": Color(0.72, 0.62, 0.56), &"tidebound": Color(0.55, 0.46, 0.34),
}
const GREY: Color = Color(0.6, 0.58, 0.55)
const ROOF: Color = Color(0.36, 0.25, 0.2)
const DOOR: Color = Color(0.12, 0.08, 0.05)
const WOOD: Color = Color(0.38, 0.27, 0.17)
const SIGN: Color = Color(0.95, 0.85, 0.55)
## Kinds with a pitched roof over the box.
const ROOFED: Array[StringName] = [&"house", &"house_big", &"hall", &"tavern", &"smithy", &"workshop", &"barracks"]
const ROOF_HEIGHT: float = 2.4
const EDGE_PIECES: int = 48
const STREET_WIDTH: float = TownView.STREET_HALF_WIDTH * 2.0 * TownLayout.SCALE

static var _materials: Dictionary[Color, StandardMaterial3D] = {}


static func build(parent: Node3D, layout: TownLayout) -> void:
	_build_ground(parent, layout)
	for piece: TownLayout.Piece in layout.pieces:
		var spot_label: String = layout.spots[piece.spot].label if piece.spot >= 0 else ""
		parent.add_child(make_piece(piece, layout.culture, spot_label))
	_build_edge(parent, layout.edge)


## One piece, turned to face its door the way the layout says.
static func make_piece(piece: TownLayout.Piece, culture: StringName, spot_label: String) -> Node3D:
	var node: Node3D = _model(piece)
	if node == null:
		node = _grey_box(piece, culture)
	var direction: Vector2 = Vector2.from_angle(piece.turn)
	node.position = Vector3(piece.at.x, 0.0, piece.at.y)
	node.rotation.y = atan2(direction.x, direction.y)
	if not spot_label.is_empty():
		var plate: Label3D = Label3D.new()
		plate.text = spot_label
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.pixel_size = 0.01
		plate.font_size = 40
		plate.outline_size = 10
		plate.modulate = SIGN
		MenuStyle.style_label_3d(plate)
		plate.position = Vector3(0.0, minf(piece.size.y, 4.0) + 0.6, piece.size.z * 0.5 + 0.6)
		node.add_child(plate)
	return node


## Lane B's walkable model for this piece, if it has been made.
static func _model(piece: TownLayout.Piece) -> Node3D:
	for model: String in [piece.model, "walk_any_%s" % piece.kind]:
		var path: String = MODELS % model
		if ResourceLoader.exists(path):
			var node: Node3D = (load(path) as PackedScene).instantiate() as Node3D
			node.name = model
			return node
	return null


static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.92
		_materials[color] = m
	return _materials[color]


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, solid: bool) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material(color)
	parent.add_child(mesh)
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.position = at
		body.add_child(shape)
		parent.add_child(body)


## A plain stand-in, named for the model that will take its place.
static func _grey_box(piece: TownLayout.Piece, culture: StringName) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = piece.model
	var size: Vector3 = piece.size
	var wall: Color = WALLS.get(culture, GREY)
	match piece.kind:
		&"market_stall":
			_box(node, Vector3(size.x, 1.0, 1.0), Vector3(0.0, 0.5, 0.6), WOOD, true)
			for x: float in [-size.x * 0.5 + 0.1, size.x * 0.5 - 0.1]:
				for z: float in [-size.z * 0.5 + 0.1, size.z * 0.5 - 0.1]:
					_box(node, Vector3(0.12, size.y, 0.12), Vector3(x, size.y * 0.5, z), WOOD, false)
			_box(node, Vector3(size.x + 0.4, 0.1, size.z + 0.4), Vector3(0.0, size.y, 0.0), Color(0.55, 0.2, 0.15), false)
		&"well":
			var mesh: MeshInstance3D = MeshInstance3D.new()
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = size.x * 0.5
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			mesh.mesh = cylinder
			mesh.position.y = size.y * 0.5
			mesh.material_override = material(wall.darkened(0.2))
			node.add_child(mesh)
			_box(node, Vector3(size.x * 0.9, size.y, size.z * 0.9), Vector3(0.0, size.y * 0.5, 0.0), wall, true)
		&"pen":
			var half: float = size.x * 0.5
			_box(node, Vector3(size.x, size.y, 0.2), Vector3(0.0, size.y * 0.5, -half), WOOD, true)
			_box(node, Vector3(0.2, size.y, size.z), Vector3(-half, size.y * 0.5, 0.0), WOOD, true)
			_box(node, Vector3(0.2, size.y, size.z), Vector3(half, size.y * 0.5, 0.0), WOOD, true)
			# The front stands open but for a gate.
			_box(node, Vector3(size.x * 0.35, size.y, 0.2), Vector3(-half + size.x * 0.175, size.y * 0.5, half), WOOD, true)
			_box(node, Vector3(size.x * 0.35, size.y, 0.2), Vector3(half - size.x * 0.175, size.y * 0.5, half), WOOD, true)
		&"gate":
			var post: Vector3 = Vector3(1.2, size.y, size.z)
			_box(node, post, Vector3(-size.x * 0.5, size.y * 0.5, 0.0), wall.darkened(0.15), true)
			_box(node, post, Vector3(size.x * 0.5, size.y * 0.5, 0.0), wall.darkened(0.15), true)
			_box(node, Vector3(size.x + 1.2, 1.0, size.z), Vector3(0.0, size.y - 0.5, 0.0), wall.darkened(0.15), false)
		&"wall", &"tower":
			_box(node, size, Vector3(0.0, size.y * 0.5, 0.0), wall.darkened(0.1), true)
		_:
			_box(node, size, Vector3(0.0, size.y * 0.5, 0.0), wall, true)
			# The door, on the side that faces the street.
			_box(node, Vector3(1.4, 2.2, 0.12), Vector3(0.0, 1.1, size.z * 0.5 + 0.04), DOOR, false)
			if ROOFED.has(piece.kind):
				var roof: MeshInstance3D = MeshInstance3D.new()
				var prism: PrismMesh = PrismMesh.new()
				prism.size = Vector3(size.x + 0.8, ROOF_HEIGHT * (1.4 if piece.kind == &"hall" else 1.0), size.z + 0.8)
				roof.mesh = prism
				roof.position.y = size.y + prism.size.y * 0.5
				roof.material_override = material(ROOF)
				node.add_child(roof)
	return node


static func _build_ground(parent: Node3D, layout: TownLayout) -> void:
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2.ONE * (layout.edge * 2.0 + 200.0)
	ground.mesh = plane
	var soil: Color = GROUND.get(layout.culture, GRASS)
	ground.material_override = material(soil)
	parent.add_child(ground)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	parent.add_child(floor_body)
	var square: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = layout.square_radius
	disc.bottom_radius = layout.square_radius
	disc.height = 0.04
	disc.radial_segments = 48
	square.mesh = disc
	square.position.y = 0.02
	square.material_override = material(SQUARE)
	parent.add_child(square)
	for street: PackedVector2Array in layout.streets:
		for i: int in range(street.size() - 1):
			var a: Vector2 = street[i]
			var b: Vector2 = street[i + 1]
			if a.length() > layout.edge:
				break
			if b.length() > layout.edge:
				b = a + (b - a).normalized() * (layout.edge - a.length())
			var strip: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(STREET_WIDTH, 0.03, a.distance_to(b) + STREET_WIDTH * 0.5)
			strip.mesh = box
			var middle: Vector2 = (a + b) * 0.5
			var way: Vector2 = (b - a).normalized()
			strip.position = Vector3(middle.x, 0.025, middle.y)
			strip.rotation.y = atan2(way.x, way.y)
			strip.material_override = material(STREET)
			parent.add_child(strip)


## A ring nobody can walk through, where the town gives out.
static func _build_edge(parent: Node3D, radius: float) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TownEdge"
	var length: float = TAU * radius / float(EDGE_PIECES) * 1.1
	for i: int in range(EDGE_PIECES):
		var angle: float = float(i) / float(EDGE_PIECES) * TAU
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(length, 6.0, 1.0)
		shape.shape = box
		var point: Vector2 = Vector2.from_angle(angle) * radius
		shape.position = Vector3(point.x, 3.0, point.y)
		shape.rotation.y = atan2(point.x, point.y)
		body.add_child(shape)
	parent.add_child(body)
