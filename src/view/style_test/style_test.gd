extends Node3D
## Throwaway scene that settles the visual style: terrain, a walled village, soldiers, riders
## and the final lighting. It reads nothing from the simulation.
##
## Controls: 1-5 camera presets, right-drag orbit, wheel zoom, arrow keys pan.
## Screenshot: godot --path . res://src/view/style_test/style_test.tscn --resolution 1920x1080 -- --cam=1 --out=C:/tmp/shot.png
## Add --settle=seconds to let it run first and print frame rate and render stats.

const MODELS: String = "res://assets/models/%s.glb"
const WORLD_SIZE: float = 560.0
const CELL: float = 2.0
const VILLAGE_RADIUS: float = 36.0
const PALISADE_SEGMENT: float = 4.0
const ROAD_WIDTH: float = 2.6
const HUMAN_RACE: String = "res://content/defs/races/human.tres"
const WOMEN_SHARE: float = 0.3
const LINES: Array[StringName] = [&"caucasian", &"caucasian", &"asian", &"african"]
const WORLD_SEED: int = 7
## Metres a second that keep feet planted in the walk clip: stride over the time a foot is on the ground.
const WALK_SPEED: float = 1.16
## How far above the saddle bone a rider's hips sit.
const SADDLE_SEAT: float = 0.05
const SKIRT_COLOR: Color = Color(0.36, 0.37, 0.22)
const GROUND_FOG: float = 0.0055
const OVERWORLD_FOG: float = 0.0012

## Camera presets: what they look at, then yaw, pitch and distance. Preset 4 follows the rider.
const CAM_TARGETS: Array[Vector3] = [
	Vector3(0.0, 3.0, 0.0), Vector3(-2.0, 1.5, 6.0), Vector3(-37.0, 1.3, -10.0),
	Vector3.ZERO, Vector3(0.0, 0.0, 0.0),
]
const CAM_ORBITS: Array[Vector3] = [
	Vector3(-125.0, -14.0, 78.0), Vector3(-75.0, -7.0, 10.0), Vector3(-65.0, -4.0, 6.5),
	Vector3(-60.0, -5.0, 7.5), Vector3(-130.0, -46.0, 190.0),
]
const ROAD: Array[Vector2] = [
	Vector2(-170.0, -62.0), Vector2(-90.0, -30.0), Vector2(-44.0, -12.0), Vector2(0.0, 3.0),
	Vector2(42.0, 20.0), Vector2(95.0, 26.0), Vector2(170.0, 66.0),
]


class Mover:
	extends RefCounted
	var node: Node3D
	var speed: float
	var distance: float
	var side: float


var _noise: FastNoiseLite = FastNoiseLite.new()
var _detail: FastNoiseLite = FastNoiseLite.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _road_length: float = 0.0
var _movers: Array[Mover] = []
var _camera: Camera3D = Camera3D.new()
var _follow: Node3D = null
var _target: Vector3 = Vector3.ZERO
var _orbit: Vector3 = Vector3.ZERO
var _hud: Label = null
var _environment: Environment = Environment.new()


func _ready() -> void:
	_rng.seed = WORLD_SEED
	_noise.seed = WORLD_SEED
	_noise.frequency = 0.008
	_noise.fractal_octaves = 4
	_detail.seed = WORLD_SEED + 1
	_detail.frequency = 0.05
	for i: int in range(ROAD.size() - 1):
		_road_length += ROAD[i].distance_to(ROAD[i + 1])
	_build_environment()
	_build_terrain()
	_build_village()
	_build_scatter()
	_build_people()
	add_child(_camera)
	_camera.far = 3000.0
	_camera.fov = 55.0
	_select_camera(ViewUtil.arg("cam", "1").to_int() - 1)
	var out_path: String = ViewUtil.arg("out", "")
	if out_path.is_empty():
		var layer: CanvasLayer = CanvasLayer.new()
		_hud = Label.new()
		_hud.position = Vector2(12.0, 8.0)
		layer.add_child(_hud)
		add_child(layer)
	else:
		var settle: float = ViewUtil.arg("settle", "0").to_float()
		if settle > 0.0:
			await get_tree().create_timer(settle).timeout
			_print_stats()
		await ViewUtil.save_shot_and_quit(self, out_path)


func _process(delta: float) -> void:
	for mover: Mover in _movers:
		mover.distance = fmod(mover.distance + mover.speed * delta, _road_length)
		_place_on_road(mover)
	if _follow != null:
		_target = _follow.global_position + Vector3(0.0, 1.6, 0.0)
	var pan: Vector2 = Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	if pan != Vector2.ZERO:
		_follow = null
		var yaw: float = deg_to_rad(_orbit.x)
		_target += Vector3(pan.x, 0.0, pan.y).rotated(Vector3.UP, yaw) * delta * _orbit.z * 0.6
	_camera_to_orbit()
	if _hud != null:
		_hud.text = "1 vista  2 street  3 gate  4 rider  5 overworld   right-drag orbit   wheel zoom   arrows pan   %d fps" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode >= KEY_1 and key.keycode <= KEY_5:
		_select_camera(key.keycode - KEY_1)
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		_orbit.x -= motion.relative.x * 0.3
		_orbit.y = clampf(_orbit.y - motion.relative.y * 0.3, -85.0, -1.0)
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit.z = maxf(_orbit.z * 0.9, 2.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit.z = minf(_orbit.z * 1.1, 400.0)


func _print_stats() -> void:
	print("STATS fps=%d draw_calls=%d primitives=%d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	])


func _select_camera(index: int) -> void:
	var clamped: int = clampi(index, 0, CAM_TARGETS.size() - 1)
	_target = CAM_TARGETS[clamped] + Vector3(0.0, _height(CAM_TARGETS[clamped].x, CAM_TARGETS[clamped].z), 0.0)
	_orbit = CAM_ORBITS[clamped]
	_environment.fog_density = OVERWORLD_FOG if clamped == 4 else GROUND_FOG
	_follow = null
	if clamped == 3 and not _movers.is_empty():
		_follow = _movers[0].node
		_target = _follow.global_position + Vector3(0.0, 1.6, 0.0)
	_camera_to_orbit()


func _camera_to_orbit() -> void:
	var yaw: float = deg_to_rad(_orbit.x)
	var pitch: float = deg_to_rad(_orbit.y)
	var offset: Vector3 = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * _orbit.z
	var position_wanted: Vector3 = _target + offset
	position_wanted.y = maxf(position_wanted.y, _height(position_wanted.x, position_wanted.z) + 0.8)
	_camera.look_at_from_position(position_wanted, _target, Vector3.UP)


# --- Environment ------------------------------------------------------------------------------

func _build_environment() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-19.0, -62.0, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.64)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.17, 0.21, 0.29)
	sky_material.sky_horizon_color = Color(0.56, 0.5, 0.46)
	sky_material.sky_curve = 0.12
	sky_material.ground_horizon_color = Color(0.56, 0.5, 0.46)
	sky_material.ground_bottom_color = Color(0.3, 0.29, 0.29)
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = 0.1
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	var environment: Environment = _environment
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.62
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 3.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 2.2
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.04
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.46, 0.45, 0.47)
	environment.fog_density = GROUND_FOG
	environment.fog_sun_scatter = 0.12
	environment.fog_sky_affect = 0.35
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.82
	environment.adjustment_contrast = 1.08
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)


# --- Terrain ----------------------------------------------------------------------------------

func _height(x: float, z: float) -> float:
	var radius: float = Vector2(x, z).length()
	var hills: float = _noise.get_noise_2d(x, z) * 34.0 + _detail.get_noise_2d(x, z) * 0.9
	var open_ground: float = smoothstep(VILLAGE_RADIUS + 2.0, VILLAGE_RADIUS + 38.0, radius)
	var road_flat: float = smoothstep(ROAD_WIDTH, ROAD_WIDTH + 16.0, _road_distance(Vector2(x, z)))
	return hills * open_ground * lerpf(0.45, 1.0, road_flat) + _detail.get_noise_2d(x, z) * 0.25


func _road_distance(point: Vector2) -> float:
	var best: float = INF
	for i: int in range(ROAD.size() - 1):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, ROAD[i], ROAD[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


func _ground_color(center: Vector3, normal: Vector3) -> Color:
	var point: Vector2 = Vector2(center.x, center.z)
	var patch: float = _noise.get_noise_2d(center.x * 4.0, center.z * 4.0)
	var color: Color = Color(0.33, 0.37, 0.2).lerp(Color(0.42, 0.39, 0.23), clampf(patch * 2.0 + 0.5, 0.0, 1.0))
	var worn: float = 1.0 - smoothstep(6.0, VILLAGE_RADIUS - 8.0, point.length() + patch * 18.0)
	color = color.lerp(Color(0.3, 0.25, 0.19), worn * 0.85)
	var road: float = _road_distance(point) + _detail.get_noise_2d(center.x, center.z) * 1.5
	if road < ROAD_WIDTH:
		color = Color(0.27, 0.21, 0.16)
	elif road < ROAD_WIDTH + 1.5:
		color = color.lerp(Color(0.27, 0.21, 0.16), 0.55)
	if normal.y < 0.86:
		color = color.lerp(Color(0.36, 0.35, 0.34), smoothstep(0.86, 0.78, normal.y))
	return color * _rng.randf_range(0.92, 1.07)


func _build_terrain() -> void:
	var half: float = WORLD_SIZE * 0.5
	_add_terrain_grid(half, CELL, 0.0, 0.0)
	# A coarse skirt out to the horizon. Only fog ever shows its detail.
	_add_terrain_grid(1500.0, 50.0, half, 1.5)


## Builds a flat-shaded grid, leaving out cells that sit inside the square hole.
func _add_terrain_grid(half: float, cell: float, hole: float, drop: float) -> void:
	var cells: int = int(half * 2.0 / cell)
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var points: PackedVector3Array = PackedVector3Array()
	points.resize((cells + 1) * (cells + 1))
	for row: int in range(cells + 1):
		for col: int in range(cells + 1):
			var x: float = col * cell - half
			var z: float = row * cell - half
			points[row * (cells + 1) + col] = Vector3(x, _height(x, z) - drop, z)
	for row: int in range(cells):
		for col: int in range(cells):
			var a: Vector3 = points[row * (cells + 1) + col]
			var d: Vector3 = points[(row + 1) * (cells + 1) + col + 1]
			if hole > 0.0 and absf(a.x) < hole and absf(a.z) < hole and absf(d.x) < hole and absf(d.z) < hole:
				continue
			var b: Vector3 = points[row * (cells + 1) + col + 1]
			var c: Vector3 = points[(row + 1) * (cells + 1) + col]
			_add_triangle(verts, normals, colors, a, b, c, hole > 0.0)
			_add_triangle(verts, normals, colors, b, d, c, hole > 0.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


func _add_triangle(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, flat_color: bool) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	var color: Color = SKIRT_COLOR if flat_color else _ground_color((a + b + c) / 3.0, normal)
	for point: Vector3 in [a, b, c]:
		verts.append(point)
		normals.append(normal)
		colors.append(color)


# --- Props ------------------------------------------------------------------------------------

func _spawn(model: String, x: float, z: float, facing: Vector3 = Vector3.ZERO, sink: float = 0.0) -> Node3D:
	var scene: PackedScene = load(MODELS % model) as PackedScene
	var instance: Node3D = scene.instantiate() as Node3D
	add_child(instance)
	instance.position = Vector3(x, _height(x, z) - sink, z)
	if facing != Vector3.ZERO:
		instance.basis = Basis.looking_at(facing.normalized(), Vector3.UP, true)
	return instance


func _facing_center(x: float, z: float) -> Vector3:
	return Vector3(-x, 0.0, -z)


func _build_village() -> void:
	_spawn("longhouse", 5.0, -19.0, Vector3(0.0, 0.0, 1.0))
	_spawn("well", 3.0, 7.0)
	var homes: Array[Vector2] = [
		Vector2(-19.0, -19.0), Vector2(-24.0, 4.0), Vector2(-14.0, 21.0), Vector2(7.0, 25.0),
		Vector2(24.0, 12.0), Vector2(25.0, -12.0), Vector2(-12.0, -6.0),
	]
	for home: Vector2 in homes:
		var facing: Vector3 = _facing_center(home.x, home.y) + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0))
		_spawn("cottage", home.x, home.y, facing)
	_add_smoke(Vector3(-19.0, _height(-19.0, -19.0) + 4.8, -19.0))
	_add_smoke(Vector3(24.0, _height(24.0, 12.0) + 4.8, 12.0))
	_add_smoke(Vector3(5.0, _height(5.0, -19.0) + 5.6, -19.0))

	var count: int = int(TAU * VILLAGE_RADIUS / PALISADE_SEGMENT)
	for i: int in range(count):
		var angle: float = TAU * (float(i) + 0.5) / float(count)
		var x: float = cos(angle) * VILLAGE_RADIUS
		var z: float = sin(angle) * VILLAGE_RADIUS
		if _road_distance(Vector2(x, z)) < 5.0:
			continue
		var segment: Node3D = _spawn("palisade", x, z, Vector3(-x, 0.0, -z), 0.1)
		segment.rotate_y(_rng.randf_range(-0.02, 0.02))
	_spawn("watchtower", -39.5, -20.0, Vector3(-1.0, 0.0, 0.6))
	_spawn("watchtower", 33.0, 26.0, Vector3(1.0, 0.0, 0.6))
	_spawn("gibbet", -49.0, -9.0, Vector3(0.0, 0.0, -1.0))


func _add_smoke(at: Vector3) -> void:
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(0.55, 0.53, 0.52, 0.0))
	fade.add_point(0.15, Color(0.42, 0.41, 0.41, 0.42))
	fade.set_color(fade.get_point_count() - 1, Color(0.6, 0.58, 0.58, 0.0))
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = fade
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3(0.25, 1.0, 0.1)
	process.spread = 8.0
	process.initial_velocity_min = 0.9
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0.12, 0.08, 0.04)
	process.scale_min = 0.8
	process.scale_max = 1.3
	process.color_ramp = ramp
	var scale_curve: CurveTexture = CurveTexture.new()
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(1.0, 1.0))
	scale_curve.curve = curve
	process.scale_curve = scale_curve
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	var puff: GradientTexture2D = GradientTexture2D.new()
	var puff_alpha: Gradient = Gradient.new()
	puff_alpha.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	puff_alpha.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	puff.gradient = puff_alpha
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	material.albedo_texture = puff
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	quad.material = material
	var smoke: GPUParticles3D = GPUParticles3D.new()
	smoke.amount = 40
	smoke.lifetime = 13.0
	smoke.preprocess = 13.0
	smoke.process_material = process
	smoke.draw_pass_1 = quad
	smoke.visibility_aabb = AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 40.0, 40.0))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = at
	add_child(smoke)


func _first_mesh(model: String) -> Mesh:
	var scene: PackedScene = load(MODELS % model) as PackedScene
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh
	root.free()
	return mesh


func _build_scatter() -> void:
	var half: float = WORLD_SIZE * 0.5
	var pine_a: Array[Transform3D] = []
	var pine_b: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	for _i: int in range(26000):
		var x: float = _rng.randf_range(-half, half)
		var z: float = _rng.randf_range(-half, half)
		var radius: float = Vector2(x, z).length()
		var road: float = _road_distance(Vector2(x, z))
		if radius < VILLAGE_RADIUS + 10.0 or road < 8.0:
			continue
		var forest: float = _noise.get_noise_2d(x * 2.4 + 300.0, z * 2.4 - 150.0)
		if forest > 0.03 and _rng.randf() < 0.3:
			var scale_factor: float = _rng.randf_range(0.8, 1.35)
			if _rng.randf() < 0.55:
				pine_a.append(_scatter_transform(x, z, scale_factor, 0.2))
			else:
				pine_b.append(_scatter_transform(x, z, scale_factor, 0.2))
		elif _rng.randf() < 0.012:
			rocks.append(_scatter_transform(x, z, _rng.randf_range(0.5, 2.0), 0.3))
	for _i: int in range(16000):
		var x: float = _rng.randf_range(-half * 0.45, half * 0.45)
		var z: float = _rng.randf_range(-half * 0.45, half * 0.45)
		if _road_distance(Vector2(x, z)) < ROAD_WIDTH + 1.0 or Vector2(x, z).length() < 15.0:
			continue
		grass.append(_scatter_transform(x, z, _rng.randf_range(0.8, 1.7), 0.0))
	_add_multimesh("pine_a", pine_a, true)
	_add_multimesh("pine_b", pine_b, true)
	_add_multimesh("rock", rocks, true)
	_add_multimesh("grass_tuft", grass, false)
	for spot: Vector2 in [Vector2(-58.0, 8.0), Vector2(55.0, -8.0), Vector2(-46.0, -36.0), Vector2(62.0, 40.0)]:
		var tree: Node3D = _spawn("dead_tree", spot.x, spot.y)
		tree.rotate_y(_rng.randf() * TAU)


func _scatter_transform(x: float, z: float, scale_factor: float, sink: float) -> Transform3D:
	var basis_value: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale_factor)
	return Transform3D(basis_value, Vector3(x, _height(x, z) - sink, z))


func _add_multimesh(model: String, transforms: Array[Transform3D], casts_shadow: bool) -> void:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _first_mesh(model)
	multimesh.instance_count = transforms.size()
	for i: int in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	if not casts_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


# --- People -----------------------------------------------------------------------------------

## A person from FaceService. crowd gives the low-detail body and no head model.
func _make_person(worn: Array[String], helmet: bool, crowd: bool) -> Node3D:
	var male: bool = _rng.randf() > WOMEN_SHARE
	var age: float = _rng.randf_range(0.05, 0.45)
	var face: FaceData = FaceService.random_face(_rng, load(HUMAN_RACE) as RaceDef, male, -1.0, LINES[_rng.randi_range(0, LINES.size() - 1)])
	var clothes: Array[String] = worn.duplicate()
	if helmet:
		clothes.append_array(BodyView.HELMET)
	var person: Node3D = BodyView.make(face, male, age, clothes, crowd)
	if not crowd:
		var head: Node3D = FaceView.attach(person, face, male, age)
		if helmet:
			FaceView.hide_hair(head)
	return person


func _spawn_person(x: float, z: float, facing: Vector3, clip: StringName, worn: Array[String], helmet: bool) -> Node3D:
	var person: Node3D = _make_person(worn, helmet, false)
	add_child(person)
	person.position = Vector3(x, _height(x, z), z)
	person.basis = Basis.looking_at(facing.normalized(), Vector3.UP, true)
	ViewUtil.play(person, clip, true, _rng.randf() * 4.0)
	return person


func _spawn_rider(clip: StringName, speed: float, distance: float, side: float) -> Node3D:
	var horse: Node3D = (load(MODELS % "horse") as PackedScene).instantiate() as Node3D
	add_child(horse)
	ViewUtil.play(horse, clip, true, _rng.randf())
	var rider: Node3D = _make_person(BodyView.SOLDIER, true, true)
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(horse)
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = "Saddle"
	skeleton.add_child(attachment)
	attachment.add_child(rider)
	# Seats each rider by their own hip height, as they differ.
	var seat: float = BodyView.hip_height(ViewUtil.find_skeleton(rider)) - SADDLE_SEAT
	var rest: Transform3D = skeleton.get_bone_global_rest(skeleton.find_bone("Saddle"))
	rider.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, rest.origin + Vector3(0.0, -seat, 0.0))
	ViewUtil.play(rider, &"ride", true, _rng.randf())
	_add_mover(horse, speed, distance, side)
	return horse


func _add_mover(node: Node3D, speed: float, distance: float, side: float) -> void:
	var mover: Mover = Mover.new()
	mover.node = node
	mover.speed = speed
	mover.distance = distance
	mover.side = side
	_movers.append(mover)
	_place_on_road(mover)


func _place_on_road(mover: Mover) -> void:
	var left: float = mover.distance
	for i: int in range(ROAD.size() - 1):
		var length: float = ROAD[i].distance_to(ROAD[i + 1])
		if left <= length or i == ROAD.size() - 2:
			var direction: Vector2 = (ROAD[i + 1] - ROAD[i]).normalized()
			var point: Vector2 = ROAD[i] + direction * left + direction.orthogonal() * mover.side
			mover.node.position = Vector3(point.x, _height(point.x, point.y), point.y)
			mover.node.basis = Basis.looking_at(Vector3(direction.x, 0.0, direction.y), Vector3.UP, true)
			return
		left -= length


func _build_people() -> void:
	# Index 0 is the rider that camera preset 4 follows. A gallop lands near the gate at start.
	_spawn_rider(&"gallop", 8.5, 104.0, 0.3)
	_spawn_rider(&"walk", 1.7, 78.0, -0.6)
	_spawn_rider(&"walk", 1.7, 74.5, 0.7)

	# A patrol walking in along the road, with a gait matching the ground speed.
	for row: int in range(4):
		for column: int in range(2):
			var walker: Node3D = _make_person(BodyView.SOLDIER, true, true)
			add_child(walker)
			ViewUtil.play(walker, &"walk", true, _rng.randf())
			_add_mover(walker, WALK_SPEED, 120.0 - row * 1.8, -0.9 + column * 1.8)

	# Gate guards.
	_spawn_person(-37.0, -6.0, Vector3(-1.0, 0.0, -0.5), &"idle", BodyView.SOLDIER, true)
	_spawn_person(-39.0, -11.0, Vector3(-1.0, 0.0, 0.1), &"idle", BodyView.SOLDIER, true)

	# Sparring by the well, and villagers in plain clothes.
	_spawn_person(-4.0, 4.0, Vector3(1.0, 0.0, 0.0), &"attack", BodyView.SOLDIER, true)
	_spawn_person(-2.4, 4.0, Vector3(-1.0, 0.0, 0.0), &"block", BodyView.SOLDIER, false)
	_spawn_person(-6.0, 7.5, Vector3(1.0, 0.0, -0.8), &"idle", BodyView.SOLDIER, true)
	_spawn_person(6.0, 5.0, Vector3(-1.0, 0.0, 0.5), &"idle_unarmed", BodyView.COMMONER, false)
	_spawn_person(7.0, 9.0, Vector3(-0.6, 0.0, -1.0), &"idle_unarmed", BodyView.COMMONER, false)
	_spawn_person(0.5, 12.0, Vector3(0.5, 0.0, -1.0), &"walk_unarmed", BodyView.COMMONER, false)

	# A dead man under the gibbet, posed at the end of his death clip.
	var corpse: Node3D = _spawn_person(-46.0, -8.0, Vector3(-0.4, 0.0, 1.0), &"idle_unarmed", BodyView.COMMONER, false)
	var player: AnimationPlayer = ViewUtil.find_player(corpse)
	player.play(&"death")
	player.seek(player.get_animation(&"death").length, true)
	player.pause()
