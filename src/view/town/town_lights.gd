class_name TownLights
extends Node3D
## Every light in a walkable town: lamps behind glass, torches, braziers, hearths and forges, beacons, and the glow of
## lit windows on the street. Each is a source, read from the 'lamp_*' and 'flame_*' marks the models carry (build_walk.py)
## and from the homes whose windows are lit. Only a few real lights, the budget, are ever on: they go to the sources
## nearest the camera, fade in and out with distance, and flicker as flame does; the nearest few cast shadows. Every
## open flame is drawn as a flame card (flame.gdshader), every light at night has a halo (halo.gdshader), and sparks
## rise off the bigger fires. It reads the layout and changes nothing in the world.

enum Kind { LAMP, TORCH, FIRE, BLAZE, WINDOW }

class Source:
	var at: Vector3
	var kind: Kind
	var phase: float
	## Lit only after dusk (lamps, windows), or always (fires).
	var night_only: bool

	func _init(point: Vector3, what: Kind, seed_phase: float) -> void:
		at = point
		kind = what
		phase = seed_phase
		night_only = what == Kind.LAMP or what == Kind.WINDOW


## Each kind's light: colour, energy, range, how much it flickers, flame card size (0 for none), halo size.
const LOOKS: Dictionary[Kind, Array] = {
	Kind.LAMP: [Color(1.0, 0.72, 0.42), 2.6, 12.0, 0.06, 0.0, 2.6],
	Kind.TORCH: [Color(1.0, 0.55, 0.25), 3.2, 12.0, 0.22, 0.5, 3.0],
	Kind.FIRE: [Color(1.0, 0.58, 0.28), 3.6, 13.0, 0.18, 0.8, 3.6],
	Kind.BLAZE: [Color(1.0, 0.6, 0.3), 6.0, 20.0, 0.2, 1.5, 6.0],
	Kind.WINDOW: [Color(1.0, 0.6, 0.32), 1.1, 7.0, 0.04, 0.0, 0.0],
}
const MARK_KINDS: Dictionary[String, Kind] = {
	"lamp": Kind.LAMP, "flame_s": Kind.TORCH, "flame_m": Kind.FIRE, "flame_l": Kind.BLAZE,
}
## How many real lights at most, how many of the nearest cast shadows, and how far out a light is worth having.
const BUDGET: int = 18
const SHADOWED: int = 2
const REACH: float = 48.0
## Seconds between handing out the lights again, and how fast one fades in or out.
const RETHINK: float = 0.2
const FADE_RATE: float = 4.0
## Kinds that may cast shadows. A lamp sits inside its own glass, which would shadow everything.
const SHADOW_KINDS: Array[Kind] = [Kind.TORCH, Kind.FIRE, Kind.BLAZE]

var sources: Array[Source] = []
var night: float = 0.0
## How lit the lamps are, 0 by day to 1 after dusk.
var lamps: float = 0.0

var _lights: Array[OmniLight3D] = []
var _slot_source: Array[int] = []
var _slot_fade: Array[float] = []
var _slot_leaving: Array[bool] = []
var _since: float = RETHINK
var _camera_at: Vector3 = Vector3.ZERO
var _ember_points: PackedVector3Array = PackedVector3Array()


## Lights for a town at an hour: night from 0 by day to 1 at midnight.
static func make(layout: TownLayout, night_amount: float) -> TownLights:
	var out: TownLights = TownLights.new()
	out.name = "Lights"
	out.night = night_amount
	out.lamps = smoothstep(0.12, 0.4, night_amount)
	out._gather(layout)
	return out


func _ready() -> void:
	for i: int in range(BUDGET):
		var light: OmniLight3D = OmniLight3D.new()
		light.visible = false
		light.shadow_enabled = false
		light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light.shadow_bias = 0.08
		light.shadow_normal_bias = 1.5
		light.omni_attenuation = 1.3
		light.light_specular = 0.35
		light.light_volumetric_fog_energy = 1.6
		add_child(light)
		_lights.append(light)
		_slot_source.append(-1)
		_slot_fade.append(0.0)
		_slot_leaving.append(false)
	_build_flames()
	_build_halos()
	_build_embers()


# --- Gathering the sources ----------------------------------------------------------------------------------------------

func _gather(layout: TownLayout) -> void:
	for piece: TownLayout.Piece in layout.pieces:
		_add_marks(piece.model, piece.at, piece.turn, 1.0, 0.0)
		if night > 0.15 and _lit_home(piece):
			# The street before a home whose windows are lit catches some of their glow.
			var front: Vector2 = piece.to_town(0.0, piece.front() + 0.9)
			sources.append(Source.new(Vector3(front.x, 2.0, front.y), Kind.WINDOW, _phase(front)))
	for prop: TownLayout.Prop in layout.props:
		_add_marks(prop.model, prop.at, prop.turn, prop.scale, prop.lift)
	if layout.harbour != null:
		for floater: TownHarbour.Floater in layout.harbour.floaters:
			_add_marks(floater.model, floater.at, floater.turn, 1.0, TownHarbour.WATER_Y)


func _add_marks(model: String, at: Vector2, turn: float, size: float, lift: float) -> void:
	var known: Dictionary = TownLayout.manifest().get(model, {}) as Dictionary
	var marks: Dictionary = known.get("marks", {}) as Dictionary
	for mark_name: String in marks:
		var cut: int = mark_name.rfind("_")
		if cut < 0 or not MARK_KINDS.has(mark_name.substr(0, cut)):
			continue
		var point: Array = (marks[mark_name] as Dictionary)["at"] as Array
		var where: Vector2 = place(at, turn, size, Vector2(point[0] as float, point[2] as float))
		var height: float = lift + (point[1] as float) * size
		sources.append(Source.new(Vector3(where.x, height, where.y), MARK_KINDS[mark_name.substr(0, cut)], _phase(where)))


## A point in a piece's or a prop's own space (x across, z out of its door), on the town's ground.
static func place(at: Vector2, turn: float, size: float, own: Vector2) -> Vector2:
	var ahead: Vector2 = Vector2.from_angle(turn)
	var across: Vector2 = Vector2(ahead.y, -ahead.x)
	return at + (across * own.x + ahead * own.y) * size


## Whether a home has its windows lit tonight, the same way each time: more often in the richer quarters.
static func _lit_home(piece: TownLayout.Piece) -> bool:
	if piece.spot >= 0 or piece.quarter == &"" or piece.kind == &"shed":
		return false
	var look: Color = TownBuilder.look_of(piece)
	return fposmod(sin(piece.at.x * 3.17 + piece.at.y * 7.31) * 9137.5, 1.0) < look.b * 0.7


static func _phase(at: Vector2) -> float:
	return fposmod(sin(at.x * 12.9898 + at.y * 78.233) * 43758.5453, 1.0)


## How bright a source is now, before flicker and fading: lamps and windows only after dusk, fires always, but faint by
## day under the sun.
func _strength(source: Source) -> float:
	var look: Array = LOOKS[source.kind]
	var base: float = look[1] as float
	if source.night_only:
		return base * lamps
	return base * lerpf(0.25, 1.0, smoothstep(0.05, 0.4, night))


# --- Drawing the flames, halos and sparks --------------------------------------------------------------------------------

func _build_flames() -> void:
	var flames: Array[Source] = []
	for source: Source in sources:
		if (LOOKS[source.kind][4] as float) > 0.0:
			flames.append(source)
			if source.kind != Kind.TORCH:
				_ember_points.append(source.at + Vector3(0.0, 0.2, 0.0))
	if flames.is_empty():
		return
	var quad: QuadMesh = QuadMesh.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://src/view/town/flame.gdshader")
	quad.material = material
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = flames.size()
	for i: int in range(flames.size()):
		var source: Source = flames[i]
		var size: float = (LOOKS[source.kind][4] as float) * (0.85 + source.phase * 0.3)
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), source.at - Vector3(0.0, size * 0.12, 0.0)))
		multi.set_instance_custom_data(i, Color(source.phase, 0.6 if source.kind == Kind.TORCH else 0.2, 0.6 if source.kind == Kind.TORCH else 0.2, 0.0))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "Flames"
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_halos() -> void:
	if lamps <= 0.01:
		return
	var glows: Array[Source] = []
	for source: Source in sources:
		if (LOOKS[source.kind][5] as float) > 0.0:
			glows.append(source)
	if glows.is_empty():
		return
	var quad: QuadMesh = QuadMesh.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://src/view/town/halo.gdshader")
	quad.material = material
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = glows.size()
	for i: int in range(glows.size()):
		var source: Source = glows[i]
		var look: Array = LOOKS[source.kind]
		var color: Color = look[0] as Color
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (look[5] as float)), source.at))
		multi.set_instance_custom_data(i, Color(color.r, color.g, color.b, lamps))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "Halos"
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Sparks rising off every fire bigger than a torch: one particle system for the town, each spark born at a fire picked
## from a texture of their places.
func _build_embers() -> void:
	if _ember_points.is_empty():
		return
	var image: Image = Image.create(_ember_points.size(), 1, false, Image.FORMAT_RGBF)
	for i: int in range(_ember_points.size()):
		image.set_pixel(i, 0, Color(_ember_points[i].x, _ember_points[i].y, _ember_points[i].z))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = ImageTexture.create_from_image(image)
	process.emission_point_count = _ember_points.size()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 25.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.1, 0.35, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 2.0
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.2
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	fade.add_point(0.4, Color(1.0, 0.45, 0.12, 0.9))
	fade.set_color(fade.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0.0))
	var fade_texture: GradientTexture1D = GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	var spark: QuadMesh = QuadMesh.new()
	spark.size = Vector2(0.035, 0.035)
	var look: StandardMaterial3D = StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color(3.0, 3.0, 3.0)
	look.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	spark.material = look
	var sparks: GPUParticles3D = GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.process_material = process
	sparks.draw_pass_1 = spark
	sparks.amount = clampi(_ember_points.size() * 8, 8, 400)
	sparks.lifetime = 1.8
	sparks.preprocess = 2.0
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lo: Vector3 = _ember_points[0]
	var hi: Vector3 = _ember_points[0]
	for point: Vector3 in _ember_points:
		lo = lo.min(point)
		hi = hi.max(point)
	sparks.visibility_aabb = AABB(lo - Vector3(4.0, 2.0, 4.0), hi - lo + Vector3(8.0, 10.0, 8.0))
	add_child(sparks)


# --- Handing out the lights ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		_camera_at = camera.global_position
	_since += delta
	if _since >= RETHINK:
		_since = 0.0
		_rethink()
	var now: float = float(Time.get_ticks_msec()) * 0.001
	for slot: int in range(_lights.size()):
		var index: int = _slot_source[slot]
		if index < 0:
			continue
		_slot_fade[slot] = clampf(_slot_fade[slot] + (-delta if _slot_leaving[slot] else delta) * FADE_RATE, 0.0, 1.0)
		var light: OmniLight3D = _lights[slot]
		if _slot_leaving[slot] and _slot_fade[slot] <= 0.0:
			_slot_source[slot] = -1
			light.visible = false
			continue
		var source: Source = sources[index]
		var look: Array = LOOKS[source.kind]
		var wobble: float = look[3] as float
		var p: float = source.phase * 40.0
		var flicker: float = 1.0 - wobble + wobble * (0.55 * sin(now * 7.3 + p) + 0.3 * sin(now * 13.7 + p * 2.1) + 0.15 * sin(now * 23.1 + p * 3.3) + 1.0) * 0.5
		var far: float = 1.0 - smoothstep(REACH * 0.65, REACH, _camera_at.distance_to(source.at))
		light.light_energy = _strength(source) * flicker * _slot_fade[slot] * far
		light.visible = light.light_energy > 0.01


## The budget goes to the strongest sources nearest the camera. A source that keeps its place keeps its light, so
## nothing pops; one that drops out fades away before its light is used again.
func _rethink() -> void:
	var ranked: Array[int] = []
	var scores: Dictionary[int, float] = {}
	for i: int in range(sources.size()):
		var source: Source = sources[i]
		var strength: float = _strength(source)
		if strength < 0.05:
			continue
		var distance: float = _camera_at.distance_to(source.at)
		if distance > REACH:
			continue
		ranked.append(i)
		scores[i] = distance - strength * 2.0
	ranked.sort_custom(func(a: int, b: int) -> bool: return scores[a] < scores[b])
	var wanted: Dictionary[int, bool] = {}
	for i: int in range(mini(ranked.size(), BUDGET)):
		wanted[ranked[i]] = true
	var held: Dictionary[int, int] = {}
	for slot: int in range(_lights.size()):
		var index: int = _slot_source[slot]
		if index < 0:
			continue
		if wanted.has(index):
			_slot_leaving[slot] = false
			held[index] = slot
		else:
			_slot_leaving[slot] = true
	for i: int in range(mini(ranked.size(), BUDGET)):
		var index: int = ranked[i]
		if held.has(index):
			continue
		var slot: int = _free_slot()
		if slot < 0:
			break
		_take(slot, index)
		held[index] = slot
	# The nearest fires cast shadows; a light that moves out of the few stops.
	var shadows: int = 0
	for i: int in range(mini(ranked.size(), BUDGET)):
		var index: int = ranked[i]
		var light: OmniLight3D = _lights[held[index]] if held.has(index) else null
		if light == null:
			continue
		var casts: bool = shadows < SHADOWED and SHADOW_KINDS.has(sources[index].kind) and night > 0.2
		if casts:
			shadows += 1
		if light.shadow_enabled != casts:
			light.shadow_enabled = casts


func _free_slot() -> int:
	for slot: int in range(_lights.size()):
		if _slot_source[slot] < 0:
			return slot
	# Else the dimmest one already on its way out.
	var best: int = -1
	for slot: int in range(_lights.size()):
		if _slot_leaving[slot] and (best < 0 or _slot_fade[slot] < _slot_fade[best]):
			best = slot
	return best


func _take(slot: int, index: int) -> void:
	var source: Source = sources[index]
	var look: Array = LOOKS[source.kind]
	var light: OmniLight3D = _lights[slot]
	_slot_source[slot] = index
	_slot_fade[slot] = 0.0
	_slot_leaving[slot] = false
	light.position = source.at
	light.light_color = look[0] as Color
	light.omni_range = look[2] as float
	light.shadow_enabled = false
	light.visible = true


## How many real lights are on now.
func lights_on() -> int:
	var count: int = 0
	for light: OmniLight3D in _lights:
		if light.visible:
			count += 1
	return count
