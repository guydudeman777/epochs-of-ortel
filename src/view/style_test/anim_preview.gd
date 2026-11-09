extends Node3D
## Contact sheet for checking animations: one row per clip, sampled left to right over its length.
##
## godot --path . res://src/view/style_test/anim_preview.tscn --resolution 1600x1200 -- --model=body_mh --out=C:/tmp/sheet.png
## Optional: --yaw=degrees, --cols=count, --clips=walk,run. Without --out it stays open.
## --model=body_mh shows a person from FaceService. Add --sex=female, --age=0.5, --line=african, --seed=number,
## --dress=soldier, commoner or none, and --helmet for the coif and helmet. --gear=spear,shield puts that in the hands
## instead of the soldier's sword and shield, and works with any dress, so --dress=none --gear=spear shows the bare body
## holding a spear.
## --views=-90,0 draws every clip once from each of these turns, a row each. --frames=0,9,18 samples those frames (at
## 24 a second) in place of even steps. --look=hand_r,0.4 frames that bone of the first sample, this many metres high.

const ROW_GAP_RATIO: float = 1.2
const HUMAN_RACE: String = "res://content/defs/races/human.tres"

var _face: FaceData = null
var _male: bool = true
var _age: float = 0.1
var _worn: Array[String] = []
var _first: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	var model_name: String = ViewUtil.arg("model", "body_mh")
	var scene: PackedScene = load("res://assets/models/%s.glb" % model_name) as PackedScene
	var cols: int = ViewUtil.arg("cols", "6").to_int()
	var yaw: float = deg_to_rad(ViewUtil.arg("yaw", "-55").to_float())
	var is_horse: bool = model_name == "horse"
	if model_name == "body_mh":
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = ViewUtil.arg("seed", "3").to_int()
		_male = ViewUtil.arg("sex", "male") == "male"
		_age = ViewUtil.arg("age", "0.1").to_float()
		_face = FaceService.random_face(rng, load(HUMAN_RACE) as RaceDef, _male, 0.5, StringName(ViewUtil.arg("line", "caucasian")))
		match ViewUtil.arg("dress", "soldier"):
			"soldier":
				_worn.assign(BodyView.SOLDIER)
			"commoner":
				_worn.assign(BodyView.COMMONER)
		if OS.get_cmdline_user_args().has("--helmet"):
			_worn.append_array(BodyView.HELMET)
		var gear: String = ViewUtil.arg("gear", "")
		if not gear.is_empty():
			_worn.erase("sword")
			_worn.erase("shield")
			_worn.append_array(gear.split(",", false))
	var cell_w: float = 3.0 if is_horse else 1.5
	var cell_h: float = 2.5 if is_horse else 2.2
	var names: PackedStringArray = _clip_names(scene)
	var clips: String = ViewUtil.arg("clips", "")
	if not clips.is_empty():
		names = clips.split(",")
	var views: Array[float] = [yaw]
	if not ViewUtil.arg("views", "").is_empty():
		views.clear()
		for v: String in ViewUtil.arg("views", "").split(","):
			views.append(deg_to_rad(v.to_float()))
	var frames: Array[float] = []
	for f: String in ViewUtil.arg("frames", "").split(",", false):
		frames.append(f.to_float() / 24.0)
	if not frames.is_empty():
		cols = frames.size()
	var rows: int = names.size() * views.size()
	for row: int in range(rows):
		var clip: String = names[floori(float(row) / float(views.size()))]
		var y: float = (rows - 1 - row) * cell_h * ROW_GAP_RATIO
		_add_label(clip, Vector3(-cell_w * 0.9, y + 1.0, 0.0))
		for col: int in range(cols):
			var at: float = -1.0 if frames.is_empty() else frames[col]
			_add_sample(scene, clip, float(col) / float(cols), Vector3(col * cell_w, y, 0.0), views[row % views.size()], at)
	_add_stage(Vector2(cols * cell_w, rows * cell_h * ROW_GAP_RATIO), cell_w)
	var look: PackedStringArray = ViewUtil.arg("look", "").split(",", false)
	if look.size() == 2 and _first != null:
		await get_tree().process_frame
		var skeleton: Skeleton3D = ViewUtil.find_skeleton(_first)
		var bone: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(look[0])).origin
		_camera.size = look[1].to_float()
		_camera.position = Vector3(bone.x, bone.y, 30.0)
	var out_path: String = ViewUtil.arg("out", "")
	if not out_path.is_empty():
		await ViewUtil.save_shot_and_quit(self, out_path)


func _clip_names(scene: PackedScene) -> PackedStringArray:
	var probe: Node = scene.instantiate()
	var names: PackedStringArray = ViewUtil.find_player(probe).get_animation_list()
	probe.free()
	return names


func _add_sample(scene: PackedScene, clip: String, fraction: float, at: Vector3, yaw: float, time: float = -1.0) -> void:
	var instance: Node3D = scene.instantiate() as Node3D if _face == null else BodyView.make(_face, _male, _age, _worn)
	add_child(instance)
	if _first == null:
		_first = instance
	if _face != null:
		FaceView.attach(instance, _face, _male, _age)
	instance.position = at
	instance.rotation.y = yaw
	var player: AnimationPlayer = ViewUtil.find_player(instance)
	player.play(clip)
	player.seek(player.get_animation(clip).length * fraction if time < 0.0 else time, true)
	player.pause()


func _add_label(text: String, at: Vector3) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.pixel_size = 0.006
	label.font_size = 48
	label.position = at
	add_child(label)


func _add_stage(extent: Vector2, cell_w: float) -> void:
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var view: Vector2 = get_viewport().get_visible_rect().size
	camera.size = maxf(extent.y, extent.x * view.y / maxf(view.x, 1.0)) + 0.5
	camera.position = Vector3(extent.x * 0.5 - cell_w * 0.75, extent.y * 0.5, 30.0)
	add_child(camera)
	_camera = camera
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	add_child(sun)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.33, 0.35)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
