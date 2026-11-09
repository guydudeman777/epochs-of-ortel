class_name FieldStage
extends RefCounted
## Draws a BattleGround: the field's ground with collision, the land beyond it to the horizon, the water, what grows
## and stands on it, and the sky over it for the hour and the weather. It only shows; the rules of the field are in
## BattleGround.

const GROUND_SHADER: String = "res://src/view/duel/field_ground.gdshader"
const WATER_SHADER: String = "res://src/view/duel/field_water.gdshader"
const GRASS_SHADER: String = "res://src/view/duel/field_grass.gdshader"
const GROUND_ALBEDO: String = "res://assets/textures/ground/ground_albedo.png"
const GROUND_NORMAL: String = "res://assets/textures/ground/ground_normal.png"
const MODELS: String = "res://assets/models/%s.glb"
const BLADES: String = "res://assets/textures/field/%s.png"
## The layer shares ride on three custom vertex channels: four, four and two floats.
const LAYER_FORMAT: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
## Each country's grass: root, tip, and how dry it stands. By LandDef.Biome.
const GRASS_COLORS: Array[Array] = [
	[Color(0.13, 0.15, 0.07), Color(0.29, 0.32, 0.14), 0.22], [Color(0.12, 0.14, 0.09), Color(0.26, 0.29, 0.17), 0.3],
	[Color(0.22, 0.2, 0.11), Color(0.45, 0.4, 0.21), 0.75], [Color(0.08, 0.07, 0.06), Color(0.17, 0.15, 0.12), 0.9],
	[Color(0.32, 0.27, 0.16), Color(0.55, 0.47, 0.28), 0.85], [Color(0.09, 0.15, 0.05), Color(0.23, 0.34, 0.12), 0.08],
	[Color(0.15, 0.16, 0.1), Color(0.3, 0.32, 0.19), 0.35], [Color(0.45, 0.47, 0.5), Color(0.7, 0.72, 0.74), 0.4],
]
## Water by country: shallow and deep.
const WATER_COLORS: Array[Array] = [
	[Color(0.24, 0.3, 0.24), Color(0.04, 0.08, 0.09)], [Color(0.22, 0.28, 0.3), Color(0.03, 0.07, 0.1)],
	[Color(0.3, 0.32, 0.24), Color(0.05, 0.09, 0.1)], [Color(0.2, 0.18, 0.15), Color(0.05, 0.05, 0.05)],
	[Color(0.24, 0.4, 0.38), Color(0.03, 0.12, 0.16)], [Color(0.18, 0.32, 0.26), Color(0.02, 0.1, 0.1)],
	[Color(0.22, 0.32, 0.34), Color(0.03, 0.08, 0.11)], [Color(0.3, 0.36, 0.4), Color(0.05, 0.08, 0.12)],
]
## Fog by country: how thick, from the near hills to the horizon.
const FOG: Array[float] = [0.0035, 0.0045, 0.003, 0.008, 0.0035, 0.005, 0.004, 0.0055]

static var _meshes: Dictionary[String, Array] = {}


## Builds the whole field under scene, and returns the sky it made, for whoever wants to know the hour's light.
static func build(scene: Node3D, ground: BattleGround, hour: float, weather_seed: int) -> SkyDome:
	var holder: Node3D = Node3D.new()
	holder.name = "Field"
	scene.add_child(holder)
	var ground_material: ShaderMaterial = _ground_material(ground)
	_build_ground(holder, ground, ground_material)
	_build_far(holder, ground, ground_material)
	if ground.has_water:
		_build_water(holder, ground)
	_build_props(holder, ground)
	_build_grass(holder, ground)
	return _build_sky(scene, ground, hour, weather_seed)


static func _ground_material(ground: BattleGround) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(GROUND_SHADER) as Shader
	material.set_shader_parameter(&"albedo_tiles", load(GROUND_ALBEDO))
	material.set_shader_parameter(&"normal_tiles", load(GROUND_NORMAL))
	material.set_shader_parameter(&"water_level", ground.water_level if ground.has_water else -1000.0)
	return material


static func _build_ground(parent: Node3D, ground: BattleGround, material: ShaderMaterial) -> void:
	var n: int = ground.samples
	var half: float = BattleGround.SIZE * 0.5
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	var custom: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	custom[0].resize(n * n * 4)
	custom[1].resize(n * n * 4)
	custom[2].resize(n * n * 2)
	for z: int in range(n):
		for x: int in range(n):
			var i: int = x + z * n
			vertices[i] = Vector3(x * BattleGround.STEP - half, ground.heights[i], z * BattleGround.STEP - half)
			var left: float = ground.heights[i - 1] if x > 0 else ground.heights[i]
			var right: float = ground.heights[i + 1] if x < n - 1 else ground.heights[i]
			var back: float = ground.heights[i - n] if z > 0 else ground.heights[i]
			var ahead: float = ground.heights[i + n] if z < n - 1 else ground.heights[i]
			normals[i] = Vector3(left - right, 2.0 * BattleGround.STEP, back - ahead).normalized()
			for k: int in range(4):
				custom[0][i * 4 + k] = ground.layers[k][i]
				custom[1][i * 4 + k] = ground.layers[4 + k][i]
			custom[2][i * 2] = ground.layers[8][i]
			custom[2][i * 2 + 1] = ground.layers[9][i]
	var mesh: MeshInstance3D = _grid_mesh("Ground", n, vertices, normals, ground.colors, custom, material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	# The ground people and bodies stand on: a height map, scaled evenly from one sample a unit to one every STEP.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "GroundBody"
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var scaled: PackedFloat32Array = PackedFloat32Array()
	scaled.resize(n * n)
	for i: int in range(n * n):
		scaled[i] = ground.heights[i] / BattleGround.STEP
	shape.map_data = scaled
	var holder: CollisionShape3D = CollisionShape3D.new()
	holder.shape = shape
	holder.scale = Vector3.ONE * BattleGround.STEP
	body.add_child(holder)
	parent.add_child(body)


static func _build_far(parent: Node3D, ground: BattleGround, material: ShaderMaterial) -> void:
	var n: int = ground.far_samples
	var half: float = BattleGround.FAR_SIZE * 0.5
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	var custom: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	custom[0].resize(n * n * 4)
	custom[1].resize(n * n * 4)
	custom[2].resize(n * n * 2)
	var base: Dictionary = BattleGround.BIOME_LAYERS[ground.biome]
	for z: int in range(n):
		for x: int in range(n):
			var i: int = x + z * n
			vertices[i] = Vector3(x * BattleGround.FAR_STEP - half, ground.far_heights[i], z * BattleGround.FAR_STEP - half)
			var left: float = ground.far_heights[i - 1] if x > 0 else ground.far_heights[i]
			var right: float = ground.far_heights[i + 1] if x < n - 1 else ground.far_heights[i]
			var back: float = ground.far_heights[i - n] if z > 0 else ground.far_heights[i]
			var ahead: float = ground.far_heights[i + n] if z < n - 1 else ground.far_heights[i]
			normals[i] = Vector3(left - right, 2.0 * BattleGround.FAR_STEP, back - ahead).normalized()
			for layer: Variant in base:
				var k: int = layer as int
				var share: float = base[layer] as float
				if k < 4:
					custom[0][i * 4 + k] = share
				elif k < 8:
					custom[1][i * 4 + k - 4] = share
				else:
					custom[2][i * 2 + k - 8] = share
	var mesh: MeshInstance3D = _grid_mesh("Far", n, vertices, normals, ground.far_colors, custom, material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


static func _grid_mesh(mesh_name: String, n: int, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		custom: Array[PackedFloat32Array], material: Material) -> MeshInstance3D:
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var at: int = 0
	for z: int in range(n - 1):
		for x: int in range(n - 1):
			var a: int = x + z * n
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			# Split each square along whichever diagonal follows the ground better.
			if absf(vertices[a].y - vertices[d].y) < absf(vertices[b].y - vertices[c].y):
				indices[at] = a
				indices[at + 1] = b
				indices[at + 2] = d
				indices[at + 3] = a
				indices[at + 4] = d
				indices[at + 5] = c
			else:
				indices[at] = a
				indices[at + 1] = b
				indices[at + 2] = c
				indices[at + 3] = b
				indices[at + 4] = d
				indices[at + 5] = c
			at += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = custom[0]
	arrays[Mesh.ARRAY_CUSTOM1] = custom[1]
	arrays[Mesh.ARRAY_CUSTOM2] = custom[2]
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, LAYER_FORMAT)
	mesh.surface_set_material(0, material)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = mesh_name
	node.mesh = mesh
	return node


static func _build_water(parent: Node3D, ground: BattleGround) -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2.ONE * BattleGround.FAR_SIZE
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(WATER_SHADER) as Shader
	var colors: Array = WATER_COLORS[ground.biome]
	material.set_shader_parameter(&"shallow_color", colors[0] as Color)
	material.set_shader_parameter(&"deep_color", colors[1] as Color)
	plane.material = material
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Water"
	node.mesh = plane
	node.position = Vector3(0.0, ground.water_level, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Every tree, rock, house and fence, one MultiMesh for each part of each model.
static func _build_props(parent: Node3D, ground: BattleGround) -> void:
	var by_model: Dictionary[String, Array] = {}
	for prop: BattleGround.Prop in ground.props:
		if not by_model.has(prop.model):
			by_model[prop.model] = []
		by_model[prop.model].append(prop)
	var names: Array[String] = []
	names.assign(by_model.keys())
	names.sort()
	for model: String in names:
		var parts: Array = _parts_of(model)
		var placed: Array = by_model[model]
		for part: Variant in parts:
			var pair: Array = part as Array
			var mesh: Mesh = pair[0] as Mesh
			var local: Transform3D = pair[1] as Transform3D
			var many: MultiMesh = MultiMesh.new()
			many.transform_format = MultiMesh.TRANSFORM_3D
			many.mesh = mesh
			many.instance_count = placed.size()
			for i: int in range(placed.size()):
				var prop: BattleGround.Prop = placed[i] as BattleGround.Prop
				var basis: Basis = Basis(Vector3.UP, prop.turn).scaled(Vector3.ONE * prop.size)
				many.set_instance_transform(i, Transform3D(basis, prop.at - Vector3(0.0, 0.15 * prop.size, 0.0)) * local)
			var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
			node.name = model
			node.multimesh = many
			parent.add_child(node)


## The meshes a model is made of, each with where it sits in the model. Nothing for a model that is not there.
static func _parts_of(model: String) -> Array:
	if _meshes.has(model):
		return _meshes[model]
	var out: Array = []
	var path: String = MODELS % model
	if ResourceLoader.exists(path):
		var scene: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		for found: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = found as MeshInstance3D
			var local: Transform3D = Transform3D.IDENTITY
			var at: Node = mesh
			while at != null and at != scene:
				local = (at as Node3D).transform * local
				at = at.get_parent()
			out.append([mesh.mesh, local])
		scene.free()
	_meshes[model] = out
	return out


static func _build_grass(parent: Node3D, ground: BattleGround) -> void:
	var colors: Array = GRASS_COLORS[ground.biome]
	_add_blades(parent, "Grass", "field_grass", "grass_blades", ground.grass, colors[0] as Color, colors[1] as Color, colors[2] as float, 0.14)
	_add_blades(parent, "Wheat", "field_wheat", "wheat", ground.wheat, Color(0.2, 0.17, 0.08), Color(0.55, 0.47, 0.22), 0.6, 0.08)
	_add_blades(parent, "Reeds", "field_reeds", "reeds", ground.reeds, Color(0.1, 0.12, 0.06), Color(0.35, 0.36, 0.18), 0.45, 0.06)


## One kind of blades, all of them in one MultiMesh.
static func _add_blades(parent: Node3D, node_name: String, model: String, texture: String, tufts: PackedVector4Array, root: Color, tip: Color,
		dry: float, sway: float) -> void:
	if tufts.is_empty():
		return
	var parts: Array = _parts_of(model)
	if parts.is_empty():
		return
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(GRASS_SHADER) as Shader
	material.set_shader_parameter(&"blades", load(BLADES % texture) as Texture2D)
	material.set_shader_parameter(&"root_color", root)
	material.set_shader_parameter(&"tip_color", tip)
	material.set_shader_parameter(&"dry", dry)
	material.set_shader_parameter(&"sway", sway)
	material.set_shader_parameter(&"reach", BattleGround.GRASS_REACH)
	var many: MultiMesh = MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = (parts[0] as Array)[0] as Mesh
	many.instance_count = tufts.size()
	var turn: float = 0.0
	for i: int in range(tufts.size()):
		var tuft: Vector4 = tufts[i]
		turn += 2.39996
		var basis: Basis = Basis(Vector3.UP, turn).scaled(Vector3(tuft.w, tuft.w * (0.85 + fposmod(turn, 0.3)), tuft.w))
		many.set_instance_transform(i, Transform3D(basis, Vector3(tuft.x, tuft.y - 0.05, tuft.z)))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = many
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _build_sky(scene: Node3D, ground: BattleGround, hour: float, weather_seed: int) -> SkyDome:
	var dome: SkyDome = SkyDome.of_place(hour, weather_seed, ground.biome as LandDef.Biome)
	match ViewUtil.arg("weather", ""):
		"clear":
			dome.cover = 0.05
			dome.overcast = 0.0
		"cloudy":
			dome.cover = 0.6
			dome.overcast = 0.0
		"overcast":
			dome.cover = 0.5
			dome.overcast = 0.9
	var env: Environment = Environment.new()
	dome.apply(env)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.fog_enabled = true
	env.fog_density = FOG[ground.biome] * lerpf(1.0, 1.7, dome.overcast) * lerpf(1.0, 1.5, dome.night())
	env.glow_enabled = true
	env.glow_intensity = 0.35
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.name = "Sky"
	holder.environment = env
	scene.add_child(holder)
	var light: DirectionalLight3D = dome.make_light()
	light.directional_shadow_max_distance = 90.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	scene.add_child(light)
	return dome
