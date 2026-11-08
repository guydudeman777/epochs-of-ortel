extends Control
## Shows the buildings of one people from all round: one column for each model, one row for each side it is seen from.
##
## godot --path . res://src/view/style_test/town_preview.tscn --resolution 1800x1050 -- --kit=reef --out=C:/tmp/reef.png
## --kit=<culture id> shows that people's map kit (reef, hive, hallowed, ...). --kit=walk:<culture> (or walk:any) shows
## the walkable pieces from assets/models/walk_manifest.json. --roofs=off takes the roofs off to see inside, --high=on
## looks down from high up, and --turns=0,90,180,270 picks the sides.

const MODEL_PATH: String = "res://assets/models/%s.glb"
const MANIFEST_PATH: String = "res://assets/models/walk_manifest.json"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var kit: String = ViewUtil.arg("kit", "reef")
	var models: Array[String] = _walk_models(kit.trim_prefix("walk:")) if kit.begins_with("walk:") else _kit_models(StringName(kit))
	var turns: PackedFloat64Array = ViewUtil.arg("turns", "20,110,200,290").split_floats(",", false)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.06, 0.06, 0.065)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var grid: GridContainer = GridContainer.new()
	grid.columns = maxi(models.size(), 1)
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid)
	for turn: float in turns:
		for model: String in models:
			_add_view(grid, model, turn)
	var out_path: String = ViewUtil.arg("out", "")
	if not out_path.is_empty():
		await ViewUtil.save_shot_and_quit(self, out_path)


func _kit_models(culture_id: StringName) -> Array[String]:
	var kit: TownView.Kit = TownView.kit_for(culture_id)
	var out: Array[String] = []
	for model: String in [kit.small, kit.big, kit.seat, kit.low_wall, kit.high_wall, kit.low_tower, kit.high_tower]:
		if not out.has(model):
			out.append(model)
	return out


func _walk_models(culture: String) -> Array[String]:
	var out: Array[String] = []
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	var manifest: Variant = JSON.parse_string(text)
	if not manifest is Dictionary:
		push_error("No walk manifest at %s" % MANIFEST_PATH)
		return out
	var pieces: Dictionary = (manifest as Dictionary).get("pieces", {})
	var names: Array = pieces.keys()
	names.sort()
	for model: Variant in names:
		var model_name: String = str(model)
		if model_name.begins_with("walk_%s_" % culture):
			out.append(model_name)
	return out


func _add_view(grid: GridContainer, model: String, turn: float) -> void:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_child(cell)
	var holder: SubViewportContainer = SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.add_child(holder)
	var world: SubViewport = SubViewport.new()
	world.own_world_3d = true
	world.msaa_3d = Viewport.MSAA_4X
	holder.add_child(world)
	var label: Label = Label.new()
	label.text = "%s  %d°" % [model, roundi(turn)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)
	var scene: PackedScene = load(MODEL_PATH % model) as PackedScene
	if scene == null:
		push_error("No model %s" % model)
		return
	var body: Node3D = scene.instantiate() as Node3D
	world.add_child(body)
	if ViewUtil.arg("roofs", "on") == "off":
		for node: Node in body.find_children("*_roof", "Node3D", true, false):
			(node as Node3D).visible = false
	var box: AABB = _bounds(body)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(box.size.x, box.size.z) * 1.6 + Vector2(8.0, 8.0)
	ground.mesh = plane
	var dirt: StandardMaterial3D = StandardMaterial3D.new()
	dirt.albedo_color = Color(0.27, 0.25, 0.2)
	ground.material_override = dirt
	ground.position = Vector3(box.get_center().x, -0.02, box.get_center().z)
	world.add_child(ground)
	_add_lighting(world, box.size.length())
	var camera: Camera3D = Camera3D.new()
	camera.fov = 32.0
	world.add_child(camera)
	var high: bool = ViewUtil.arg("high", "off") == "on"
	var radius: float = box.size.length() * 0.5
	var distance: float = radius / sin(deg_to_rad(camera.fov * 0.5)) * 1.05
	var pitch: float = deg_to_rad(62.0 if high else 22.0)
	var yaw: float = deg_to_rad(turn)
	var aim: Vector3 = box.get_center()
	# A model's door faces +Z, so the first view, at turn 0, looks at its front.
	var offset: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at_from_position(aim + offset, aim, Vector3.UP)


func _bounds(root: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not mesh.visible:
			continue
		var local: AABB = mesh.global_transform * mesh.get_aabb() if mesh.is_inside_tree() else mesh.transform * mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


func _add_lighting(world: SubViewport, reach: float) -> void:
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	key.light_color = Color(1.0, 0.88, 0.76)
	key.light_energy = 1.1
	key.shadow_enabled = true
	key.directional_shadow_max_distance = reach * 3.0
	world.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -130.0, 0.0)
	fill.light_color = Color(0.7, 0.76, 0.9)
	fill.light_energy = 0.3
	world.add_child(fill)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.36, 0.4, 0.46)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.58, 0.62, 0.72)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
