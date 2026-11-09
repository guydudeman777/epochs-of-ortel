extends Node3D
## A small battle to play, on a small real world so that its dead and maimed stay that way.
##
## godot --path . res://src/view/duel/battle_scene.tscn
## You fight in the near line, walking and looking freely. Q or the middle button locks on to someone. Controls are in
## FightControls, for mouse and keys or an Xbox controller. Hold G to run for it and Y to give up, T lets 30 days pass
## once it is over, and R starts another.
## Options: --auto (all NPCs, camera circling), --size=8 a side, --seed=number, --out=path%d.png and --shots=seconds,seconds
## to save pictures and print frame rates then quit. The ground is a battle site of the world's land: --site=number, or
## --ground=kind (field, forest, hills, ford, beach, lake, marsh, outskirts) with --biome=name (temperate, desert, snow,
## ash and the rest) for the first site of that kind there. --hour=14 and --weather=clear|cloudy|overcast set the sky,
## and --watch=distance,height backs the circling camera off.
##
## Sent from the overworld, it fights Simulation.field_battle instead, with the real people and troop counts of the two bands,
## and hands the scene back when it is over. Those options then read --battle-out and --battle-shots.

const PEOPLE: int = 900
## The hour of the first watch of the day.
const DAWN_HOUR: float = 6.0
const FIELD_RADIUS: float = 17.0
const WALL_RADIUS: float = 21.0
const LINE_GAP: float = 1.9
const LINES_APART: float = 11.0
## Who stands in each line, repeated until it is full.
const NEAR_LINE: Array[StringName] = [&"man_at_arms", &"levy_spearman", &"levy_spearman", &"man_at_arms", &"pikeman", &"plate_knight"]
const FAR_LINE: Array[StringName] = [&"man_at_arms", &"levy_spearman", &"pikeman", &"man_at_arms", &"rebel_militia", &"plate_knight"]
const SIDE_NAMES: Array[String] = ["Red", "Blue"]
const SIDE_COLORS: Array[Color] = [Color(0.42, 0.08, 0.07), Color(0.1, 0.16, 0.38)]
## How many people have faces and full bodies at once, and how many steps further down the order one may slip before losing them.
const DETAILED: int = 8
const DETAILED_SLACK: int = 2
## At most this many bodies gain detail each frame, so the swap is never a stutter.
const DETAIL_PER_FRAME: int = 1
const CAMERA_LOOK_UP: float = 1.15
const AUTO_SETTLE_AFTER: float = 40.0
const WATCH_DISTANCE: float = 9.0
const WATCH_HEIGHT: float = 3.6
const WATCH_TURN: float = 0.12
## Force a killing blow throws a body with, and how much of it goes upwards.
const FALL_PUSH: float = 30.0
const FALL_LIFT: float = 0.15
const FALL_PUSH_QUIET: float = 7.0
const STRUCK_BONES: Dictionary[StringName, String] = {&"torso": "spine_03", &"abdomen": "spine_01", &"head": "head", &"neck": "spine_03"}
const LEVEL_WORDS: Dictionary[SimEnums.WoundLevel, String] = {
	SimEnums.WoundLevel.BRUISED: "bruised", SimEnums.WoundLevel.HURT: "hurt", SimEnums.WoundLevel.BADLY_HURT: "badly hurt",
	SimEnums.WoundLevel.CRIPPLED: "crippled", SimEnums.WoundLevel.RUINED: "ruined", SimEnums.WoundLevel.LOST: "gone",
}
const LEVEL_COLORS: Dictionary[SimEnums.WoundLevel, String] = {
	SimEnums.WoundLevel.BRUISED: "#d8c98a", SimEnums.WoundLevel.HURT: "#e0a040", SimEnums.WoundLevel.BADLY_HURT: "#e07030",
	SimEnums.WoundLevel.CRIPPLED: "#e03828", SimEnums.WoundLevel.RUINED: "#c01818", SimEnums.WoundLevel.LOST: "#808080",
}

var _controls: FightControls = FightControls.new()
var _hub: EventHub
var _kernel: SimKernel
var _fight: LocalFight
var _player: DuelFighter = null
var _agents: Dictionary[int, DuelAgent] = {}
var _views: Dictionary[int, DuelFighterView] = {}
var _inputs: Array[DuelInput] = []
var _camera: Camera3D
var _camera_look: Vector3 = Vector3.ZERO
var _left_panel: FightVitals
var _log: KillFeed
var _prompt: HudPlate
var _count: HudPlate
var _aim_label: AimArrows
var _auto: bool = false
var _shots: Array[float] = []
var _shot_index: int = 0
var _elapsed: float = 0.0
var _size: int = 8
var _reported: bool = false
var _battle: FieldBattle = null
var _finished_at: float = -1.0
var _ground: BattleGround = null
var _watch_distance: float = WATCH_DISTANCE
var _watch_height: float = WATCH_HEIGHT


func _ready() -> void:
	_battle = Simulation.field_battle
	_auto = OS.get_cmdline_user_args().has("--auto") or (OS.get_cmdline_user_args().has("--demo") and not OS.get_cmdline_user_args().has("--demo-stand"))
	_size = ViewUtil.arg("size", "8").to_int()
	for item: String in ViewUtil.arg("battle-shots" if _battle != null else "shots", "").split(",", false):
		_shots.append(item.to_float())
	var watch: PackedStringArray = ViewUtil.arg("watch", "").split(",", false)
	if watch.size() == 2:
		_watch_distance = watch[0].to_float()
		_watch_height = watch[1].to_float()
	_camera = Camera3D.new()
	_camera.fov = 58.0
	add_child(_camera)
	_build_hud()
	# The head model takes seconds to load, so that happens now and not when the first face comes near.
	load(FaceView.HEAD_SCENE)
	load(FaceView.GROWN_HAIR_SCENE)
	if _battle != null:
		_kernel = Simulation.kernel
		_ground = _battle.ground
		_set_stage()
		_start_field_battle()
		return
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = ViewUtil.arg("seed", "1").to_int()
	config.named_target = PEOPLE
	_hub = EventHub.new()
	add_child(_hub)
	_kernel = SimKernel.new(WorldGenerator.generate(config, DefRegistry.catalog), DefRegistry.catalog, _hub)
	_ground = _pick_ground(_kernel.ctx)
	_set_stage()
	_start_battle()


## The site asked for on the command line, or a field in the Marches.
func _pick_ground(ctx: SimContext) -> BattleGround:
	var sites: BattleSitesDef = BattleSitesDef.of_land(ctx.world.map.land_id) if ctx.world.map.land_id != &"" else null
	if sites == null or sites.sites.is_empty():
		return BattleGround.flat()
	var site: BattleSiteDef = null
	var asked: String = ViewUtil.arg("site", "")
	var kind: StringName = StringName(ViewUtil.arg("ground", "field"))
	if not asked.is_empty():
		site = sites.sites[clampi(asked.to_int(), 0, sites.sites.size() - 1)]
	else:
		site = sites.first_of(kind, LandDef.BIOME_NAMES.find(StringName(ViewUtil.arg("biome", "temperate"))))
		if site == null:
			site = sites.first_of(kind)
		if site == null:
			site = sites.sites[0]
	print("FIELD site %d, %s in %s, at %s" % [site.id, site.kind, LandDef.BIOME_NAMES[site.biome], site.position])
	return BattleGround.of_site(ctx, site)


## The field and the sky over it. Level ground with a fence round it where there is no land to cut a field from.
func _set_stage() -> void:
	_controls.ground = _ground
	if _ground == null or _ground.samples <= 2:
		ArenaStage.build(self, WALL_RADIUS, 0 if _battle != null else 24)
		return
	var ctx: SimContext = _kernel.ctx
	var hour: float = fposmod(DAWN_HOUR + float(ctx.world.calendar.watch) * 24.0 / float(CalendarData.WATCHES_PER_DAY), 24.0)
	if _battle == null:
		hour = 10.5
	var asked: String = ViewUtil.arg("hour", "")
	if not asked.is_empty():
		hour = fposmod(asked.to_float(), 24.0)
	var weather_seed: int = ctx.world.world_seed * 7919 + ctx.world.calendar.day_index * 131 + (_ground.site.id if _ground.site != null else 0)
	FieldStage.build(self, _ground, hour, weather_seed)


func _build_hud() -> void:
	MenuStyle.apply(self)
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	var layer: Control = MenuStyle.hud_root(canvas)
	_left_panel = _vitals()
	layer.add_child(_left_panel)
	_log = KillFeed.new()
	_pin(_log, Vector2(0.0, 0.0), Vector2(22.0, 16.0), Vector2(460.0, 0.0))
	layer.add_child(_log)
	_count = _plate(layer, &"BarePanel", 0.0, Vector2(0.5, 0.0), Vector2(0.0, 10.0), 22)
	_prompt = _plate(layer, &"BarePanel", 0.0, Vector2(0.5, 0.0), Vector2(0.0, 52.0), 17)
	_aim_label = AimArrows.new()
	layer.add_child(_aim_label)


## The two sides and how many each still has standing, in gilt.
func _score(left: String, left_count: int, right_count: int, right: String) -> String:
	var gold: String = MenuStyle.BRIGHT.to_html(false)
	return "%s   [b][color=#%s]%d[/color][/b]   ·   [b][color=#%s]%d[/color][/b]   %s" % [left, gold, left_count, gold, right_count, right]


func _plate(layer: Control, variation: StringName, width: float, anchor: Vector2, at: Vector2, font_size: int) -> HudPlate:
	var plate: HudPlate = HudPlate.new(variation, width, font_size)
	layer.add_child(plate)
	plate.pin(anchor, at)
	return plate


## The player's own bars, in the bottom left corner. They draw upward from the bottom, so more wounds push them up.
func _vitals() -> FightVitals:
	var out: FightVitals = FightVitals.new()
	out.anchor_left = 0.0
	out.anchor_right = 0.0
	out.anchor_top = 1.0
	out.anchor_bottom = 1.0
	out.offset_left = 30.0
	out.offset_right = 380.0
	out.offset_top = -420.0
	out.offset_bottom = -18.0
	return out


## Fills a fighter's bars and wounds, or clears them when there is nobody to show.
func _show_vitals(view: FightVitals, c: CharacterData, breath: float, dead: String) -> void:
	if c == null:
		view.clear()
		return
	var ctx: SimContext = _kernel.ctx
	var words: Array[String] = []
	var colors: Array[Color] = []
	for part_id: StringName in ctx.defs.body_part_ids:
		var level: SimEnums.WoundLevel = LimbService.part_level(ctx, c, part_id)
		if level == SimEnums.WoundLevel.UNHURT:
			continue
		words.append("%s: %s" % [ctx.defs.body_parts[part_id].display_name, LEVEL_WORDS[level]])
		colors.append(Color.html(LEVEL_COLORS[level]))
	for wound: WoundData in c.body.wounds:
		if wound.infection > 0.0:
			words.append("%s is festering" % ctx.defs.body_parts[wound.part_id].display_name)
			colors.append(Color(0.56, 0.75, 0.25))
	var others: Dictionary[String, float] = {"Fight": LimbService.fighting_capacity(ctx, c), "Walk": LimbService.mobility(ctx, c)}
	view.show_fighter(c.given_name, c.body.blood, breath, others, words, colors, dead)


func _pin(control: Control, anchor: Vector2, at: Vector2, size_px: Vector2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = at.x
	control.offset_top = at.y
	control.offset_right = at.x + size_px.x
	control.offset_bottom = at.y + size_px.y


func _make_label(layer: Control, anchor: Vector2, at: Vector2, size_px: Vector2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override(&"font_size", font_size)
	label.theme_type_variation = &"HudLabel"
	layer.add_child(label)
	_pin(label, anchor, at, size_px)
	return label


func _start_battle() -> void:
	for child: Node in get_children():
		if child is DuelFighterView or child is RigidBody3D:
			child.queue_free()
	var ctx: SimContext = _kernel.ctx
	_fight = LocalFight.new(ctx)
	_fight.arena_radius = FIELD_RADIUS
	_fight.ground = _ground
	_agents.clear()
	_views.clear()
	_inputs.clear()
	_player = null
	_reported = false
	_log.wipe()
	var ids: Array[int] = _pick_people(ctx, _size * 2)
	var used: int = 0
	for side: int in range(2):
		var line: Array[StringName] = NEAR_LINE if side == 0 else FAR_LINE
		var count: int = mini(_size, (ids.size() - used) if side == 1 else ids.size() / 2)
		for i: int in range(count):
			var id: int = ids[used]
			used += 1
			var is_player: bool = side == 0 and i == count / 2 and not _auto
			# You get a sword and shield, so that the guards you know from the duel work the same.
			Actions.kit_out(ctx, id, &"man_at_arms" if is_player else line[i % line.size()])
			var across: float = (float(i) - float(count - 1) * 0.5) * LINE_GAP
			var along: float = LINES_APART * 0.5 * (-1.0 if side == 0 else 1.0)
			var f: DuelFighter = _fight.add_fighter(id, side, Vector2(across, along), Vector2(0.0, 1.0 if side == 0 else -1.0))
			_add_view(f, side)
			if is_player:
				_player = f
				_inputs.append(_controls.input)
			else:
				_agents[id] = DuelAgent.new(_fight, f)
				_inputs.append(null)
	_note("[color=#cccccc]%d against %d.[/color]" % [_fight.standing_on(0), _fight.standing_on(1)])
	if _player != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_controls.begin(_player)
		_inputs[_fight.fighters.find(_player)] = _controls.input
		_camera.global_position = Vector3(_player.position.x, _ground_at(_player.position) + FightControls.CAMERA_UP, _player.position.y - FightControls.CAMERA_BACK)
	else:
		_prompt.text = ""
	_camera_look = Vector3(0.0, _ground_at(Vector2.ZERO) + CAMERA_LOOK_UP, 0.0)


## The battle the two bands have come to, on the ground where they met.
func _start_field_battle() -> void:
	var ctx: SimContext = _kernel.ctx
	_fight = _battle.fight
	_take_those_who_came_on()
	_note("[color=#cccccc]%s, %d, against %s, %d.[/color]" % [_battle.label_of(0), _fight.strength_of(0), _battle.label_of(1), _fight.strength_of(1)])
	if _player != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_controls.begin(_player)
		_inputs[_fight.fighters.find(_player)] = _controls.input
		_camera.global_position = Vector3(_player.position.x, _ground_at(_player.position) + FightControls.CAMERA_UP, _player.position.y - FightControls.CAMERA_BACK)
	_camera_look = Vector3(0.0, _ground_at(Vector2.ZERO) + CAMERA_LOOK_UP, 0.0)


## Gives everyone new on the field a body and a mind.
func _take_those_who_came_on() -> void:
	for f: DuelFighter in _battle.joined:
		_add_view(f, f.side)
		if f == _battle.player_fighter and not _auto:
			_player = f
			_inputs.append(_controls.input)
		else:
			_agents[f.character_id] = DuelAgent.new(_fight, f)
			_inputs.append(null)
	_battle.joined.clear()


## Adults of the world still whole, in id order, with no one the world badly needs in charge of something.
func _pick_people(ctx: SimContext, wanted: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if not ctx.is_adult(c) or GeneticsService.dominant_race(c) != &"human" or c.warband_id >= 0 or c.occupation == &"ruler":
			continue
		if not c.body.wounds.is_empty() or not c.body.lost_parts.is_empty():
			continue
		out.append(id)
		if out.size() == wanted:
			break
	return out


func _add_view(f: DuelFighter, side: int) -> void:
	var view: DuelFighterView = DuelFighterView.new()
	add_child(view)
	var c: CharacterData = _kernel.ctx.character(f.character_id)
	var race: RaceDef = _kernel.ctx.defs.races[GeneticsService.dominant_race(c)]
	var share: float = clampf((_kernel.ctx.age_years(c) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)
	view.ground = _ground
	view.setup(f, c, share, SIDE_COLORS[side], false)
	_views[c.id] = view


func _name_of(id: int) -> String:
	var c: CharacterData = _person(id)
	return c.given_name if c != null else "Someone"


func _person(id: int) -> CharacterData:
	var c: CharacterData = _kernel.ctx.character(id)
	if c == null:
		c = _kernel.ctx.temp_characters.get(id, null)
	if c == null:
		c = _kernel.ctx.world.archived_characters.get(id, null)
	return c


func _unhandled_input(event: InputEvent) -> void:
	if _auto:
		return
	var asked: StringName = _controls.handle_event(event)
	if _battle != null:
		if asked == FightControls.SPARE:
			_field_battle_go_on()
		return
	match asked:
		FightControls.PASS_TIME:
			if _fight.over:
				_kernel.advance_days(30)
				_note("[color=#a0c0e0]30 days pass.[/color]", true)
				_report_fates()
		FightControls.RESTART:
			_start_battle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_controls.release_all()


## Enter once you are out of it settles the rest. Once it is settled, it takes you back to the map.
func _field_battle_go_on() -> void:
	if _battle.finished:
		_go_back_to_map()
	elif _fight.over or _player == null or _player.is_out():
		_battle.settle_the_rest()
		_on_over()


func _go_back_to_map() -> void:
	var map: Node = Simulation.overworld
	var summary: String = _battle.summary
	Simulation.field_battle = null
	Simulation.overworld = null
	var tree: SceneTree = get_tree()
	tree.root.remove_child(self)
	tree.root.add_child(map)
	tree.current_scene = map
	map.call(&"came_back", summary)
	queue_free()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _battle != null:
		if _battle.finished:
			return
		_battle.top_up(delta)
		_take_those_who_came_on()
	for i: int in range(_fight.fighters.size()):
		var f: DuelFighter = _fight.fighters[i]
		if f == _player:
			_inputs[i] = _controls.read(_fight, _player, delta)
		else:
			_inputs[i] = _agents[f.character_id].decide(delta)
	_fight.advance_all(delta, _inputs)
	if _player != null:
		_controls.after_step(_player)
	for e: DuelEvent in _fight.events:
		_show_event(e)
	_fight.events.clear()
	for id: int in _views:
		_views[id].update_view()


func _show_event(e: DuelEvent) -> void:
	var who: String = _name_of(e.character_id)
	var part_name: String = String(e.part_id)
	if _kernel.ctx.defs.body_parts.has(e.part_id):
		part_name = _kernel.ctx.defs.body_parts[e.part_id].display_name
	match e.kind:
		&"swing":
			_views[e.character_id].restart_clip()
		&"hit":
			_splash(e.character_id, 0.6)
			if _player != null and e.character_id == _player.character_id:
				_controls.rumble(0.6)
			if e.level >= SimEnums.WoundLevel.BADLY_HURT:
				_note("%s is struck on the %s: [color=%s]%s[/color]." % [who, part_name, LEVEL_COLORS.get(e.level, "#ffffff"), LEVEL_WORDS.get(e.level, "")])
		&"severed":
			_note("[color=#ff4030]%s loses the %s![/color]" % [who, part_name], true)
			_splash(e.character_id, 1.6)
			var view: DuelFighterView = _views[e.character_id]
			LimbView.drop_piece(self, view.body, e.part_id, view.face, view.male, view.age, view.worn, e.part_id == &"neck", view.tint)
			var c: CharacterData = _person(e.character_id)
			if c != null:
				view.show_body(c)
		&"down":
			_note("[color=#e0a040]%s goes down.[/color]" % who, true)
			_fall(e, FALL_PUSH_QUIET)
		&"yielded":
			_note("[color=#e0a040]%s gives up.[/color]" % who, true)
		&"fled":
			_note("[color=#a0a0c0]%s has fled the field.[/color]" % who, true)
			_views[e.character_id].visible = false
		&"dead":
			_note("[color=#ff4030]%s is dead.[/color]" % who, true)
			_fall(e, FALL_PUSH if e.part_id != &"" else FALL_PUSH_QUIET)
		&"over":
			_on_over()


## A body falls away from whoever struck it, or just down if nobody did.
func _fall(e: DuelEvent, force: float) -> void:
	var view: DuelFighterView = _views[e.character_id]
	var push: Vector3 = Vector3.ZERO
	if _views.has(e.by_id):
		var away: Vector2 = (view.fighter.position - _views[e.by_id].fighter.position).normalized()
		push = Vector3(away.x, FALL_LIFT, away.y).normalized() * force
	var limb_bone: String = LimbView.BONES.get(e.part_id, "spine_03")
	var struck: String = STRUCK_BONES.get(e.part_id, limb_bone)
	view.go_limp(self, push, struck)


func _splash(character_id: int, amount: float) -> void:
	var blood: CPUParticles3D = CPUParticles3D.new()
	blood.one_shot = true
	blood.emitting = true
	blood.amount = int(24.0 * amount)
	blood.lifetime = 0.55
	blood.explosiveness = 0.95
	blood.direction = Vector3.UP
	blood.spread = 70.0
	blood.initial_velocity_min = 1.0
	blood.initial_velocity_max = 2.6
	blood.gravity = Vector3(0.0, -8.0, 0.0)
	blood.scale_amount_min = 0.012
	blood.scale_amount_max = 0.03
	var drop: SphereMesh = SphereMesh.new()
	drop.radius = 1.0
	drop.height = 2.0
	drop.radial_segments = 6
	drop.rings = 3
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.albedo_color = Color(0.42, 0.02, 0.02)
	drop.material = red
	blood.mesh = drop
	_views[character_id].add_child(blood)
	blood.position = Vector3(0.0, 1.15, 0.1)
	get_tree().create_timer(1.2).timeout.connect(blood.queue_free)


func _on_over() -> void:
	_log.hold = true
	if _battle != null:
		_battle.finish()
		_finished_at = _elapsed
		_note("[color=#ffffff]%s[/color]" % _battle.summary.replace("\n", "\n"), true)
		_prompt.text = "A returns to the map." if _controls.using_pad else "Enter returns to the map."
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if _fight.winning_side >= 0:
		_note("[color=#ffffff]%s holds the field.[/color]" % SIDE_NAMES[_fight.winning_side], true)
	else:
		_note("Nobody holds the field.", true)
	_report_fates()
	_prompt.text = "Back lets 30 days pass. Start begins another." if _controls.using_pad else "T lets 30 days pass. R starts another."


## How it came out for everyone, as the world now has it.
func _report_fates() -> void:
	var dead: int = 0
	var maimed: int = 0
	var fled: int = 0
	var unhurt: int = 0
	var limbs: int = 0
	for f: DuelFighter in _fight.fighters:
		var c: CharacterData = _kernel.ctx.character(f.character_id)
		if c == null:
			dead += 1
			continue
		limbs += c.body.lost_parts.size()
		if not c.body.lost_parts.is_empty():
			maimed += 1
		elif c.body.wounds.is_empty():
			unhurt += 1
		if f.state == DuelFighter.State.FLED:
			fled += 1
	_note("[color=#cccccc]Dead %d, maimed %d (%d limbs), fled %d, unhurt %d.[/color]" % [dead, maimed, limbs, fled, unhurt], true)


## Every line goes to the console when the fight plays itself. Only who fell, and how it ended, goes on screen.
func _note(line: String, shown: bool = false) -> void:
	if shown:
		_log.add(line)
	if _auto:
		print(RegEx.create_from_string(r"\[.*?\]").sub(line, "", true))


## The people nearest the camera get faces. Everyone else is one of the crowd.
func _update_detail() -> void:
	var order: Array[int] = []
	order.assign(_views.keys())
	order.sort_custom(func(x: int, y: int) -> bool: return _camera.global_position.distance_squared_to(_views[x].global_position) < _camera.global_position.distance_squared_to(_views[y].global_position))
	var added: int = 0
	for rank: int in range(order.size()):
		var view: DuelFighterView = _views[order[rank]]
		if not view.visible:
			continue
		if rank < DETAILED and added < DETAIL_PER_FRAME and not view.is_near():
			view.set_near(true)
			added += 1
		elif rank >= DETAILED + DETAILED_SLACK and view.is_near():
			view.set_near(false)


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_detail()
	if _battle != null:
		_count.text = _score(_battle.label_of(0), _fight.strength_of(0), _fight.strength_of(1), _battle.label_of(1))
		_update_field_prompt()
	else:
		_count.text = _score(SIDE_NAMES[0], _fight.standing_on(0), _fight.standing_on(1), SIDE_NAMES[1])
	_show_status()
	_update_aim_label()
	var out_arg: String = "battle-out" if _battle != null else "out"
	if _shot_index < _shots.size() and _elapsed >= _shots[_shot_index]:
		_take_shot()
	elif _battle == null and not ViewUtil.arg(out_arg, "").is_empty() and _shot_index >= _shots.size():
		get_tree().quit(0)


## What happens next, once you can do no more. Playing by itself, it just goes on.
func _update_field_prompt() -> void:
	if OS.get_cmdline_user_args().has("--demo-stand"):
		if _battle.finished or (_player != null and _player.is_out()):
			_field_battle_go_on()
		return
	if _auto:
		if _battle.finished and _elapsed - _finished_at > 2.0:
			print("DEMO battle over: %s" % _battle.summary.replace("\n", " "))
			_go_back_to_map()
		elif not _battle.finished and _elapsed > AUTO_SETTLE_AFTER:
			_battle.settle_the_rest()
			_on_over()
		return
	if not _battle.finished and _player != null and _player.is_out():
		_prompt.text = "You are out of it. A lets the rest be decided." if _controls.using_pad else "You are out of it. Enter lets the rest be decided."


func _take_shot() -> void:
	var path: String = ViewUtil.arg("battle-out" if _battle != null else "out", "") % _shot_index
	_shot_index += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("STATS t=%.1f fps=%d draw_calls=%d primitives=%d" % [_elapsed, Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _update_camera(delta: float) -> void:
	if _player != null and not _player.is_out():
		_controls.update_camera(_camera, _player, delta)
		return
	else:
		# Circles whatever is left of the fight.
		var sum: Vector2 = Vector2.ZERO
		var count: int = 0
		for f: DuelFighter in _fight.fighters:
			if not f.is_out():
				sum += f.position
				count += 1
		var middle: Vector2 = sum / float(maxi(count, 1))
		var angle: float = _elapsed * WATCH_TURN
		var spot: Vector2 = middle + Vector2(sin(angle), cos(angle)) * _watch_distance
		var eye: Vector3 = Vector3(spot.x, maxf(_ground_at(spot), _ground_at(middle)) + _watch_height, spot.y)
		var keep: float = clampf(delta * 1.5, 0.0, 1.0)
		if _elapsed < 0.2:
			keep = 1.0
		_camera.global_position = _camera.global_position.lerp(eye, keep)
		_camera_look = _camera_look.lerp(Vector3(middle.x, _ground_at(middle) + 1.0, middle.y), keep)
	_camera.look_at(_camera_look, Vector3.UP)


func _ground_at(at: Vector2) -> float:
	return _ground.height_at(at) if _ground != null else 0.0


func _update_aim_label() -> void:
	var active: bool = _player != null and not _player.is_out() and not _fight.over
	var threat_guard: DuelFighter.Guard = DuelFighter.Guard.NONE
	if active:
		var coming: DuelFighter = _controls.threat(_fight, _player)
		if coming != null:
			threat_guard = LocalFight.MEETS[coming.move]
		_prompt.text = ""
	_aim_label.show_state(active, _controls.aim_guard, threat_guard, active and _controls.locked != null)


func _show_status() -> void:
	if _player != null:
		_status(_left_panel, _player)
	else:
		_left_panel.clear()


func _status(view: FightVitals, f: DuelFighter) -> void:
	var ctx: SimContext = _kernel.ctx
	var c: CharacterData = _person(f.character_id)
	if c == null:
		view.clear()
		return
	if ctx.character(f.character_id) == null:
		_show_vitals(view, c, 0.0, c.death_cause)
		return
	_show_vitals(view, c, f.stamina, "")
