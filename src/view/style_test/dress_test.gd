extends Control
## Clothes as people of the world wear them, to judge the wardrobe by: peoples poor to rich, soldiers by rank in their
## realm's colours, one garment up close, and a person before and after their fortune changes.
##
## godot --path . res://src/view/style_test/dress_test.tscn --resolution 1800x1000 -- --out=C:/tmp/dress.png
## --view=people (default) --cultures=hallowed,sunborn,rime: a row each, poor, middling and rich, women and men.
## --view=soldiers --culture=hallowed --realm=Name: troop kits from recruit to knight, in the realm's arms.
## --view=close --garment=id --tier=0..4: one garment on a man and a woman, front and back, up close.
## --view=fortune --culture=id: the same people poor and then rich, as WardrobeSystem re-dresses them.
## --turn=degrees turns everyone; --zoom=factor; --seed=number.

const RACE_PATH: String = "res://content/defs/races/%s.tres"
const LINES: Array[StringName] = [&"caucasian", &"asian", &"african"]
const SPACING: float = 0.82
## Wealth shown for the poor, the middling and the rich.
const FORTUNES: Array[int] = [Outfits.POOR, Outfits.COMMON, Outfits.NOBLE]
const FORTUNE_NAMES: Array[String] = ["poor", "middling", "rich"]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _defs: DefCatalog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = ViewUtil.arg("seed", "7").to_int()
	_defs = DefCatalog.new()
	_defs.load_all("res://content/defs")
	var back: ColorRect = ColorRect.new()
	back.color = Color(0.07, 0.065, 0.06)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	match ViewUtil.arg("view", "people"):
		"soldiers":
			_show_soldiers()
		"close":
			_show_close()
		"fortune":
			_show_fortune()
		_:
			_show_people()
	var out_path: String = ViewUtil.arg("out", "")
	if not out_path.is_empty():
		for _i: int in range(20):
			await get_tree().process_frame
		var began: int = Time.get_ticks_usec()
		for _i: int in range(60):
			await get_tree().process_frame
		print("DRESS frame %.2f ms" % (float(Time.get_ticks_usec() - began) / 60000.0))
		await ViewUtil.save_shot_and_quit(self, out_path)


func _rows(count: int) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 2)
	add_child(column)
	return column


func _show_people() -> void:
	var cultures: PackedStringArray = ViewUtil.arg("cultures", "hallowed,sunborn,rime").split(",")
	var column: VBoxContainer = _rows(cultures.size())
	for culture: String in cultures:
		var race: StringName = _defs.cultures[StringName(culture)].primary_race if _defs.cultures.has(StringName(culture)) else &"human"
		var world: SubViewport = _stage(column, "%s: poor, middling and rich" % culture)
		var i: int = 0
		for f: int in range(FORTUNES.size()):
			for male: bool in [false, true]:
				var gear: EquipmentData = EquipmentData.new()
				gear.armour_ids = Outfits.outfit(_defs, StringName(culture), race, male, FORTUNES[f], &"", i * 13 + 5)
				_person(world, race, male, gear, i, 6, "%s %s" % [FORTUNE_NAMES[f], "man" if male else "woman"], FORTUNES[f], null)
				i += 1
		_light(world)
		_frame(world, 6, 1.0)


func _show_soldiers() -> void:
	var culture: StringName = StringName(ViewUtil.arg("culture", "hallowed"))
	var realm: FactionData = FactionData.new()
	realm.display_name = ViewUtil.arg("realm", "Kingdom of Aldmere")
	var troops: PackedStringArray = ViewUtil.arg("troops", "levy_spearman,archer,man_at_arms,pikeman,plate_knight").split(",")
	var column: VBoxContainer = _rows(1)
	var world: SubViewport = _stage(column, "%s soldiers of %s, recruit to knight" % [culture, realm.display_name])
	for i: int in range(troops.size()):
		var troop: TroopDef = _defs.troops.get(StringName(troops[i]), null)
		if troop == null:
			continue
		var gear: EquipmentData = EquipmentData.new()
		gear.armour_ids = Outfits.troop_outfit(_defs, troop, culture, true, &"human", i)
		gear.weapon_id = troop.weapon_id
		gear.has_shield = troop.has_shield
		_person(world, &"human", true, gear, i, troops.size(), troop.display_name, Outfits.COMMON, realm)
	_light(world)
	_frame(world, troops.size(), 1.0)


func _show_close() -> void:
	var id: StringName = StringName(ViewUtil.arg("garment", "tunic"))
	var tier: int = ViewUtil.arg("tier", "2").to_int()
	var column: VBoxContainer = _rows(1)
	var world: SubViewport = _stage(column, "%s, tier %d, front and back" % [id, tier])
	var under: Array[StringName] = [&"braies", &"shirt", &"trousers", &"turnshoes", &"belt"]
	for i: int in range(4):
		var male: bool = i % 2 == 1
		var gear: EquipmentData = EquipmentData.new()
		for u: StringName in under:
			if _defs.armours.has(u):
				Outfits.put_on(_defs, gear.armour_ids, u)
		Outfits.put_on(_defs, gear.armour_ids, id)
		var body: Node3D = _person(world, &"human", male, gear, i, 4, "", tier, null)
		if i >= 2:
			body.rotation_degrees.y += 180.0
	_light(world)
	_frame(world, 4, 0.75)


func _show_fortune() -> void:
	var culture: StringName = StringName(ViewUtil.arg("culture", "hallowed"))
	var race: StringName = _defs.cultures[culture].primary_race if _defs.cultures.has(culture) else &"human"
	var column: VBoxContainer = _rows(1)
	var world: SubViewport = _stage(column, "%s: the same people poor, then rich" % culture)
	var i: int = 0
	for who: int in range(3):
		var male: bool = who != 1
		var seed_face: int = _rng.randi()
		for tier: int in [Outfits.POOR, Outfits.NOBLE]:
			var gear: EquipmentData = EquipmentData.new()
			gear.armour_ids = Outfits.outfit(_defs, culture, race, male, tier, &"", who * 31 + 3)
			_rng.seed = seed_face
			_person(world, race, male, gear, i, 6, "%s, %s" % ["before" if tier == Outfits.POOR else "after", Outfits.TIER_NAMES[tier]], tier, null)
			i += 1
	_light(world)
	_frame(world, 6, 1.0)


func _stage(column: VBoxContainer, title: String) -> SubViewport:
	var holder: SubViewportContainer = SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(holder)
	var world: SubViewport = SubViewport.new()
	world.own_world_3d = true
	world.msaa_3d = Viewport.MSAA_4X
	holder.add_child(world)
	var label: Label = Label.new()
	label.text = title
	label.add_theme_font_size_override(&"font_size", 15)
	label.add_theme_color_override(&"font_color", Color(0.75, 0.7, 0.6))
	label.position = Vector2(10.0, 4.0)
	holder.add_child(label)
	return world


func _person(world: SubViewport, race_id: StringName, male: bool, gear: EquipmentData, index: int, count: int, title: String, tier: int,
		realm: FactionData) -> Node3D:
	var race: RaceDef = load(RACE_PATH % race_id) as RaceDef
	var face: FaceData = FaceService.random_face(_rng, race, male, 0.5, LINES[index % LINES.size()] if race_id == &"human" else &"")
	var worn: Array[String] = BodyView.worn_for(gear, index * 7 + 1, realm, tier)
	var body: Node3D = BodyView.make(face, male, 0.25, worn)
	world.add_child(body)
	body.position.x = (index - (count - 1) * 0.5) * SPACING
	body.rotation_degrees.y = ViewUtil.arg("turn", "12").to_float()
	var head: Node3D = FaceView.attach(body, face, male, 0.25)
	if BodyView.hides_hair(worn) and head != null and not BodyView.has_own_body(face):
		FaceView.hide_hair(head)
	ViewUtil.play(body, BodyView.kit_clip(ViewUtil.find_player(body), &"idle", worn) if gear.weapon_id != &"" else &"idle_unarmed", true)
	if not title.is_empty():
		var label: Label3D = Label3D.new()
		label.text = title
		label.pixel_size = 0.002
		label.font_size = 34
		label.outline_size = 8
		label.modulate = Color(0.9, 0.85, 0.75)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(body.position.x, 2.0, 0.0)
		world.add_child(label)
	return body


func _light(world: SubViewport) -> void:
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 32.0, 0.0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 14.0
	world.add_child(key)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12.0, 200.0, 0.0)
	rim.light_color = Color(0.62, 0.7, 0.95)
	rim.light_energy = 0.55
	# The rim lights people, not the floor.
	rim.light_cull_mask = 1
	world.add_child(rim)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	var ground: StandardMaterial3D = StandardMaterial3D.new()
	ground.albedo_color = Color(0.11, 0.1, 0.09)
	ground.roughness = 0.95
	floor_mesh.material_override = ground
	floor_mesh.layers = 2
	world.add_child(floor_mesh)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.075, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.6, 0.58)
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.12
	environment.ssao_intensity = 1.5
	environment.sky = PortraitView.studio_sky()
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# The floor fades into the dark behind, with no line where it ends.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.08, 0.075, 0.07)
	environment.fog_density = 0.06
	environment.fog_sky_affect = 0.0
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)


func _frame(world: SubViewport, count: int, rise: float) -> void:
	var camera: Camera3D = Camera3D.new()
	camera.fov = 24.0
	world.add_child(camera)
	var width: float = maxf(float(count) * SPACING, 1.6)
	var distance: float = width * 0.5 / tan(deg_to_rad(12.0)) * 0.62 * ViewUtil.arg("zoom", "1").to_float()
	var at: float = {"feet": 0.3, "head": 1.6, "chest": 1.3}.get(ViewUtil.arg("focus", ""), rise) as float
	camera.look_at_from_position(Vector3(0.0, at + 0.1, maxf(distance, 2.2)), Vector3(0.0, at, 0.0), Vector3.UP)
