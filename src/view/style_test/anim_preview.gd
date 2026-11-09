extends Node3D
## Contact sheet for checking animations: one row per clip, sampled left to right over its length.
##
## godot --path . res://src/view/style_test/anim_preview.tscn --resolution 1600x1200 -- --model=body_mh --out=C:/tmp/sheet.png
## Optional: --yaw=degrees, --cols=count, --clips=walk,run. Without --out it stays open.
## --model=body_mh shows a person from FaceService. Add --sex=female, --age=0.5, --line=african, --seed=number,
## --dress=soldier, commoner or none, and --helmet for the coif and helmet. --gear=spear,shield puts that in the hands
## instead of the soldier's sword and shield, and works with any dress, so --dress=none --gear=spear shows the bare body
## holding a spear.

const ROW_GAP_RATIO: float = 1.2
const HUMAN_RACE: String = "res://content/defs/races/human.tres"

var _face: FaceData = null
var _male: bool = true
var _age: float = 0.1
var _worn: Array[String] = []


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
	for row: int in range(names.size()):
		var y: float = (names.size() - 1 - row) * cell_h * ROW_GAP_RATIO
		_add_label(names[row], Vector3(-cell_w * 0.9, y + 1.0, 0.0))
		for col: int in range(cols):
			_add_sample(scene, names[row], float(col) / float(cols), Vector3(col * cell_w, y, 0.0), yaw)
	_add_stage(Vector2(cols * cell_w, names.size() * cell_h * ROW_GAP_RATIO), cell_w)
	var out_path: String = ViewUtil.arg("out", "")
	if not out_path.is_empty():
		await ViewUtil.save_shot_and_quit(self, out_path)


func _clip_names(scene: PackedScene) -> PackedStringArray:
	var probe: Node = scene.instantiate()
	var names: PackedStringArray = ViewUtil.find_player(probe).get_animation_list()
	probe.free()
	return names


func _add_sample(scene: PackedScene, clip: String, fraction: float, at: Vector3, yaw: float) -> void:
	var instance: Node3D = scene.instantiate() as Node3D if _face == null else BodyView.make(_face, _male, _age, _worn)
	add_child(instance)
	if _face != null:
		FaceView.attach(instance, _face, _male, _age)
	instance.position = at
	instance.rotation.y = yaw
	var player: AnimationPlayer = ViewUtil.find_player(instance)
	player.play(clip)
	player.seek(player.get_animation(clip).length * fraction, true)
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
