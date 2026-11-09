class_name TownBuilder
extends RefCounted
## Builds a TownLayout at person scale: the ground, each piece as its walkable model where lane B has made one
## (walk_<culture>_<piece>, then walk_any_<piece>) or as a grey box of the same name until then, and what lies about.
## Every building stops you walking through it, and all of it wears the town's material (TownSurfaces).
##
## The buildings people use (the spots, the hall, the gate) are each a scene of their own. The many homes, walls and
## towers, and every prop, are drawn many at once (one MultiMesh per part of a model), with their collision gathered
## into one body, so a town of a hundred and fifty houses draws in a few dozen calls.

const MODELS: String = "res://assets/models/%s.glb"
const BANNER_SHADER: Shader = preload("res://src/view/town/banner.gdshader")
const GREY: Color = Color(0.6, 0.58, 0.55)
## Grey boxes, a little warmer or colder by people, so towns of different peoples read apart even before their art.
const WALLS: Dictionary[StringName, Color] = {
	&"sunborn": Color(0.74, 0.64, 0.5), &"hive": Color(0.6, 0.47, 0.3), &"rime": Color(0.52, 0.5, 0.48),
	&"ashen": Color(0.25, 0.23, 0.23), &"freehold": Color(0.55, 0.55, 0.53), &"veiled": Color(0.5, 0.56, 0.46),
	&"reef": Color(0.72, 0.62, 0.56), &"tidebound": Color(0.55, 0.46, 0.34),
}
const ROOF: Color = Color(0.36, 0.25, 0.2)
const DOOR: Color = Color(0.12, 0.08, 0.05)
const WOOD: Color = Color(0.38, 0.27, 0.17)
const SIGN: Color = Color(0.95, 0.85, 0.55)
## Kinds with a pitched roof over the box.
const ROOFED: Array[StringName] = [&"house", &"house_big", &"hall", &"tavern", &"smithy", &"workshop", &"barracks", &"row", &"tall"]
const ROOF_HEIGHT: float = 2.4
const EDGE_PIECES: int = 48
## Roofs collide only with the camera arm, never with people (as TownScene.ROOF_LAYER).
const ROOF_LAYER: int = 2
## Kinds that are each their own scene, never drawn many at once.
const ALONE: Array[StringName] = [&"hall", &"gate"]
## How worn and how often lit after dark each quarter's homes are.
const WORN: Dictionary[StringName, float] = {&"poor": 0.95, &"craft": 0.7, &"common": 0.5, &"market": 0.4, &"rich": 0.12}
const LIT: Dictionary[StringName, float] = {&"poor": 0.3, &"craft": 0.45, &"common": 0.5, &"market": 0.6, &"rich": 0.75}
## Lights with a lamp inside them, which would shadow their own light; and things too thin to cast a shadow worth it.
const NO_SHADOW: Array[String] = ["walk_prop_lamp", "walk_prop_lantern", "walk_prop_torch"]

## A model's drawn parts and collision, each placed in the model's own space.
class Template:
	var meshes: Array[Mesh] = []
	var names: Array[String] = []
	var mesh_places: Array[Transform3D] = []
	var roof: Array[bool] = []
	var roof_shapes: Array[Shape3D] = []
	var shapes: Array[Shape3D] = []
	var shape_places: Array[Transform3D] = []

static var _materials: Dictionary[Color, StandardMaterial3D] = {}
static var _templates: Dictionary[String, Template] = {}
## The realm whose arms the town's banners show, set before the town is built.
static var arms: FactionData = null


## A banner's cloth in the realm's arms, fitted to where the cloth hangs in its model.
static func banner_material(cloth: Mesh) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BANNER_SHADER
	var box: AABB = cloth.get_aabb()
	material.set_shader_parameter(&"cloth_box", Vector4(box.position.x, box.end.x, box.end.y, box.position.y))
	material.set_shader_parameter(&"field_color", Heraldry.field(arms))
	material.set_shader_parameter(&"charge_color", Heraldry.charge_color(arms))
	material.set_shader_parameter(&"charge", int(Heraldry.charge(arms)))
	return material


## Builds the whole town, and gives back each piece's node, in the layout's order. A piece drawn with others has an
## empty node where it stands.
static func build(parent: Node3D, layout: TownLayout) -> Array[Node3D]:
	TownGround.build(parent, layout)
	var nodes: Array[Node3D] = []
	var many: Dictionary[String, Array] = {}
	for piece: TownLayout.Piece in layout.pieces:
		var look: Color = look_of(piece)
		if piece.has_model and piece.spot < 0 and not ALONE.has(piece.kind):
			var stand: Node3D = Node3D.new()
			stand.name = "%s_%d" % [piece.model, nodes.size()]
			stand.position = Vector3(piece.at.x, 0.0, piece.at.y)
			parent.add_child(stand)
			nodes.append(stand)
			if not many.has(piece.model):
				many[piece.model] = []
			var place: Transform3D = place_of(piece.at, piece.turn, 1.0)
			if piece.stretch != 1.0:
				# A length cut to fit is drawn shorter; the water's edge stops walkers there instead of its own walls.
				place.basis = place.basis * Basis.from_scale(Vector3(piece.stretch, 1.0, 1.0))
			many[piece.model].append([place, look, piece.stretch == 1.0])
			continue
		var spot_label: String = layout.spots[piece.spot].label if piece.spot >= 0 else ""
		var node: Node3D = make_piece(piece, layout.culture, spot_label)
		if piece.has_model:
			TownSurfaces.dress(node, look)
		parent.add_child(node)
		nodes.append(node)
	_draw_many(parent, many, "Homes")
	var props: Dictionary[String, Array] = {}
	for prop: TownLayout.Prop in layout.props:
		if not props.has(prop.model):
			props[prop.model] = []
		var tint: float = fposmod(sin(prop.at.x * 12.9898 + prop.at.y * 78.233) * 43758.5453, 1.0)
		props[prop.model].append([place_of(prop.at, prop.turn, prop.scale, prop.lift), Color(tint, 0.6, 0.0, 0.0)])
	_draw_many(parent, props, "Props")
	_build_edge(parent, layout.edge)
	return nodes


## A piece's own look: its tint, how worn it is, and the share of its windows lit at night, the same each time.
static func look_of(piece: TownLayout.Piece) -> Color:
	var tint: float = fposmod(sin(piece.at.x * 12.9898 + piece.at.y * 78.233) * 43758.5453, 1.0)
	var worn: float = WORN.get(piece.quarter, 0.3) as float
	var lit: float = LIT.get(piece.quarter, 0.85 if piece.spot >= 0 else 0.4) as float
	return Color(tint, worn, lit, 0.0)


static func place_of(at: Vector2, turn: float, size: float, lift: float = 0.0) -> Transform3D:
	var direction: Vector2 = Vector2.from_angle(turn)
	var basis: Basis = Basis(Vector3.UP, atan2(direction.x, direction.y)).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(at.x, lift, at.y))


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
		plate.position = Vector3(0.0, minf(piece.high.y, 4.0) + 0.6, piece.high.z + 0.6)
		node.add_child(plate)
	return node


## Lane B's walkable model for this piece, if the layout found one. Its collision comes with it.
static func _model(piece: TownLayout.Piece) -> Node3D:
	if not piece.has_model:
		return null
	var node: Node3D = (load(MODELS % piece.model) as PackedScene).instantiate() as Node3D
	node.name = piece.model
	return node


## The roof of a building drawn from lane B's model, to hide while you are inside, or null.
static func roof_of(node: Node3D, piece: TownLayout.Piece) -> Node3D:
	if piece.roof.is_empty():
		return null
	return node.find_child(piece.roof, true, false) as Node3D


## A model's parts, read once from its scene.
static func template(model: String) -> Template:
	if _templates.has(model):
		return _templates[model]
	var out: Template = Template.new()
	var scene: Node3D = (load(MODELS % model) as PackedScene).instantiate() as Node3D
	for found: Node in scene.find_children("*", "", true, false):
		if not found is Node3D:
			continue
		var place: Transform3D = _place_in(found as Node3D, scene)
		if found is MeshInstance3D and (found as MeshInstance3D).mesh != null:
			var mesh: Mesh = (found as MeshInstance3D).mesh
			out.meshes.append(mesh)
			out.names.append(String(found.name))
			out.mesh_places.append(place)
			var is_roof: bool = String(found.name).ends_with("_roof")
			out.roof.append(is_roof)
			out.roof_shapes.append(mesh.create_trimesh_shape() if is_roof else null)
		elif found is CollisionShape3D and (found as CollisionShape3D).shape != null:
			out.shapes.append((found as CollisionShape3D).shape)
			out.shape_places.append(place)
	scene.free()
	_templates[model] = out
	return out


static func _place_in(node: Node3D, root: Node3D) -> Transform3D:
	var place: Transform3D = Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			place = (at as Node3D).transform * place
		at = at.get_parent()
	return place


## Every copy of each model at once: a MultiMesh for each of its parts, its walls and blocks gathered into one body,
## and its roofs into another that only the camera bumps into. A prop with no collision of its own gets a box if the
## manifest calls it solid.
static func _draw_many(parent: Node3D, many: Dictionary[String, Array], label: String) -> void:
	var group: Node3D = Node3D.new()
	group.name = label
	parent.add_child(group)
	var solids: StaticBody3D = StaticBody3D.new()
	solids.name = label + "Solids"
	group.add_child(solids)
	var roofs: StaticBody3D = StaticBody3D.new()
	roofs.name = label + "Roofs"
	roofs.collision_layer = ROOF_LAYER
	roofs.collision_mask = 0
	group.add_child(roofs)
	var models: Array[String] = many.keys()
	models.sort()
	for model: String in models:
		if not ResourceLoader.exists(MODELS % model):
			push_warning("No model %s yet; build and import the walk pieces." % model)
			continue
		var copies: Array = many[model]
		var made: Template = template(model)
		for part: int in range(made.meshes.size()):
			var multi: MultiMesh = MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_custom_data = true
			multi.mesh = made.meshes[part]
			multi.instance_count = copies.size()
			for i: int in range(copies.size()):
				var place: Transform3D = copies[i][0] as Transform3D
				multi.set_instance_transform(i, place * made.mesh_places[part])
				multi.set_instance_custom_data(i, copies[i][1] as Color)
				if made.roof[part]:
					var roof_shape: CollisionShape3D = CollisionShape3D.new()
					roof_shape.shape = made.roof_shapes[part]
					roof_shape.transform = place * made.mesh_places[part]
					roofs.add_child(roof_shape)
			var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
			node.name = "%s_%d" % [model, part]
			node.multimesh = multi
			node.material_override = TownSurfaces.material()
			if made.names[part].ends_with("_cloth"):
				node.material_override = banner_material(made.meshes[part])
			if NO_SHADOW.has(model):
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.add_child(node)
		var box: BoxShape3D = null
		if made.shapes.is_empty():
			var known: Dictionary = TownLayout.manifest().get(model, {}) as Dictionary
			if known.get("solid", false) as bool:
				var bounds: Dictionary = known["bounds"] as Dictionary
				var low: Array = bounds["min"] as Array
				var high: Array = bounds["max"] as Array
				box = BoxShape3D.new()
				box.size = Vector3((high[0] as float) - (low[0] as float), (high[1] as float) - (low[1] as float), (high[2] as float) - (low[2] as float)) * Vector3(0.8, 1.0, 0.8)
				made.shapes.append(box)
				made.shape_places.append(Transform3D(Basis.IDENTITY, Vector3(((low[0] as float) + (high[0] as float)) * 0.5, box.size.y * 0.5, ((low[2] as float) + (high[2] as float)) * 0.5)))
		for i: int in range(copies.size()):
			var place: Transform3D = copies[i][0] as Transform3D
			var copy: Array = copies[i] as Array
			if copy.size() > 2 and not (copy[2] as bool):
				continue
			for s: int in range(made.shapes.size()):
				var shape: CollisionShape3D = CollisionShape3D.new()
				shape.shape = made.shapes[s]
				shape.transform = place * made.shape_places[s]
				solids.add_child(shape)


## Where smoke rises: each chimney of the town's homes and spots, and of the smoke huts and furnaces lying about, on
## the town's ground, with its height.
static func chimneys(layout: TownLayout) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for piece: TownLayout.Piece in layout.pieces:
		if not piece.has_mark("smoke"):
			continue
		var mark: TownLayout.Mark = piece.mark("smoke")
		out.append(Vector3(mark.at.x, mark.height, mark.at.y))
	for prop: TownLayout.Prop in layout.props:
		var marks: Dictionary = (TownLayout.manifest().get(prop.model, {}) as Dictionary).get("marks", {}) as Dictionary
		if not marks.has("smoke"):
			continue
		var point: Array = (marks["smoke"] as Dictionary)["at"] as Array
		var at: Vector2 = TownLights.place(prop.at, prop.turn, prop.scale, Vector2(point[0] as float, point[2] as float))
		out.append(Vector3(at.x, prop.lift + (point[1] as float) * prop.scale, at.y))
	return out


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
			# A hair lower than the drum, so their tops never share a plane.
			_box(node, Vector3(size.x * 0.9, size.y - 0.03, size.z * 0.9), Vector3(0.0, (size.y - 0.03) * 0.5, 0.0), wall, true)
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
			# The lintel stands a hair proud of the posts on every side, so no face lies on theirs.
			_box(node, Vector3(size.x + 1.24, 1.02, size.z + 0.04), Vector3(0.0, size.y - 0.49, 0.0), wall.darkened(0.15), false)
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


## A ring nobody can walk through, where the town gives out, and the floor under it all.
static func _build_edge(parent: Node3D, radius: float) -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	parent.add_child(floor_body)
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
