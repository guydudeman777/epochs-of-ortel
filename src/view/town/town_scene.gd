class_name TownScene
extends Node3D
## Walking about a town as yourself. The town is built from its real data (TownLayout): its people's buildings on its
## own streets and lots, its walls by its fortification, and a building for each TownSite spot. At each door you can
## do what the spot offers, through Actions, the same as the town's text menu. The world's clock stands still in here.
##
## Entered from the map by TownEntry, and hands the map back when you go. Run alone, it makes a world and walks you in:
## godot --path . res://src/view/town/town_scene.tscn -- --seed=1 --town=id
## Options: --walk-test walks to every spot and uses it, --demo does only what the map's demo needs (a band, a levy,
## the road), --out=path%d.png saves a picture at each spot, --no-folk leaves the streets empty.

const WALK_SPEED: float = 1.5
const RUN_SPEED: float = 4.6
const TURN_RATE: float = 10.0
const CAMERA_HEIGHT: float = 1.6
const CAMERA_BACK: float = 3.4
const CAMERA_SIDE: float = 0.45
## Indoors the camera comes in closer and looks up less, so it stays under the roof.
const CAMERA_BACK_INSIDE: float = 2.1
const PITCH_HIGH_INSIDE: float = 0.3
const CAMERA_EASE: float = 6.0
## Roofs collide only with the camera arm, never with people.
const ROOF_LAYER: int = 2
## Hearth light indoors, since the roof shuts out the sun.
const INDOOR_LIGHT_ENERGY: float = 1.6
const INDOOR_LIGHT_RANGE: float = 11.0
const INDOOR_LIGHT_COLOR: Color = Color(1.0, 0.78, 0.52)
const MENU_WIDTH: float = 600.0
## Up to so many named people walk about in full; the rest of the town is a crowd, one walker for so many people,
## fewer after dark.
const NAMED_MOST: int = 4
const CROWD_MOST: int = 30
const PEOPLE_PER_WALKER: int = 80
## Folk standing at their work: at the market's awnings, the sheds, the plazas.
const WORKERS_MOST: int = 8
## The first watch of the day is at this hour.
const DAWN_HOUR: float = 7.5
## So many folk nearest the camera have faces; the rest are crowd bodies. The slack stops a body swapping back and
## forth at the edge, and only one face is made a frame, so walking about never stutters.
const DETAILED: int = 10
const DETAILED_SLACK: int = 2
const DETAIL_PER_FRAME: int = 1
const FOLK_SPEED: float = 1.25
## A share of the crowd are children, drawn this much smaller; a city has guards walking its rounds.
const CHILD_SHARE: float = 0.15
const CHILD_SIZE: float = 0.62
const GUARDS: int = 2
## Townsfolk step round you rather than through you, from this near.
const GIVE_WAY: float = 1.3
## Beyond this far from the camera a body's clips are stepped once every so many frames.
const CLIP_FAR: float = 30.0
const CLIP_STEPS: int = 3
## A tour step that has not got nearer for this long jumps ahead.
const STUCK_SECONDS: float = 2.5
const ARRIVED: float = 0.9
const TEST_TIME_SCALE: float = 3.0

var _ctx: SimContext
var _site: SettlementData
var _layout: TownLayout
var _controls: TownControls = TownControls.new()
var _me: CharacterBody3D
var _figure: TownFigure
var _pivot: Node3D
var _arm: SpringArm3D
var _indoor_light: OmniLight3D
var _lights: TownLights
var _water: TownWater
var _env: Environment
var _camera: Camera3D
var _folk: Array[TownFigure] = []
## Roofs of buildings drawn from lane B's models, by piece, and the one hidden now.
var _fall: float = 0.0
var _folk_target: Array[int] = []
var _folk_wait: Array[float] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _graph_points: Array[Vector2] = []
var _graph_links: Array[PackedInt32Array] = []
var _place: HudPlate
var _prompt: HudPlate
var _news_plate: HudPlate
var _menu_panel: PanelContainer
var _menu_shade: ColorRect
var _menu_scroller: ScrollContainer
var _menu_title: Label
var _menu_text: RichTextLabel
var _menu_buttons: VBoxContainer
var _menu_open: bool = false
var _menu_spot: int = -1
var _menu_options: Array[TownSpots.Option] = []
var _news: PackedStringArray = PackedStringArray()
var _said: PackedStringArray = PackedStringArray()
var _near_spot: int = -1
var _leaving: bool = false
## The self-test: spots still to visit, the way to the next, and what to choose there.
var _tour: Array[int] = []
var _tour_path: Array[Vector2] = []
var _tour_on: bool = false
var _tour_busy: bool = false
var _tour_best: float = INF
var _tour_still: float = 0.0
var _shot_index: int = 0
## While a picture of the whole town is taken, the camera is not behind you.
var _overview: bool = false
## From 0 by day to 1 at night.
var _night: float = 0.0
## Which share of the far bodies have their clips stepped this frame.
var _clip_turn: int = 0


func _ready() -> void:
	_rng.seed = 7
	if World.state == null:
		var config: WorldGenConfig = WorldGenConfig.new()
		config.world_seed = ViewUtil.arg("seed", "1").to_int()
		World.new_game(config)
	_ctx = Simulation.kernel.ctx
	GameClock.paused = true
	if OS.get_cmdline_user_args().has("--list-towns"):
		for id: int in _ctx.settlement_ids():
			var s: SettlementData = _ctx.settlement(id)
			var trades: PackedStringArray = PackedStringArray()
			for b_id: int in s.business_ids:
				var b: BusinessData = _ctx.business(b_id)
				if b != null:
					trades.append(String(b.building_id))
			print("TOWN %d %s at %s %s %s%s people=%d walls=%.1f houses=%d shore=%s trades=%s" % [id, s.display_name, _ctx.world.map.positions.get(id),
					TownView.culture_of(_ctx, s), "town" if s.kind == SimEnums.SettlementKind.TOWN else "city",
					(" of %d (%s)" % [s.city_id, s.specialty]) if s.kind == SimEnums.SettlementKind.TOWN else "",
					PopService.total(s), s.fortification, TownView.house_count(s), LandOps.shore_dir(_ctx, s),
					",".join(trades)])
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--layouts"):
		# Lays out every town without drawing it, to check the layouts and how long they take.
		for id: int in _ctx.settlement_ids():
			var began_at: int = Time.get_ticks_msec()
			var s: SettlementData = _ctx.settlement(id)
			var made: TownLayout = TownLayout.make(_ctx, s)
			var models: Dictionary[String, int] = {}
			for prop: TownLayout.Prop in made.props:
				models[prop.model.trim_prefix("walk_prop_")] = models.get(prop.model.trim_prefix("walk_prop_"), 0) + 1
			print("LAYOUT %d %s %s%s pieces=%d props=%d edge=%.0f build=%.0f wall=%.0f water=%s shore=%.0f %d ms %s" % [id,
					s.display_name, "town " + String(s.specialty) if made.is_town else "city", " port" if made.port else "",
					made.pieces.size(), made.props.size(), made.edge, made.build_radius, made.wall_radius, made.water_dir,
					made.shore_line if made.water_dir != Vector2.ZERO else 0.0, Time.get_ticks_msec() - began_at, models])
		get_tree().quit()
		return
	_site = _ctx.settlement(_pick_site())
	if _site == null:
		push_error("No town to walk in.")
		return
	_rng.seed = _site.id * 104729 + 3
	var began: int = Time.get_ticks_msec()
	_layout = TownLayout.make(_ctx, _site)
	_build_world()
	TownBuilder.arms = Heraldry.of_settlement(_ctx, _site)
	var nodes: Array[Node3D] = TownBuilder.build(self, _layout)
	for i: int in range(nodes.size()):
		var roof: Node3D = TownBuilder.roof_of(nodes[i], _layout.pieces[i])
		if roof != null:
			_give_roof_collision(roof)
	_water = TownWater.build(self, _layout, _night)
	_build_smoke()
	# --plain leaves out the lights, the fire smoke and the animals, to measure what they cost.
	var plain: bool = OS.get_cmdline_user_args().has("--plain")
	_lights = TownLights.make(_layout, 0.0 if plain else _night)
	if not plain:
		add_child(_lights)
		_build_fire_smoke()
	_build_graph()
	_build_me()
	if not OS.get_cmdline_user_args().has("--no-folk"):
		_build_folk()
		if not OS.get_cmdline_user_args().has("--plain"):
			add_child(TownLife.make(_layout, _night, _site.id * 6151 + _ctx.world.calendar.day_index))
	_build_hud()
	print("TOWN %s (%s): %d spots, %d pieces, %d folk, built in %d ms" % [_site.display_name, _layout.culture,
			_layout.spots.size(), _layout.pieces.size(), _folk.size(), Time.get_ticks_msec() - began])
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--bench-split"):
		_bench_split.call_deferred()
	elif args.has("--bench"):
		_bench.call_deferred()
	elif not ViewUtil.arg("look", "").is_empty():
		_look_round.call_deferred()
	elif args.has("--walk-test") or args.has("--demo"):
		_start_tour(args.has("--demo"))
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pick_site() -> int:
	if TownEntry.site_id >= 0:
		return TownEntry.site_id
	var asked: int = ViewUtil.arg("town", "-1").to_int()
	if _ctx.settlement(asked) != null:
		TownEntry.site_id = asked
		return asked
	var c: CharacterData = _ctx.character(_ctx.world.player_character_id)
	if c != null and _ctx.settlement(c.settlement_id) != null:
		return c.settlement_id
	var ids: Array[int] = _ctx.settlement_ids()
	return ids[0] if not ids.is_empty() else -1


# --- Building the town -----------------------------------------------------

## The hour of the day in town, from the world's watch (the first watch at dawn), or --hour= to look at it then.
func _hour() -> float:
	var asked: String = ViewUtil.arg("hour", "")
	if not asked.is_empty():
		return fposmod(asked.to_float(), 24.0)
	return fposmod(DAWN_HOUR + float(_ctx.world.calendar.watch) * 24.0 / float(CalendarData.WATCHES_PER_DAY), 24.0)


## From 0 by day to 1 in the dead of night, through dusk and dawn.
static func night_of(hour: float) -> float:
	return SkyDome.night_of(hour)


## The sky over this town today: its weather comes from the town, the day and the land it stands on.
func _make_sky() -> SkyDome:
	var biome: LandDef.Biome = LandDef.Biome.TEMPERATE
	var place: Variant = _ctx.world.map.positions.get(_site.id)
	if place is Vector2:
		biome = _ctx.terrain().biome_at(place as Vector2)
	var weather_seed: int = _ctx.world.world_seed * 7919 + _ctx.world.calendar.day_index * 131 + _site.id
	var asked: String = ViewUtil.arg("weather", "")
	var dome: SkyDome = SkyDome.of_place(_hour(), weather_seed, biome)
	# --weather=clear, cloudy or overcast, to look at the town under each.
	match asked:
		"clear":
			dome.cover = 0.05
			dome.overcast = 0.0
		"cloudy":
			dome.cover = 0.6
			dome.overcast = 0.0
		"overcast":
			dome.cover = 0.5
			dome.overcast = 0.9
	return dome


func _build_world() -> void:
	_night = night_of(_hour())
	var dome: SkyDome = _make_sky()
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	_env = env
	dome.apply(env)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	# Glow, so lamps, fires and lit windows bloom at night (each lamp's halo is its own card, TownLights). --vfog=1 adds a
	# thin haze in the night air that the lights catch; it costs a millisecond or two a frame on a small card, so it is
	# off unless asked for.
	env.glow_enabled = _night > 0.1
	env.glow_intensity = lerpf(0.35, 0.85, _night)
	env.glow_bloom = lerpf(0.0, 0.04, _night)
	env.glow_hdr_threshold = lerpf(1.3, 0.85, _night)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for level: int in range(7):
		env.set_glow_level(level, [0.0, 1.0, 1.0, 0.8, 0.6, 0.3, 0.0][level] as float)
	env.volumetric_fog_enabled = _night > 0.3 and ViewUtil.arg("vfog", "0") == "1"
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.55, 0.58, 0.66)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.4
	env.volumetric_fog_sky_affect = 0.2
	env.fog_enabled = true
	env.fog_density = lerpf(0.0025, 0.006, _night) * lerpf(1.0, 1.6, dome.overcast)
	environment.environment = env
	add_child(environment)
	# By day the sun climbs from the east and sets in the west; by night a pale moon stands in.
	var sun: DirectionalLight3D = dome.make_light()
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	TownSurfaces.set_night(_night)


## Smoke from every chimney: one particle system for the whole town, each puff born at a chimney picked from a
## texture of their places. Fewer smoke by day than at supper.
func _build_smoke() -> void:
	var stacks: PackedVector3Array = TownBuilder.chimneys(_layout)
	var lit: PackedVector3Array = PackedVector3Array()
	var share: float = 0.4 + _night * 0.4
	for i: int in range(stacks.size()):
		if fposmod(sin(float(i) * 91.7 + float(_site.id)) * 4375.85, 1.0) < share:
			lit.append(stacks[i])
	if lit.is_empty():
		return
	var image: Image = Image.create(lit.size(), 1, false, Image.FORMAT_RGBF)
	for i: int in range(lit.size()):
		image.set_pixel(i, 0, Color(lit[i].x, lit[i].y, lit[i].z))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = ImageTexture.create_from_image(image)
	process.emission_point_count = lit.size()
	process.direction = Vector3(0.3, 1.0, 0.15)
	process.spread = 12.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0.25, 0.12, 0.08)
	process.damping_min = 0.1
	process.damping_max = 0.2
	process.scale_min = 0.6
	process.scale_max = 1.0
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_texture: CurveTexture = CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(0.42, 0.4, 0.38, 0.0))
	fade.set_color(1, Color(0.55, 0.54, 0.52, 0.0))
	fade.add_point(0.12, Color(0.4, 0.39, 0.37, 0.42))
	fade.add_point(0.6, Color(0.5, 0.49, 0.47, 0.22))
	var fade_texture: GradientTexture1D = GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	var puff: QuadMesh = QuadMesh.new()
	puff.size = Vector2(1.6, 1.6)
	var look: StandardMaterial3D = StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if _night > 0.5 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var soft: GradientTexture2D = GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var round_edge: Gradient = Gradient.new()
	round_edge.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	round_edge.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = round_edge
	look.albedo_texture = soft
	if _night > 0.5:
		look.albedo_color = Color(0.25, 0.25, 0.3)
	puff.material = look
	var smoke: GPUParticles3D = GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.process_material = process
	smoke.draw_pass_1 = puff
	smoke.amount = clampi(lit.size() * 14, 16, 900)
	smoke.lifetime = 7.0
	smoke.preprocess = 7.0
	smoke.visibility_aabb = AABB(Vector3(-_layout.edge, -5.0, -_layout.edge), Vector3(_layout.edge * 2.0, 60.0, _layout.edge * 2.0))
	add_child(smoke)


## A thin smoke off every fire burning in the open: braziers, torches, forges, the beacon.
func _build_fire_smoke() -> void:
	var points: PackedVector3Array = PackedVector3Array()
	for source: TownLights.Source in _lights.sources:
		if source.kind == TownLights.Kind.LAMP or source.kind == TownLights.Kind.WINDOW:
			continue
		if _layout.inside(Vector2(source.at.x, source.at.z)) != null:
			continue
		points.append(source.at + Vector3(0.0, 0.4, 0.0))
	if points.is_empty():
		return
	var image: Image = Image.create(points.size(), 1, false, Image.FORMAT_RGBF)
	for i: int in range(points.size()):
		image.set_pixel(i, 0, Color(points[i].x, points[i].y, points[i].z))
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = ImageTexture.create_from_image(image)
	process.emission_point_count = points.size()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 10.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.2, 0.15, 0.05)
	process.scale_min = 0.3
	process.scale_max = 0.6
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.4))
	var grow_texture: CurveTexture = CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(0.3, 0.28, 0.26, 0.0))
	fade.add_point(0.15, Color(0.3, 0.29, 0.28, 0.3))
	fade.set_color(fade.get_point_count() - 1, Color(0.45, 0.45, 0.45, 0.0))
	var fade_texture: GradientTexture1D = GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	var puff: QuadMesh = QuadMesh.new()
	puff.size = Vector2(1.0, 1.0)
	var look: StandardMaterial3D = StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var soft: GradientTexture2D = GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var round_edge: Gradient = Gradient.new()
	round_edge.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	round_edge.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = round_edge
	look.albedo_texture = soft
	puff.material = look
	var smoke: GPUParticles3D = GPUParticles3D.new()
	smoke.name = "FireSmoke"
	smoke.process_material = process
	smoke.draw_pass_1 = puff
	smoke.amount = clampi(points.size() * 5, 8, 240)
	smoke.lifetime = 4.0
	smoke.preprocess = 4.0
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-_layout.edge, -5.0, -_layout.edge), Vector3(_layout.edge * 2.0, 40.0, _layout.edge * 2.0))
	add_child(smoke)


## Where townsfolk walk: a ring round the square, and each street out to the town's end, linked up.
func _build_graph() -> void:
	const RING: int = 12
	var ring_radius: float = _layout.square_radius * 0.62
	for i: int in range(RING):
		_graph_points.append(Vector2.from_angle(float(i) * TAU / float(RING)) * ring_radius)
		_graph_links.append(PackedInt32Array())
	for i: int in range(RING):
		_link(i, (i + 1) % RING)
	const STEP: float = 9.0
	for street: PackedVector2Array in _layout.streets:
		var previous: int = -1
		var walked: float = 0.0
		var next: float = ring_radius + 4.0
		for i: int in range(street.size() - 1):
			var a: Vector2 = street[i]
			var b: Vector2 = street[i + 1]
			var length: float = a.distance_to(b)
			while next <= walked + length:
				var point: Vector2 = a.lerp(b, (next - walked) / maxf(length, 0.001))
				next += STEP
				if point.length() < ring_radius + 3.0:
					continue
				if point.length() > _layout.edge - 4.0:
					break
				if _layout.blocked(point, 1.0):
					continue
				_graph_points.append(point)
				_graph_links.append(PackedInt32Array())
				var index: int = _graph_points.size() - 1
				if previous < 0:
					_link(index, _nearest_ring(point, RING))
				else:
					_link(index, previous)
				previous = index
			walked += length
	# The lanes and alleys, each joined at its ends to whatever way is nearest.
	for lane: PackedVector2Array in _layout.lanes:
		var first: int = _graph_points.size()
		var previous: int = -1
		var walked: float = 0.0
		var next: float = 0.0
		for i: int in range(lane.size() - 1):
			var a: Vector2 = lane[i]
			var b: Vector2 = lane[i + 1]
			var length: float = a.distance_to(b)
			while next <= walked + length:
				var point: Vector2 = a.lerp(b, (next - walked) / maxf(length, 0.001))
				next += 6.0
				if _layout.blocked(point, 0.4):
					continue
				_graph_points.append(point)
				_graph_links.append(PackedInt32Array())
				var index: int = _graph_points.size() - 1
				if previous >= 0:
					_link(index, previous)
				previous = index
			walked += length
		var last: int = _graph_points.size() - 1
		if last < first:
			continue
		for end: int in [first, last]:
			var best: int = -1
			for j: int in range(first):
				if best < 0 or _graph_points[j].distance_squared_to(_graph_points[end]) < _graph_points[best].distance_squared_to(_graph_points[end]):
					best = j
			if best >= 0 and _graph_points[best].distance_to(_graph_points[end]) < 16.0:
				_link(end, best)


func _link(a: int, b: int) -> void:
	if not _graph_links[a].has(b):
		_graph_links[a].append(b)
		_graph_links[b].append(a)


func _nearest_ring(point: Vector2, ring: int) -> int:
	var best: int = 0
	for i: int in range(ring):
		if _graph_points[i].distance_to(point) < _graph_points[best].distance_to(point):
			best = i
	return best


func _nearest_node(point: Vector2) -> int:
	var best: int = 0
	for i: int in range(_graph_points.size()):
		if _graph_points[i].distance_squared_to(point) < _graph_points[best].distance_squared_to(point):
			best = i
	return best


## The way along the streets from one point to another, ending at the other.
func _route(from: Vector2, to: Vector2) -> Array[Vector2]:
	var start: int = _nearest_node(from)
	var goal: int = _nearest_node(to)
	var cost: Dictionary[int, float] = {start: 0.0}
	var came: Dictionary[int, int] = {}
	var open: Array[int] = [start]
	while not open.is_empty():
		var best: int = 0
		for i: int in range(open.size()):
			if cost[open[i]] < cost[open[best]]:
				best = i
		var here: int = open[best]
		open.remove_at(best)
		if here == goal:
			break
		for there: int in _graph_links[here]:
			var through: float = cost[here] + _graph_points[here].distance_to(_graph_points[there])
			if not cost.has(there) or through < cost[there]:
				cost[there] = through
				came[there] = here
				open.append(there)
	var way: Array[Vector2] = [to]
	var at: int = goal
	while true:
		way.push_front(_graph_points[at])
		if at == start or not came.has(at):
			break
		at = came[at]
	return way


func _build_me() -> void:
	_me = CharacterBody3D.new()
	_me.name = "Me"
	# Steep enough to step over a threshold or onto a dais.
	_me.floor_max_angle = deg_to_rad(65.0)
	_me.floor_snap_length = 0.3
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.88
	_me.add_child(shape)
	add_child(_me)
	_me.position = Vector3(_layout.start.x, 0.0, _layout.start.y)
	var c: CharacterData = _ctx.character(_ctx.world.player_character_id)
	if c != null:
		_figure = TownFigure.new()
		_me.add_child(_figure)
		_figure.setup_person(_ctx, c, true)
	var way: Vector2 = Vector2.from_angle(_layout.start_turn)
	_controls.yaw = atan2(way.x, way.y)
	if _figure != null:
		_figure.rotation.y = _controls.yaw
	_pivot = Node3D.new()
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = CAMERA_BACK
	_arm.margin = 0.2
	var ball: SphereShape3D = SphereShape3D.new()
	ball.radius = 0.25
	_arm.shape = ball
	_arm.add_excluded_object(_me.get_rid())
	_arm.collision_mask = 1 | ROOF_LAYER
	_pivot.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 600.0
	_arm.add_child(_camera)
	_camera.make_current()
	_update_camera()


func _build_folk() -> void:
	# The head model takes seconds to load, so that happens now and not when the first face comes near.
	load(FaceView.HEAD_SCENE)
	load(FaceView.GROWN_HAIR_SCENE)
	var named: Array[int] = _named_people()
	for id: int in named:
		var c: CharacterData = _ctx.character(id)
		var figure: TownFigure = TownFigure.new()
		add_child(figure)
		figure.setup_person(_ctx, c, true)
		var f: FactionData = _ctx.faction(_site.faction_id)
		var ruler: bool = f != null and f.ruler_id == id
		figure.add_label(c.given_name + (", ruler" if ruler else ""), MenuStyle.GOLD if ruler else MenuStyle.TEXT)
		var hall: int = _spot_of_kind(&"hall")
		if ruler and hall >= 0 and _keep(figure, hall, "lord"):
			continue
		_add_walker(figure, ruler)
	var groups: Array[PopGroupData] = []
	var total: int = 0
	for group: PopGroupData in _site.pop_groups:
		if group.count > 0 and _ctx.defs.races.has(group.race_id):
			groups.append(group)
			total += group.count
	if total <= 0:
		return
	_build_keepers(groups, total)
	var hour: float = _hour()
	var crowd: int = clampi(roundi(float(PopService.total(_site) / PEOPLE_PER_WALKER) * busy_at(hour)), 3, CROWD_MOST)
	_build_workers(groups, total)
	for i: int in range(crowd):
		var group: PopGroupData = _pick_group(groups, total)
		var worn: Array[String] = []
		worn.assign(BodyView.COMMONER)
		if group.status == SimEnums.LegalStatus.ENSLAVED:
			worn.erase("boots")
		# Some of the crowd are children, small and bareheaded.
		var child: bool = _rng.randf() < CHILD_SHARE * (1.0 - _night)
		var figure: TownFigure = _crowd_figure(group.race_id, worn, 0.0 if child else -1.0)
		if child:
			figure.scale = Vector3.ONE * CHILD_SIZE
		_add_walker(figure, false)
	_build_gatherings(groups, total, hour)


## How busy the streets are at an hour, from 0 to 1: the market mornings busiest, a lull after noon, the evening out,
## and few about in the dead of night.
static func busy_at(hour: float) -> float:
	var h: float = fposmod(hour, 24.0)
	if h < 5.0:
		return 0.15
	if h < 7.0:
		return lerpf(0.15, 0.8, (h - 5.0) / 2.0)
	if h < 12.0:
		return 1.0
	if h < 14.0:
		return 0.75
	if h < 18.0:
		return 0.85
	if h < 21.0:
		return 0.7
	return lerpf(0.5, 0.15, (h - 21.0) / 3.0)


## Folk standing about where the hour takes them: buyers at the market's counters in the morning, drinkers outside the
## tavern at evening, beggars where the town is poor, and guards walking their rounds in a city.
func _build_gatherings(groups: Array[PopGroupData], total: int, hour: float) -> void:
	var worn: Array[String] = []
	worn.assign(BodyView.COMMONER)
	var market_hours: bool = hour >= 7.0 and hour < 14.0
	var evening: bool = hour >= 18.0 or hour < 1.0
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.kind == &"market_stall" and market_hours:
			for n: int in range(_rng.randi_range(0, 2)):
				var at: Vector2 = piece.to_town(_rng.randf_range(-1.2, 1.2), piece.high.z + _rng.randf_range(0.7, 1.4))
				_stand(_crowd_figure(_pick_group(groups, total).race_id, worn), at, piece.at)
		elif piece.kind == &"tavern" and evening:
			var door: Vector2 = piece.to_town(0.0, piece.high.z + 2.4)
			var ring: int = _rng.randi_range(3, 6)
			for n: int in range(ring):
				var at: Vector2 = door + Vector2.from_angle(float(n) / float(ring) * TAU + 0.3) * 1.1 + Vector2.from_angle(piece.turn) * 0.8
				_stand(_crowd_figure(_pick_group(groups, total).race_id, worn), at, door + Vector2.from_angle(piece.turn) * 0.8)
	if _layout.poverty > 0.35:
		var ragged: Array[String] = []
		ragged.assign(BodyView.COMMONER)
		ragged.erase("boots")
		var places: Array[Vector2] = []
		places.append(_layout.start + Vector2.from_angle(_layout.start_turn).orthogonal() * 3.0)
		places.append_array(_layout.plazas)
		for i: int in range(mini(roundi(_layout.poverty * 4.0), places.size())):
			var at: Vector2 = places[i] + Vector2(1.5, 1.0)
			_stand(_crowd_figure(_pick_group(groups, total).race_id, ragged), at, at * 0.9)
	if not _layout.is_town:
		var soldier: Array[String] = []
		soldier.assign(BodyView.SOLDIER)
		for n: int in range(GUARDS):
			_add_walker(_crowd_figure(_pick_group(groups, total).race_id, soldier), false)


## Someone standing still at a place, looking towards another, out of anyone's way.
func _stand(figure: TownFigure, at: Vector2, toward: Vector2) -> void:
	if _layout.blocked(at, 0.3) or _layout.wet(at, 1.0):
		figure.queue_free()
		return
	figure.position = Vector3(at.x, 0.0, at.y)
	var way: Vector2 = toward - at
	figure.rotation.y = atan2(way.x, way.y)
	_folk.append(figure)
	_folk_target.append(-2)
	_folk_wait.append(0.0)


## Folk at their work, standing: sellers under the market's awnings, someone at the woodpile by a shed, at the well
## and at the small squares' troughs. Fewer after dark. Only bodies; nothing they do touches the world.
func _build_workers(groups: Array[PopGroupData], total: int) -> void:
	var places: Array[Array] = []
	for prop: TownLayout.Prop in _layout.props:
		var ahead: Vector2 = Vector2.from_angle(prop.turn)
		match prop.model:
			"walk_prop_awning":
				places.append([prop.at + ahead * 0.25, ahead])
			"walk_prop_trough", "walk_prop_shrine":
				places.append([prop.at + ahead * 1.6, -ahead])
			"walk_prop_woodpile", "walk_prop_cart":
				places.append([prop.at + ahead * 1.4, -ahead])
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.kind == &"well":
			places.append([piece.to_town(0.0, piece.high.z + 0.8), -Vector2.from_angle(piece.turn)])
	var most: int = roundi(float(WORKERS_MOST) * (1.0 - _night * 0.75))
	var taken: int = 0
	var order: Array[int] = []
	for i: int in range(places.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return (places[a][0] as Vector2).length() < (places[b][0] as Vector2).length())
	for i: int in order:
		if taken >= most:
			break
		var at: Vector2 = places[i][0] as Vector2
		var way: Vector2 = places[i][1] as Vector2
		if _layout.blocked(at, 0.1):
			continue
		var group: PopGroupData = _pick_group(groups, total)
		var worn: Array[String] = []
		worn.assign(BodyView.COMMONER)
		if group.status == SimEnums.LegalStatus.ENSLAVED:
			worn.erase("boots")
		var figure: TownFigure = _crowd_figure(group.race_id, worn)
		figure.position = Vector3(at.x, 0.0, at.y)
		figure.rotation.y = atan2(way.x, way.y)
		_folk.append(figure)
		_folk_target.append(-2)
		_folk_wait.append(0.0)
		taken += 1


func _pick_group(groups: Array[PopGroupData], total: int) -> PopGroupData:
	var pick: int = _rng.randi_range(0, total - 1)
	for g: PopGroupData in groups:
		if pick < g.count:
			return g
		pick -= g.count
	return groups[0]


## One of the many. A soldier's kit (with mail) gets the realm's arms; anyone else is dressed as their people dress at
## their wealth (Outfits), a wealth picked from the town's: more poor in a poor town, more well-off in a rich one, and
## the bonded or ragged (no boots asked for) at the bottom.
func _crowd_figure(race_id: StringName, worn: Array[String], age: float = -1.0) -> TownFigure:
	var male: bool = _rng.randf() < 0.5
	var face: FaceData = FaceService.random_face(_rng, _ctx.defs.races[race_id], male)
	var dressed: Array[String] = worn.duplicate()
	if worn.has("mail"):
		var arms: String = BodyView.arms_of(_ctx.faction(_site.faction_id))
		if not arms.is_empty():
			dressed.append(arms)
	else:
		var tier: int = _crowd_tier(not worn.has("boots"))
		var gear: EquipmentData = EquipmentData.new()
		gear.armour_ids = Outfits.outfit(_ctx.defs, _layout.culture, race_id, male, tier, &"", _rng.randi())
		if not gear.armour_ids.is_empty():
			dressed = BodyView.worn_for(gear, _rng.randi_range(0, 99999), null, tier)
	var figure: TownFigure = TownFigure.new()
	add_child(figure)
	figure.setup_crowd(face, male, _rng.randf_range(0.1, 0.7) if age < 0.0 else age, dressed)
	return figure


## How well off one of the crowd is, from the town's own wealth and want.
func _crowd_tier(ragged: bool) -> int:
	if ragged:
		return Outfits.BONDED if _rng.randf() < 0.5 else Outfits.POOR
	var roll: float = _rng.randf()
	if roll < _layout.poverty * 0.6:
		return Outfits.POOR
	if roll > 1.0 - _layout.wealth * 0.45:
		return Outfits.WELL_OFF
	return Outfits.COMMON


## Whoever keeps each spot, at their mark: the tavern keeper behind the counter, the smith at the forge, the captain,
## the pen keeper, a seller at the stall, the gate's guards, and a steward where the lord is away. Free folk of the
## town's own; only the lord is a real person.
func _build_keepers(groups: Array[PopGroupData], total: int) -> void:
	var free_groups: Array[PopGroupData] = []
	var free_total: int = 0
	for group: PopGroupData in groups:
		if group.status == SimEnums.LegalStatus.FREE:
			free_groups.append(group)
			free_total += group.count
	if free_total <= 0:
		free_groups = groups
		free_total = total
	for spot: int in range(_layout.spots.size()):
		var kind: StringName = _layout.spots[spot].kind
		if kind == &"hall" and _ruler_home():
			continue
		var piece: TownLayout.Piece = _layout.piece_for_spot(spot)
		if piece == null or not piece.has_mark(TownLayout.KEEPER_MARKS.get(kind, "") as String):
			continue
		var worn: Array[String] = []
		worn.assign(BodyView.SOLDIER if kind == &"gate" or kind == &"barracks" else BodyView.COMMONER)
		var race: StringName = _pick_group(free_groups, free_total).race_id
		_keep(_crowd_figure(race, worn), spot, TownLayout.KEEPER_MARKS[kind])
		if kind == &"gate" and piece.has_mark("guard_1"):
			_keep(_crowd_figure(race, worn), spot, "guard_1")


func _ruler_home() -> bool:
	var f: FactionData = _ctx.faction(_site.faction_id)
	var ruler: CharacterData = _ctx.character(f.ruler_id) if f != null else null
	return ruler != null and ruler.settlement_id == _site.id and ruler.death_day < 0


## Stands someone at a mark of a spot's building, looking the way the mark says. False if it has no such mark.
func _keep(figure: TownFigure, spot: int, mark_name: String) -> bool:
	var piece: TownLayout.Piece = _layout.piece_for_spot(spot)
	if piece == null or not piece.has_mark(mark_name):
		return false
	var mark: TownLayout.Mark = piece.mark(mark_name)
	figure.position = Vector3(mark.at.x, mark.height, mark.at.y)
	figure.rotation.y = atan2(mark.way.x, mark.way.y)
	_folk.append(figure)
	_folk_target.append(-2)
	_folk_wait.append(0.0)
	return true


## Real people of this town who are about: its ruler if home, then others by id, none on the road.
func _named_people() -> Array[int]:
	var out: Array[int] = []
	var f: FactionData = _ctx.faction(_site.faction_id)
	if f != null:
		var ruler: CharacterData = _ctx.character(f.ruler_id)
		if ruler != null and ruler.settlement_id == _site.id and ruler.death_day < 0:
			out.append(ruler.id)
	for id: int in _ctx.character_ids():
		if out.size() >= NAMED_MOST:
			break
		var c: CharacterData = _ctx.character(id)
		if c == null or c.death_day >= 0 or c.settlement_id != _site.id or c.warband_id >= 0 or out.has(id):
			continue
		if id == _ctx.world.player_character_id or not _ctx.is_adult(c):
			continue
		out.append(id)
	return out


## A townsperson set on the streets. One who keeps a hall stands at its door.
func _add_walker(figure: TownFigure, keeps_hall: bool) -> void:
	var start: int = _rng.randi_range(0, _graph_points.size() - 1)
	var at: Vector2 = _graph_points[start]
	var hall: int = _spot_of_kind(&"hall")
	if keeps_hall and hall >= 0:
		at = _layout.doors[hall] + Vector2.from_angle(_rng.randf() * TAU) * 1.5
		start = -1
	figure.position = Vector3(at.x, 0.0, at.y)
	_folk.append(figure)
	_folk_target.append(start)
	_folk_wait.append(_rng.randf_range(0.0, 4.0))


func _spot_of_kind(kind: StringName) -> int:
	for i: int in range(_layout.spots.size()):
		if _layout.spots[i].kind == kind:
			return i
	return -1


func _build_hud() -> void:
	MenuStyle.apply(self)
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	var layer: Control = MenuStyle.hud_root(canvas)
	_place = HudPlate.new(&"BannerPanel", 0.0, 18)
	layer.add_child(_place)
	_place.pin(Vector2(0.0, 0.0), Vector2(16.0, 14.0))
	_prompt = HudPlate.new(&"HudPanel", 0.0, 17)
	layer.add_child(_prompt)
	_prompt.pin(Vector2(0.5, 1.0), Vector2(0.0, -90.0))
	_news_plate = HudPlate.new(&"HudPanel", 520.0, 15)
	layer.add_child(_news_plate)
	_news_plate.pin(Vector2(0.0, 1.0), Vector2(16.0, -62.0))
	var hint: HudPlate = HudPlate.new(&"HudPanel", 0.0, 14)
	layer.add_child(hint)
	hint.pin(Vector2(0.5, 1.0), Vector2(0.0, -14.0))
	hint.text = "WASD walk  ·  Shift run  ·  Mouse look  ·  E use  ·  Esc menu   (pad: sticks, A use, LB run, Start)"
	var f: FactionData = _ctx.faction(_site.faction_id)
	var calendar: CalendarData = _ctx.world.calendar
	_place.text = "[color=#%s]%s[/color]   ·   %s   ·   Year %d, month %d, day %d" % [MenuStyle.GOLD.to_html(false), _site.display_name,
			f.display_name if f != null else "no realm", calendar.year(), calendar.month() + 1, calendar.day_of_month() + 1]
	_menu_shade = ColorRect.new()
	_menu_shade.color = Color(0.0, 0.0, 0.0, 0.45)
	_menu_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_shade.visible = false
	layer.add_child(_menu_shade)
	_menu_panel = PanelContainer.new()
	_menu_panel.anchor_left = 0.5
	_menu_panel.anchor_right = 0.5
	_menu_panel.anchor_top = 0.5
	_menu_panel.anchor_bottom = 0.5
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_panel.custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	_menu_title = MenuStyle.title("", 24)
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_text = RichTextLabel.new()
	_menu_text.bbcode_enabled = true
	_menu_text.fit_content = true
	_menu_text.scroll_active = false
	_menu_text.custom_minimum_size = Vector2(MENU_WIDTH - 40.0, 0.0)
	_menu_scroller = ScrollContainer.new()
	_menu_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_buttons = VBoxContainer.new()
	_menu_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_buttons.add_theme_constant_override(&"separation", 6)
	_menu_scroller.add_child(_menu_buttons)
	column.add_child(_menu_title)
	column.add_child(MenuStyle.rule())
	column.add_child(_menu_text)
	column.add_child(_menu_scroller)
	_menu_panel.add_child(column)
	layer.add_child(_menu_panel)
	_menu_panel.visible = false
	_refresh_news()


# --- Each frame ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var asked: StringName = _controls.handle_event(event)
	if _menu_open:
		if asked == TownControls.PAUSE or asked == TownControls.BACK:
			_close_menu()
		return
	match asked:
		TownControls.USE:
			if _near_spot >= 0:
				open_spot(_near_spot)
		TownControls.PAUSE:
			_open_pause()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_controls.release_all()


func _physics_process(delta: float) -> void:
	if _me == null or _leaving:
		return
	var wish: Vector2 = Vector2.ZERO
	var running: bool = false
	if _tour_on:
		wish = _tour_wish(delta)
		running = true
	elif not _menu_open:
		wish = _controls.wish(delta)
		running = _controls.running()
	var speed: float = RUN_SPEED if running else WALK_SPEED
	_fall = 0.0 if _me.is_on_floor() else _fall - 9.8 * delta
	_me.velocity = Vector3(wish.x * speed, _fall, wish.y * speed)
	_me.move_and_slide()
	if _figure != null:
		var moved: Vector2 = Vector2(_me.get_real_velocity().x, _me.get_real_velocity().z)
		_figure.face_towards(wish, delta, TURN_RATE)
		_figure.show_motion(moved.length())


func _process(delta: float) -> void:
	if _me == null or _leaving:
		return
	if not _overview:
		_update_camera()
	if _water != null:
		_water.rock(float(Time.get_ticks_msec()) * 0.001)
	_walk_folk(delta)
	_update_detail()
	_fit_camera_indoors(delta)
	var near: int = _layout.spot_near(Vector2(_me.position.x, _me.position.z))
	if near != _near_spot:
		_near_spot = near
	_prompt.visible = _near_spot >= 0 and not _menu_open
	if _prompt.visible:
		var key: String = "A" if _controls.using_pad else "E"
		_prompt.text = "[color=#%s]%s[/color]   %s" % [MenuStyle.GOLD.to_html(false), key, _layout.spots[_near_spot].label]


## Roofs stay drawn indoors. The camera comes in closer and looks up less, and the roof stops its arm.
func _fit_camera_indoors(delta: float) -> void:
	var indoors: bool = _layout.inside(Vector2(_me.position.x, _me.position.z)) != null
	if _indoor_light == null:
		_indoor_light = OmniLight3D.new()
		_indoor_light.light_color = INDOOR_LIGHT_COLOR
		_indoor_light.omni_range = INDOOR_LIGHT_RANGE
		_indoor_light.shadow_enabled = false
		_indoor_light.light_energy = 0.0
		add_child(_indoor_light)
	_indoor_light.position = _me.position + Vector3(0.0, 2.2, 0.0)
	_indoor_light.light_energy = lerpf(_indoor_light.light_energy, INDOOR_LIGHT_ENERGY if indoors else 0.0, clampf(delta * CAMERA_EASE, 0.0, 1.0))
	_indoor_light.visible = _indoor_light.light_energy > 0.01
	var reach: float = CAMERA_BACK_INSIDE if indoors else CAMERA_BACK
	_arm.spring_length = lerpf(_arm.spring_length, reach, clampf(delta * CAMERA_EASE, 0.0, 1.0))
	_controls.pitch_high = PITCH_HIGH_INSIDE if indoors else TownControls.PITCH_HIGH
	_controls.pitch = minf(_controls.pitch, lerpf(_controls.pitch, _controls.pitch_high, clampf(delta * CAMERA_EASE, 0.0, 1.0)))


## A roof the camera arm cannot pass through, on a layer people do not collide with.
func _give_roof_collision(roof: Node3D) -> void:
	var meshes: Array[Node] = roof.find_children("*", "MeshInstance3D", true, false)
	if roof is MeshInstance3D:
		meshes.append(roof)
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = ROOF_LAYER
		body.collision_mask = 0
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = mesh.mesh.create_trimesh_shape()
		body.add_child(shape)
		mesh.add_child(body)


func _update_camera() -> void:
	var at: Vector3 = _me.position
	var ahead: Vector2 = _controls.forward()
	var right: Vector2 = Vector2(-ahead.y, ahead.x)
	_pivot.position = at + Vector3(right.x * CAMERA_SIDE, CAMERA_HEIGHT, right.y * CAMERA_SIDE)
	# The arm reaches out along its own +Z, so it points back from the way you look, and up by the pitch.
	_pivot.rotation = Vector3(-_controls.pitch, _controls.yaw + PI, 0.0)


## The folk nearest the camera get faces. Everyone else is one of the crowd.
func _update_detail() -> void:
	var from: Vector3 = _camera.global_position
	var order: Array[TownFigure] = _folk.duplicate()
	order.sort_custom(func(x: TownFigure, y: TownFigure) -> bool: return from.distance_squared_to(x.global_position) < from.distance_squared_to(y.global_position))
	var added: int = 0
	_clip_turn = (_clip_turn + 1) % CLIP_STEPS
	for rank: int in range(order.size()):
		var figure: TownFigure = order[rank]
		if rank < DETAILED and added < DETAIL_PER_FRAME and not figure.is_near():
			figure.set_near(true)
			added += 1
		elif rank >= DETAILED + DETAILED_SLACK and figure.is_near():
			figure.set_near(false)
		# Bodies far off have their clips stepped every few frames, a share of them each frame.
		var far: bool = from.distance_to(figure.global_position) > CLIP_FAR
		figure.set_far(far)
		if far and figure.get_instance_id() % CLIP_STEPS == _clip_turn:
			figure.step_clips(get_process_delta_time() * float(CLIP_STEPS))


func _walk_folk(delta: float) -> void:
	for i: int in range(_folk.size()):
		var figure: TownFigure = _folk[i]
		if _folk_target[i] == -2:
			figure.show_motion(0.0)
			continue
		if _folk_target[i] < 0:
			figure.show_motion(0.0)
			var to_me: Vector3 = _me.position - figure.position
			figure.face_towards(Vector2(to_me.x, to_me.z), delta, 2.0)
			continue
		if _folk_wait[i] > 0.0:
			_folk_wait[i] -= delta
			figure.show_motion(0.0)
			continue
		var target: Vector2 = _graph_points[_folk_target[i]]
		var here: Vector2 = Vector2(figure.position.x, figure.position.z)
		var offset: Vector2 = target - here
		if offset.length() < 0.4:
			var links: PackedInt32Array = _graph_links[_folk_target[i]]
			_folk_target[i] = links[_rng.randi_range(0, links.size() - 1)] if not links.is_empty() else _folk_target[i]
			if _rng.randf() < 0.25:
				_folk_wait[i] = _rng.randf_range(1.5, 6.0)
			continue
		var way: Vector2 = offset.normalized()
		# Someone in the way (you) is stepped round, to whichever side is further from them.
		var to_me: Vector2 = Vector2(_me.position.x, _me.position.z) - here
		if to_me.length() < GIVE_WAY and to_me.dot(way) > 0.0:
			var aside: Vector2 = way.orthogonal() * (1.0 if to_me.dot(way.orthogonal()) < 0.0 else -1.0)
			way = (way * 0.35 + aside).normalized()
		var step: Vector2 = way * minf(FOLK_SPEED * delta, offset.length())
		figure.position += Vector3(step.x, 0.0, step.y)
		figure.face_towards(way, delta, 6.0)
		figure.show_motion(FOLK_SPEED)


# --- Spots -----------------------------------------------------------------

func _player_id() -> int:
	return _ctx.world.player_character_id


func _only_looking() -> bool:
	var c: CharacterData = _ctx.character(_player_id())
	return c == null or c.settlement_id != _site.id


## Opens what a spot offers: what is there, and what you can do.
func open_spot(spot: int) -> void:
	_menu_spot = spot
	var at: TownSite.Spot = _layout.spots[spot]
	var words: String = TownSpots.words_for(_ctx, _site, at, _player_id())
	if not _said.is_empty():
		words = "[color=#%s]%s[/color]\n\n%s" % [MenuStyle.BRIGHT.to_html(false), "\n".join(_said), words]
		_said = PackedStringArray()
	_menu_options = TownSpots.options_for(_ctx, _site, at, _player_id())
	if at.kind == &"tavern":
		_menu_options.insert(_menu_options.size() - 1, TownSpots.Option.new("Take a bed for a week", _wait_days.bind(7), "A week goes by.", true))
		_menu_options.insert(_menu_options.size() - 1, TownSpots.Option.new("Take a bed for a month", _wait_days.bind(CalendarData.DAYS_PER_MONTH), "A month goes by.", true))
	if _only_looking():
		# Run alone in a town you are not in: you may look, but what you do happens where you are.
		words = "[i]You are only looking. You are not really here.[/i]

" + words
		_menu_options = [_menu_options[_menu_options.size() - 1]]
	var labels: Array[String] = []
	var actions: Array[Callable] = []
	for i: int in range(_menu_options.size()):
		labels.append(_menu_options[i].label)
		# A heading is shown, not chosen.
		actions.append(Callable() if _menu_options[i].heading else _choose.bind(i))
	_show_menu(at.label, words, labels, actions)


func _choose(index: int) -> void:
	var option: TownSpots.Option = _menu_options[index]
	var words: String = option.run()
	if not words.is_empty():
		_news.append(words)
		_said.append(words)
		_refresh_news()
	if TownSpots.must_leave(_ctx, _site, _player_id()) or (option.leaves and option.worked):
		_close_menu()
		go_back_to_map()
		return
	if option.closes:
		_close_menu()
		return
	open_spot(_menu_spot)


func _show_menu(title: String, words: String, labels: Array[String], actions: Array[Callable]) -> void:
	_menu_open = true
	_menu_title.text = title
	_menu_text.text = words
	for child: Node in _menu_buttons.get_children():
		_menu_buttons.remove_child(child)
		child.queue_free()
	var first: Button = null
	for i: int in range(labels.size()):
		if not actions[i].is_valid():
			var heading: Label = MenuStyle.title(labels[i], 16)
			heading.modulate = MenuStyle.GOLD
			_menu_buttons.add_child(heading)
			continue
		var button: Button = Button.new()
		button.text = labels[i]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 38.0)
		button.pressed.connect(actions[i])
		_menu_buttons.add_child(button)
		if first == null:
			first = button
	_menu_panel.visible = true
	_menu_shade.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fit_menu.call_deferred()
	if first != null:
		first.grab_focus()


func _close_menu() -> void:
	_menu_open = false
	_menu_spot = -1
	_menu_panel.visible = false
	_menu_shade.visible = false
	if not _tour_on and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _fit_menu() -> void:
	var rows: float = _menu_buttons.get_combined_minimum_size().y
	var room: float = get_viewport().get_visible_rect().size.y * 0.85 - _menu_text.get_combined_minimum_size().y - 120.0
	_menu_scroller.custom_minimum_size.y = clampf(rows, 0.0, maxf(room, 120.0))
	_menu_panel.reset_size()
	var want: Vector2 = _menu_panel.get_combined_minimum_size()
	_menu_panel.offset_left = -want.x * 0.5
	_menu_panel.offset_right = want.x * 0.5
	_menu_panel.offset_top = -want.y * 0.5
	_menu_panel.offset_bottom = want.y * 0.5


func _refresh_news() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(maxi(_news.size() - 4, 0), _news.size()):
		lines.append(_news[i])
	_news_plate.text = "\n".join(lines)
	_news_plate.visible = not lines.is_empty()


func _open_pause() -> void:
	var labels: Array[String] = ["Go on", "Save"]
	var actions: Array[Callable] = [_close_menu, _save]
	var c: CharacterData = _ctx.character(_player_id())
	var band: WarbandData = _ctx.warband(c.warband_id) if c != null else null
	if band != null:
		labels.append("Back to the map")
		actions.append(go_back_to_map)
	labels.append("To the title")
	labels.append("Leave the game")
	actions.append(func() -> void: get_tree().change_scene_to_file(OverworldScene.MENU_SCENE))
	actions.append(func() -> void: get_tree().quit())
	var words: String = "Time stands still while you are in town."
	if band == null:
		words += " You have no band to leave with: the gate or the barracks will make you one."
	_show_menu(_site.display_name, words, labels, actions)


## Time goes by, which only the map's clock can do: the days pass, and the map takes you back in to see what changed.
func _wait_days(days: int) -> ActionResult:
	Simulation.kernel.advance_days(days)
	return ActionResult.ok(days)


func _save() -> void:
	var saved: Error = World.save_game(OverworldScene.SAVE_PATH)
	_news.append("Saved." if saved == OK else "Could not save: %s." % error_string(saved))
	_refresh_news()
	_close_menu()


## Out of the gate and back to the map, which hears what was done here. It is all in the world already.
func go_back_to_map() -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	print("TOWN leaves %s: %s" % [_site.display_name, " | ".join(_news)])
	if TownEntry.map == null and (_tour_on or OS.get_cmdline_user_args().has("--walk-test")):
		get_tree().quit(0)
		return
	TownEntry.leave(self, "\n".join(_news))


# --- Walking itself round every spot, to test the whole of it ---------------

func _start_tour(short: bool) -> void:
	_tour_on = true
	Engine.time_scale = TEST_TIME_SCALE
	var gate: int = _spot_of_kind(&"gate")
	if short:
		_tour = [gate, _spot_of_kind(&"barracks"), gate]
	else:
		_tour.append(gate)
		for i: int in range(_layout.spots.size()):
			if i != gate:
				_tour.append(i)
		_tour.append(gate)
	_tour.assign(_tour.filter(func(i: int) -> bool: return i >= 0))
	_tour_busy = true
	await _overview_shot()
	_tour_busy = false
	_next_tour_step()


## The whole town from above the gate, for the test's first picture.
func _overview_shot() -> void:
	if ViewUtil.arg("out", "").is_empty() or DisplayServer.get_name() == "headless":
		return
	_overview = true
	var back: Vector2 = _layout.start.normalized() * (_layout.edge * 0.95)
	var high: Camera3D = Camera3D.new()
	high.far = 900.0
	add_child(high)
	high.global_position = Vector3(back.x, _layout.edge * 0.55, back.y)
	high.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	high.make_current()
	await _frames(30)
	await _shot()
	_camera.make_current()
	high.queue_free()
	_overview = false


func _next_tour_step() -> void:
	if _tour.is_empty():
		_tour_on = false
		var c: CharacterData = _ctx.character(_player_id())
		if TownEntry.map != null and c != null and c.warband_id < 0:
			# No band to leave with: you stay in town, as anyone would.
			print("TOUR done, no band, stays in %s" % _site.display_name)
			Engine.time_scale = 1.0
			return
		go_back_to_map()
		return
	_tour_path = _way_to(_tour[0])
	_tour_best = INF
	_tour_still = 0.0
	print("TOUR to %s, %d steps" % [_layout.spots[_tour[0]].label, _tour_path.size()])


## The way to where a spot is used: out of whatever building you are in, along the streets, and in at its door.
func _way_to(spot: int) -> Array[Vector2]:
	var here: Vector2 = Vector2(_me.position.x, _me.position.z)
	var out: Array[Vector2] = []
	var inside: TownLayout.Piece = _layout.inside(here)
	if inside != null and inside.has_mark("door_in") and inside.has_mark("door_out"):
		out.append(inside.mark("door_in").at)
		out.append(inside.mark("door_out").at)
		here = inside.mark("door_out").at
	elif inside != null:
		# Open-fronted, like a smithy: out the front.
		here = inside.to_town(0.0, inside.high.z + 1.5)
		out.append(here)
	var entry: PackedVector2Array = _layout.entries[spot]
	var door: Vector2 = _layout.doors[spot]
	if entry.is_empty():
		out.append_array(_route(here, door))
		return out
	out.append_array(_route(here, entry[0]))
	for i: int in range(1, entry.size()):
		out.append(entry[i])
	out.append(door)
	return out


func _tour_wish(delta: float) -> Vector2:
	if _tour_busy or _tour_path.is_empty():
		return Vector2.ZERO
	var here: Vector2 = Vector2(_me.position.x, _me.position.z)
	var target: Vector2 = _tour_path[0]
	var offset: Vector2 = target - here
	var distance: float = offset.length()
	# The last step is where a spot is used, and anywhere within reach of it will do.
	if distance < (ARRIVED if _tour_path.size() > 1 else TownLayout.USE_RANGE * 0.6):
		_tour_path.remove_at(0)
		_tour_best = INF
		_tour_still = 0.0
		if _tour_path.is_empty():
			_arrive.call_deferred()
		return Vector2.ZERO
	if distance < _tour_best - 0.05:
		_tour_best = distance
		_tour_still = 0.0
	else:
		_tour_still += delta
		if _tour_still > STUCK_SECONDS:
			print("TOUR stuck at %s, jumps to %s" % [here, target])
			_me.position = Vector3(target.x, 0.0, target.y)
			_tour_still = 0.0
	_controls.yaw = lerp_angle(_controls.yaw, atan2(offset.x, offset.y), clampf(delta * 4.0, 0.0, 1.0))
	return offset / distance


## At a door: look at the building, use it, choose what the test wants there, and go on.
func _arrive() -> void:
	_tour_busy = true
	var spot: int = _tour.pop_front()
	var piece: TownLayout.Piece = _layout.piece_for_spot(spot)
	if piece != null:
		# Face whoever keeps it, or the building itself.
		var keeper: TownLayout.Mark = _layout.keeper_mark(spot)
		var toward: Vector2 = keeper.at if keeper != null and spot != _spot_of_kind(&"gate") else piece.at
		var to: Vector2 = toward - Vector2(_me.position.x, _me.position.z)
		if to.length() > 0.3:
			_controls.yaw = atan2(to.x, to.y)
		_controls.pitch = 0.2
	await _frames(20)
	if _leaving:
		return
	await _shot()
	open_spot(spot)
	print("TOUR at %s | %s" % [_layout.spots[spot].label, _menu_text.text.replace("\n", " ")])
	var labels: PackedStringArray = PackedStringArray()
	for option: TownSpots.Option in _menu_options:
		labels.append(option.label)
	print("TOUR options: %s" % " / ".join(labels))
	await _frames(6)
	await _shot()
	var last: bool = _tour.is_empty()
	for wanted: String in _wanted_at(_layout.spots[spot].kind, last):
		for i: int in range(_menu_options.size()):
			if _menu_options[i].label.begins_with(wanted):
				print("TOUR picks: %s" % _menu_options[i].label)
				_choose(i)
				if _leaving:
					return
				break
	if _menu_open:
		_close_menu()
	_tour_busy = false
	_next_tour_step()


## What the test chooses at each kind of spot. A band first, a levy or two, a look at the rest, then the road.
func _wanted_at(kind: StringName, last: bool) -> Array[String]:
	match kind:
		&"gate":
			if last:
				return ["Put your", "Leave town", "March on"]
			return ["Take to the road"]
		&"barracks":
			return ["Hire one levy", "Hire one levy"]
		&"market":
			return ["Buy a month of supplies"]
	return []


## --look=path%d.png: pictures of the town to judge its look by, from above and from where a walker stands, then quits.
func _look_round() -> void:
	var path: String = ViewUtil.arg("look", "")
	_overview = true
	var eye: Camera3D = Camera3D.new()
	eye.far = 900.0
	eye.fov = 62.0
	add_child(eye)
	eye.make_current()
	var views: Array[Array] = []
	var back: Vector2 = _layout.start.normalized() * (_layout.edge * 0.9)
	views.append([Vector3(back.x, _layout.edge * 0.5, back.y), Vector3.ZERO])
	# The town's work: from over the square out across it, and from a walker's eye among it.
	if _layout.works != null:
		var work: Vector2 = Vector2.from_angle(_layout.works.way)
		var over: Vector2 = -work * _layout.square_radius
		var at: Vector2 = work * (_layout.build_radius + 22.0)
		views.append([Vector3(over.x, 34.0, over.y), Vector3(at.x, 0.0, at.y)])
		var stand: Vector2 = work * (_layout.build_radius + 6.0) + work.orthogonal() * 4.0
		views.append([Vector3(stand.x, 1.7, stand.y), Vector3(at.x, 1.5, at.y)])
	# The market from before its first counter, the others along beside it.
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.kind == &"market_stall":
			var buyer: Vector2 = piece.to_town(-2.5, piece.high.z + 5.0)
			views.append([Vector3(buyer.x, 1.8, buyer.y), Vector3(piece.at.x, 1.1, piece.at.y)])
			break
	if _layout.water_dir != Vector2.ZERO:
		var shore: Vector2 = _layout.water_dir * (_layout.shore_line - 10.0)
		var across: Vector2 = _layout.water_dir.orthogonal()
		views.append([Vector3(shore.x - across.x * 14.0, 6.0, shore.y - across.y * 14.0), Vector3(shore.x + _layout.water_dir.x * 25.0, 0.0, shore.y + _layout.water_dir.y * 25.0)])
		# A walker on the quayside lane, between the warehouses and the water, or on the strand.
		var walk: Vector2 = _layout.water_dir * (_layout.shore_line - 3.4) if _layout.harbour != null and _layout.harbour.quay else shore
		views.append([Vector3(walk.x, 1.7, walk.y),Vector3(walk.x + across.x * 20.0 + _layout.water_dir.x * 6.0, 1.0, walk.y + across.y * 20.0 + _layout.water_dir.y * 6.0)])
	var just_works: int = views.size()
	views.append([Vector3(back.x * 0.55, 14.0, back.y * 0.55), Vector3(0.0, 0.0, 0.0)])
	views.append([Vector3(_layout.start.x, 1.7, _layout.start.y), Vector3(0.0, 1.5, 0.0)])
	for street: PackedVector2Array in _layout.streets:
		if views.size() >= 6:
			break
		var near: Vector2 = street[1].normalized() * _layout.square_radius * 0.8
		var far: Vector2 = street[1].normalized() * _layout.square_radius * 3.0
		if street.size() > 2:
			far = street[2]
		views.append([Vector3(near.x, 1.7, near.y), Vector3(far.x, 1.4, far.y)])
	for lane: PackedVector2Array in _layout.lanes:
		if views.size() >= 9 or lane.size() < 2:
			break
		var a: Vector2 = lane[0]
		var b: Vector2 = lane[mini(2, lane.size() - 1)]
		views.append([Vector3(a.x, 1.7, a.y), Vector3(b.x, 1.4, b.y)])
	# Close to the ground, as a walker sees it at their feet: on the square, and on the first street out of it.
	if not _layout.streets.is_empty() and _layout.streets[0].size() > 1:
		var out: Vector2 = _layout.streets[0][1].normalized()
		var square_eye: Vector2 = out * (_layout.square_radius * 0.8)
		var square_at: Vector2 = out * (_layout.square_radius * 0.8 - 3.0)
		views.append([Vector3(square_eye.x, 1.6, square_eye.y), Vector3(square_at.x, 0.0, square_at.y)])
	# The first cobbled street: through the market or the rich quarter.
	for street: PackedVector2Array in _layout.streets:
		var found: bool = false
		for i: int in range(street.size() - 1):
			var mid: Vector2 = (street[i] + street[i + 1]) * 0.5
			var q: StringName = _layout.quarter_at(mid)
			if mid.length() > _layout.square_radius + 3.0 and (q == &"market" or q == &"rich"):
				var way: Vector2 = (street[i + 1] - street[i]).normalized()
				views.append([Vector3(mid.x, 1.6, mid.y), Vector3(mid.x + way.x * 3.0, 0.0, mid.y + way.y * 3.0)])
				found = true
				break
		if found:
			break
	# Each trade's yard, from before its front, one of each kind.
	var seen: Dictionary[StringName, bool] = {}
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.spot < 0 or not TownLayout.is_yard(piece.kind) or seen.has(piece.kind):
			continue
		seen[piece.kind] = true
		var eye_at: Vector2 = piece.to_town(2.0, piece.high.z + 8.0)
		views.append([Vector3(eye_at.x, 5.0, eye_at.y), Vector3(piece.at.x, 1.0, piece.at.y)])
	# --look-works looks only from above and at the work and the water.
	if OS.get_cmdline_user_args().has("--look-works"):
		views = views.slice(0, just_works)
	# --look-sky looks only up from the square, four ways round, to see the sky.
	if OS.get_cmdline_user_args().has("--look-sky"):
		views.clear()
		var stand: Vector3 = Vector3(_layout.start.x * 0.3, 1.7, _layout.start.y * 0.3)
		for k: int in range(4):
			var way: Vector2 = Vector2.from_angle(float(k) * PI * 0.5)
			views.append([stand, stand + Vector3(way.x, 0.45, way.y)])
	for i: int in range(views.size()):
		var from: Vector3 = views[i][0]
		var to: Vector3 = views[i][1]
		eye.global_position = from
		if from.distance_to(to) > 0.1:
			eye.look_at(to, Vector3.UP)
		await _frames(20)
		await RenderingServer.frame_post_draw
		var file: String = path % i
		get_viewport().get_texture().get_image().save_png(file)
		print("LOOK shot %s fps=%d draw_calls=%d" % [file, Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()


## --bench-split: what the lights and fire, the animals and birds, and the townsfolk each cost the GPU, by timing each
## view with them shown and hidden in turn, in the same run, so a busy machine weighs on both alike.
func _bench_split() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_overview = true
	var eye: Camera3D = Camera3D.new()
	eye.far = 600.0
	eye.fov = 62.0
	add_child(eye)
	eye.make_current()
	var viewport: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var out: Vector2 = _layout.start.normalized()
	var views: Array[Array] = [
		["gate", Vector3(_layout.start.x, 1.7, _layout.start.y), Vector3(0.0, 1.5, 0.0)],
		["square", Vector3(out.x * _layout.square_radius * 0.8, 1.7, out.y * _layout.square_radius * 0.8), Vector3(-out.x * 10.0, 1.5, -out.y * 10.0)],
	]
	var fog: bool = _env.volumetric_fog_enabled
	for view: Array in views:
		eye.global_position = view[1] as Vector3
		eye.look_at(view[2] as Vector3, Vector3.UP)
		for group: String in ["fog", "lamps", "flames", "folk"]:
			var shown: float = 0.0
			var hidden: float = 0.0
			for cycle: int in range(3):
				_show_group(group, true, fog)
				await _frames(20)
				shown += await _gpu_time(viewport, 60)
				_show_group(group, false, fog)
				await _frames(20)
				hidden += await _gpu_time(viewport, 60)
			_show_group(group, true, fog)
			print("SPLIT %s %s %s shown=%.2f hidden=%.2f cost=%.2f gpu ms" % [_site.display_name, view[0], group, shown / 3.0, hidden / 3.0, (shown - hidden) / 3.0])
	get_tree().quit()


func _show_group(group: String, on: bool, fog: bool) -> void:
	match group:
		"fog":
			_env.volumetric_fog_enabled = on and fog
		"lamps":
			_lights.set_process(on)
			for child: Node in _lights.get_children():
				if child is OmniLight3D:
					(child as OmniLight3D).visible = on
		"flames":
			for child: Node in _lights.get_children():
				if not child is OmniLight3D:
					(child as Node3D).visible = on
			var smoke: Node3D = get_node_or_null("FireSmoke") as Node3D
			if smoke != null:
				smoke.visible = on
		"life":
			var life: Node3D = get_node_or_null("Life") as Node3D
			if life != null:
				life.visible = on
		"folk":
			for figure: TownFigure in _folk:
				figure.visible = on


func _gpu_time(viewport: RID, frames: int) -> float:
	var sum: float = 0.0
	for i: int in range(frames):
		await get_tree().process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	return sum / float(frames)


## --bench: how long a frame takes, with vsync off, from a walker's eye at the gate, on the square, down a street,
## and from above, then quits. Each view settles first, then so many frames are timed.
func _bench() -> void:
	const SETTLE: int = 60
	const TIMED: int = 240
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_overview = true
	var eye: Camera3D = Camera3D.new()
	eye.far = 600.0
	eye.fov = 62.0
	add_child(eye)
	eye.make_current()
	var views: Array[Array] = []
	views.append(["gate", Vector3(_layout.start.x, 1.7, _layout.start.y), Vector3(0.0, 1.5, 0.0)])
	var out: Vector2 = _layout.start.normalized()
	views.append(["square", Vector3(out.x * _layout.square_radius * 0.8, 1.7, out.y * _layout.square_radius * 0.8), Vector3(-out.x * 10.0, 1.5, -out.y * 10.0)])
	if _layout.streets.size() > 1:
		var street: PackedVector2Array = _layout.streets[1]
		var near: Vector2 = street[1].normalized() * _layout.square_radius * 1.1
		var far: Vector2 = street[street.size() - 1]
		views.append(["street", Vector3(near.x, 1.7, near.y), Vector3(far.x, 1.4, far.y)])
	views.append(["above", Vector3(out.x * _layout.edge * 0.9, _layout.edge * 0.5, out.y * _layout.edge * 0.9), Vector3.ZERO])
	var total: float = 0.0
	var total_gpu: float = 0.0
	# The GPU's own time for the frame, which other programs on the machine disturb less than the wall clock.
	var viewport: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for view: Array in views:
		eye.global_position = view[1] as Vector3
		eye.look_at(view[2] as Vector3, Vector3.UP)
		await _frames(SETTLE)
		var times: Array[float] = []
		var gpu: float = 0.0
		var last: int = Time.get_ticks_usec()
		for i: int in range(TIMED):
			await get_tree().process_frame
			var now: int = Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			last = now
		gpu /= float(TIMED)
		total_gpu += gpu
		print("BENCH %s %s gpu_ms=%.2f cpu_render_ms=%.2f" % [_site.display_name, view[0], gpu, RenderingServer.viewport_get_measured_render_time_cpu(viewport)])
		times.sort()
		var mean: float = 0.0
		for t: float in times:
			mean += t
		mean /= float(times.size())
		total += mean
		print("BENCH %s %s ms=%.2f p95=%.2f draw_calls=%d lights=%d" % [_site.display_name, view[0], mean,
				times[floori(times.size() * 0.95)],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				find_children("*", "OmniLight3D", true, false).filter(func(n: Node) -> bool: return (n as OmniLight3D).is_visible_in_tree()).size()])
	print("BENCH %s mean ms=%.2f gpu_ms=%.2f hour=%.1f" % [_site.display_name, total / float(views.size()), total_gpu / float(views.size()), _hour()])
	get_tree().quit()


func _frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame


func _shot() -> void:
	var path: String = ViewUtil.arg("out", "")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var file: String = path % _shot_index
	_shot_index += 1
	get_viewport().get_texture().get_image().save_png(file)
	print("TOUR shot %s fps=%d draw_calls=%d" % [file, Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
