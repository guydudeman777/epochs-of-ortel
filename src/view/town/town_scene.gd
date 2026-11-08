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
const MENU_WIDTH: float = 600.0
## Up to so many named people walk about in full; the rest of the town is a crowd.
const NAMED_MOST: int = 4
const CROWD_MOST: int = 12
const FOLK_SPEED: float = 1.25
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
var _camera: Camera3D
var _folk: Array[TownFigure] = []
## Roofs of buildings drawn from lane B's models, by piece, and the one hidden now.
var _roofs: Dictionary[TownLayout.Piece, Node3D] = {}
var _roof_hidden: Node3D = null
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


func _ready() -> void:
	_rng.seed = 7
	if World.state == null:
		var config: WorldGenConfig = WorldGenConfig.new()
		config.world_seed = ViewUtil.arg("seed", "1").to_int()
		World.new_game(config)
	_ctx = Simulation.kernel.ctx
	GameClock.paused = true
	_site = _ctx.settlement(_pick_site())
	if _site == null:
		push_error("No town to walk in.")
		return
	_rng.seed = _site.id * 104729 + 3
	var began: int = Time.get_ticks_msec()
	_layout = TownLayout.make(_ctx, _site)
	_build_world()
	var nodes: Array[Node3D] = TownBuilder.build(self, _layout)
	for i: int in range(nodes.size()):
		var roof: Node3D = TownBuilder.roof_of(nodes[i], _layout.pieces[i])
		if roof != null:
			_roofs[_layout.pieces[i]] = roof
	_build_graph()
	_build_me()
	if not OS.get_cmdline_user_args().has("--no-folk"):
		_build_folk()
	_build_hud()
	print("TOWN %s (%s): %d spots, %d pieces, %d folk, built in %d ms" % [_site.display_name, _layout.culture,
			_layout.spots.size(), _layout.pieces.size(), _folk.size(), Time.get_ticks_msec() - began])
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--walk-test") or args.has("--demo"):
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

func _build_world() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.42, 0.55)
	sky_material.sky_horizon_color = Color(0.68, 0.66, 0.6)
	sky_material.ground_horizon_color = Color(0.4, 0.37, 0.32)
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.6, 0.58)
	env.fog_density = 0.004
	environment.environment = env
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


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
	_pivot.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 600.0
	_arm.add_child(_camera)
	_camera.make_current()
	_update_camera()


func _build_folk() -> void:
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
	var crowd: int = clampi(PopService.total(_site) / 120, 3, CROWD_MOST)
	for i: int in range(crowd):
		var group: PopGroupData = _pick_group(groups, total)
		var worn: Array[String] = []
		worn.assign(BodyView.COMMONER)
		if group.status == SimEnums.LegalStatus.ENSLAVED:
			worn.erase("boots")
		_add_walker(_crowd_figure(group.race_id, worn), false)


func _pick_group(groups: Array[PopGroupData], total: int) -> PopGroupData:
	var pick: int = _rng.randi_range(0, total - 1)
	for g: PopGroupData in groups:
		if pick < g.count:
			return g
		pick -= g.count
	return groups[0]


func _crowd_figure(race_id: StringName, worn: Array[String]) -> TownFigure:
	var male: bool = _rng.randf() < 0.5
	var face: FaceData = FaceService.random_face(_rng, _ctx.defs.races[race_id], male)
	var figure: TownFigure = TownFigure.new()
	add_child(figure)
	figure.setup_crowd(face, male, _rng.randf_range(0.1, 0.7), worn)
	return figure


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
	_walk_folk(delta)
	_show_roofs()
	var near: int = _layout.spot_near(Vector2(_me.position.x, _me.position.z))
	if near != _near_spot:
		_near_spot = near
	_prompt.visible = _near_spot >= 0 and not _menu_open
	if _prompt.visible:
		var key: String = "A" if _controls.using_pad else "E"
		_prompt.text = "[color=#%s]%s[/color]   %s" % [MenuStyle.GOLD.to_html(false), key, _layout.spots[_near_spot].label]


## The roof of the building you are in is not drawn, so you can see inside.
func _show_roofs() -> void:
	var piece: TownLayout.Piece = _layout.inside(Vector2(_me.position.x, _me.position.z))
	var roof: Node3D = null
	if piece != null and _roofs.has(piece):
		roof = _roofs[piece]
	if roof == _roof_hidden:
		return
	if _roof_hidden != null:
		_roof_hidden.visible = true
	_roof_hidden = roof
	if roof != null:
		roof.visible = false


func _update_camera() -> void:
	var at: Vector3 = _me.position
	var ahead: Vector2 = _controls.forward()
	var right: Vector2 = Vector2(-ahead.y, ahead.x)
	_pivot.position = at + Vector3(right.x * CAMERA_SIDE, CAMERA_HEIGHT, right.y * CAMERA_SIDE)
	# The arm reaches out along its own +Z, so it points back from the way you look, and up by the pitch.
	_pivot.rotation = Vector3(-_controls.pitch, _controls.yaw + PI, 0.0)


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
		actions.append(_choose.bind(i))
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
