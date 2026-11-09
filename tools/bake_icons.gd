extends SceneTree
## Bakes the picture of every garment and weapon from the real models into assets/icons, for the inventory's slots.
## Each is drawn alone on a body nobody sees, in the pose people stand in, framed to fit, lit warm from the front
## and cool from behind, on a clear ground. Run with a window, as it draws:
##
## godot --path . --script res://tools/bake_icons.gd
## Then import (godot --headless --path . --import). --only=id,id bakes those.

const SIZE: int = 160
const GARMENT_DIR: String = "res://content/defs/armours"
const OUT_GARMENTS: String = "res://assets/icons/garments/%s.png"
const OUT_WEAPONS: String = "res://assets/icons/weapons/%s.png"
const FRAMES: int = 4

var _stage: SubViewport
var _camera: Camera3D
var _human: FaceData
var _kheth: FaceData


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons/garments"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons/weapons"))
	_build_stage()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	_human = FaceService.random_face(rng, load("res://content/defs/races/human.tres") as RaceDef, true, 0.5, &"caucasian")
	_kheth = FaceService.random_face(rng, load("res://content/defs/races/kheth.tres") as RaceDef, true, 0.5)
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	var made: int = 0
	for file_name: String in ResourceLoader.list_directory(GARMENT_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var def: GarmentDef = load(GARMENT_DIR + "/" + file_name) as GarmentDef
		if def == null or def.model.is_empty() or (not only.is_empty() and not only.has(String(def.id))):
			continue
		var gear: EquipmentData = EquipmentData.new()
		gear.armour_ids.assign([def.id])
		var worn: Array[String] = BodyView.worn_for(gear, 7)
		worn.erase(BodyView.SMALLCLOTHES)
		var face: FaceData = _kheth if def.race_ids.has(&"kheth") else _human
		await _shoot(face, worn, OUT_GARMENTS % String(def.id), def.slot)
		made += 1
	for weapon: StringName in BodyView.WEAPON_PARTS:
		if only.is_empty() or only.has(String(weapon)):
			await _shoot(_human, [BodyView.WEAPON_PARTS[weapon]] as Array[String], OUT_WEAPONS % String(weapon), &"weapon")
			made += 1
	if only.is_empty() or only.has("shield"):
		await _shoot(_human, ["shield"] as Array[String], OUT_WEAPONS % "shield", &"shield")
		made += 1
	print("ICONS baked %d" % made)
	quit(0)


func _build_stage() -> void:
	_stage = SubViewport.new()
	_stage.size = Vector2i(SIZE, SIZE)
	_stage.own_world_3d = true
	_stage.transparent_bg = true
	_stage.msaa_3d = Viewport.MSAA_8X
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_stage)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, 28.0, 0.0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.15
	_stage.add_child(key)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	rim.light_color = Color(0.62, 0.7, 0.95)
	rim.light_energy = 0.8
	_stage.add_child(rim)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60.0, -70.0, 0.0)
	fill.light_color = Color(1.0, 0.85, 0.7)
	fill.light_energy = 0.3
	_stage.add_child(fill)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.6, 0.56)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.sky = PortraitView.studio_sky()
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	_stage.add_child(holder)
	_camera = Camera3D.new()
	_camera.fov = 18.0
	_stage.add_child(_camera)


## Draws what is worn on a body that does not show, frames it and saves the picture.
func _shoot(face: FaceData, worn: Array[String], path: String, slot: StringName) -> void:
	var body: Node3D = BodyView.make(face, true, 0.3, worn)
	_stage.add_child(body)
	for part: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		if BodyView.BODY_PARTS.has(String(mesh.name)) or String(mesh.name) == BodyView.CROWD_HAIR:
			mesh.visible = false
	if body.has_meta(BodyView.FORM_BODY_META):
		(body.get_meta(BodyView.FORM_BODY_META) as Node3D).visible = false
	# Gear stands as people stand, a little turned, so its depth shows. What is held stays as the body was built, since
	# the frame is worked out from the meshes as they rest and a hand moves its weapon a long way from there.
	if slot != &"weapon" and slot != &"shield":
		ViewUtil.play(body, &"idle_unarmed", true)
	# Gloves side on, so the two hands lie one behind the other and fill the picture.
	body.rotation_degrees.y = 24.0
	if slot == &"weapon" or slot == &"shield":
		body.rotation_degrees.y = -60.0
	elif slot == &"hands":
		body.rotation_degrees.y = 80.0
	await process_frame
	var box: AABB = AABB()
	var first: bool = true
	for part: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var shown: AABB = mesh.global_transform * mesh.get_aabb()
		box = shown if first else box.merge(shown)
		first = false
	var centre: Vector3 = box.get_center()
	var reach: float = maxf(maxf(box.size.x, box.size.y), box.size.z * 0.8) * 0.5
	var distance: float = reach / tan(deg_to_rad(_camera.fov * 0.5)) * 1.12
	_camera.look_at_from_position(centre + Vector3(0.0, reach * 0.15, distance), centre, Vector3.UP)
	for _i: int in range(FRAMES):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _stage.get_texture().get_image()
	var error: Error = image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		print("ICONS failed %s" % path)
	_stage.remove_child(body)
	body.free()
