extends Node3D
## A duel to play: you against an NPC, in a small arena, on a real small world so wounds stay after it.
##
## godot --path . res://src/view/duel/duel_scene.tscn
## You walk and look freely, and blows land on whoever is in front of you. Q or the middle button locks on to someone.
## The way the mouse last moved is the way you strike and guard. Left click strikes, Shift-click thrusts, right click
## guards, Shift runs, hold Y to give up. An Xbox controller works too: see FightControls.
## At the end: K kills, Enter spares, T lets 30 days pass, R starts a new fight.
## Options: --auto (two NPCs), --seed=number, --out=path and --shots=seconds,seconds to save pictures and quit,
## --no-shield, --weapon=axe, --maim=hand_r,shin_l to start the second fighter with those parts already gone,
## --side for a camera from the side, --slay=seconds to kill the second fighter then, to watch the fall.

const ARENA_PEOPLE: int = 150
const CAMERA_BACK: float = 2.5
const CAMERA_UP: float = 1.75
const CAMERA_LOOK_UP: float = 1.15
const CAMERA_SIDE: float = 0.55
const CAMERA_SIDE_OVER: float = 1.9
## Force a killing blow throws a body with, and how much of it goes upwards.
const FALL_PUSH: float = 30.0
const FALL_LIFT: float = 0.15
const FALL_PUSH_QUIET: float = 7.0
## The bone each part's blow lands on, where it is not a limb's own.
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
var _fight: DuelFight
var _agent_a: DuelAgent
var _agent_b: DuelAgent
var _view_a: DuelFighterView
var _view_b: DuelFighterView
var _camera: Camera3D
var _left_panel: FightVitals
var _log: KillFeed
var _prompt: HudPlate
var _aim_label: AimArrows
var _auto: bool = false
var _shots: Array[float] = []
var _shot_index: int = 0
var _elapsed: float = 0.0
var _decided: bool = false
var _world_seed: int = 1
var _end_prompt: String = ""


func _ready() -> void:
	_auto = OS.get_cmdline_user_args().has("--auto")
	_world_seed = ViewUtil.arg("seed", "1").to_int()
	for item: String in ViewUtil.arg("shots", "").split(",", false):
		_shots.append(item.to_float())
	_build_arena()
	_build_hud()
	_start_fight()


func _build_arena() -> void:
	ArenaStage.build(self, 11.5, 14)
	_camera = Camera3D.new()
	_camera.fov = 58.0
	add_child(_camera)


func _build_hud() -> void:
	MenuStyle.apply(self)
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	var layer: Control = MenuStyle.hud_root(canvas)
	_left_panel = _vitals()
	layer.add_child(_left_panel)
	_log = KillFeed.new()
	_place(_log, Vector2(0.0, 0.0), Vector2(22.0, 16.0), Vector2(460.0, 0.0))
	layer.add_child(_log)
	_prompt = _plate(layer, &"BarePanel", 0.0, Vector2(0.5, 0.0), Vector2(0.0, 14.0), 18)
	_aim_label = AimArrows.new()
	layer.add_child(_aim_label)


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


## Pins a control to a point of the screen, with its box measured from there.
func _place(control: Control, anchor: Vector2, at: Vector2, size_px: Vector2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = at.x
	control.offset_top = at.y
	control.offset_right = at.x + size_px.x
	control.offset_bottom = at.y + size_px.y


func _start_fight() -> void:
	_clear_people()
	if _kernel == null:
		var config: WorldGenConfig = WorldGenConfig.new()
		config.world_seed = _world_seed
		config.named_target = ARENA_PEOPLE
		_hub = EventHub.new()
		add_child(_hub)
		_kernel = SimKernel.new(WorldGenerator.generate(config, DefRegistry.catalog), DefRegistry.catalog, _hub)
	var ctx: SimContext = _kernel.ctx
	var ids: Array[int] = _pick_fighters(ctx)
	var weapon: StringName = StringName(ViewUtil.arg("weapon", "arming_sword"))
	var shield: bool = not OS.get_cmdline_user_args().has("--no-shield")
	var armour: Array[StringName] = [&"mail_hauberk", &"mail_coif", &"helmet", &"trousers", &"boots"]
	for id: int in ids:
		Actions.equip(ctx, id, weapon, shield, armour)
	for part: String in ViewUtil.arg("maim", "").split(",", false):
		LimbService.sever(ctx, ctx.character(ids[1]), StringName(part), 0.0)
	_fight = DuelFight.new(ctx, ids[0], ids[1])
	_agent_a = DuelAgent.new(_fight, _fight.a)
	_agent_b = DuelAgent.new(_fight, _fight.b)
	_view_a = _make_view(_fight.a)
	_view_b = _make_view(_fight.b)
	for part: String in ViewUtil.arg("maim", "").split(",", false):
		LimbView.drop_piece(self, _view_b.body, StringName(part), _view_b.face, _view_b.male, _view_b.age, _view_b.worn, part == "neck", _view_b.tint)
	_decided = false
	_elapsed = 0.0
	_elapsed = 0.0
	_log.wipe()
	_note("[color=#cccccc]%s faces %s.[/color]" % [_name_of(ids[0]), _name_of(ids[1])])
	if not _auto:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_controls.begin(_fight.a)
		_controls.allow_flee = false
		_camera.global_position = Vector3(_fight.a.position.x, FightControls.CAMERA_UP, _fight.a.position.y - FightControls.CAMERA_BACK)


func _clear_people() -> void:
	for child: Node in get_children():
		if child is DuelFighterView or child is RigidBody3D:
			child.queue_free()


## The two fittest adults in the world who have not been in a fight here yet.
func _pick_fighters(ctx: SimContext) -> Array[int]:
	var out: Array[int] = []
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if not ctx.is_adult(c) or GeneticsService.dominant_race(c) != &"human":
			continue
		if c.warband_id >= 0 or c.occupation == &"ruler" or not c.body.wounds.is_empty() or not c.body.lost_parts.is_empty():
			continue
		out.append(id)
		if out.size() == 2:
			break
	return out


func _make_view(fighter: DuelFighter) -> DuelFighterView:
	var view: DuelFighterView = DuelFighterView.new()
	add_child(view)
	var c: CharacterData = _kernel.ctx.character(fighter.character_id)
	var race: RaceDef = _kernel.ctx.defs.races[GeneticsService.dominant_race(c)]
	var share: float = clampf((_kernel.ctx.age_years(c) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)
	view.setup(fighter, c, share)
	return view


func _name_of(id: int) -> String:
	var ctx: SimContext = _kernel.ctx
	var c: CharacterData = ctx.character(id)
	if c == null:
		c = ctx.world.archived_characters.get(id, null)
	return c.given_name if c != null else "Someone"


## The winner's call. Only someone who won may make it, and an NPC makes it by their nature.
func _decide(kill: bool) -> void:
	if not _fight.over or _decided or _fight.winner_id < 0 or _kernel.ctx.character(_fight.loser_id) == null:
		return
	_decided = true
	if kill:
		_fight.finish()
		_note("[color=#e05040]%s finishes %s.[/color]" % [_name_of(_fight.winner_id), _name_of(_fight.loser_id)], true)
	else:
		_fight.spare()
		_note("%s spares %s." % [_name_of(_fight.winner_id), _name_of(_fight.loser_id)], true)


func _pass_time(days: int) -> void:
	_kernel.advance_days(days)
	_note("[color=#a0c0e0]%d days pass.[/color]" % days, true)
	for id: int in [_fight.a.character_id, _fight.b.character_id]:
		if _kernel.ctx.character(id) == null:
			var dead: CharacterData = _kernel.ctx.world.archived_characters.get(id, null)
			if dead != null and dead.death_cause != &"wounds":
				_note("%s has died (%s)." % [dead.given_name, dead.death_cause], true)


func _unhandled_input(event: InputEvent) -> void:
	if _auto:
		return
	match _controls.handle_event(event):
		FightControls.FINISH:
			_decide(true)
		FightControls.SPARE:
			_decide(false)
		FightControls.PASS_TIME:
			if _fight.over:
				_pass_time(30)
		FightControls.RESTART:
			_start_fight()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_controls.release_all()


func _update_aim_label() -> void:
	var active: bool = not _auto and not _fight.over
	var threat_guard: DuelFighter.Guard = DuelFighter.Guard.NONE
	if active:
		var coming: DuelFighter = _controls.threat(_fight, _fight.a)
		if coming != null:
			threat_guard = LocalFight.MEETS[coming.move]
	_aim_label.show_state(active, _controls.aim_guard, threat_guard, active and _controls.locked != null)


func _physics_process(delta: float) -> void:
	var first: DuelInput = _agent_a.decide(delta) if _auto else _controls.read(_fight, _fight.a, delta)
	var second: DuelInput = _agent_b.decide(delta)
	var slay_at: float = ViewUtil.arg("slay", "-1").to_float()
	if slay_at >= 0.0 and _elapsed >= slay_at and _kernel.ctx.character(_fight.b.character_id) != null and not _fight.over:
		LimbService.apply_blow(_kernel.ctx, _kernel.ctx.character(_fight.b.character_id), &"torso", &"pierce", 100000.0)
	_fight.advance(delta, first, second)
	if not _auto:
		_controls.after_step(_fight.a)
	_read_events()
	_view_a.update_view()
	_view_b.update_view()
	_elapsed += delta


func _read_events() -> void:
	for e: DuelEvent in _fight.events:
		_show_event(e)
	_fight.events.clear()


func _view_of(id: int) -> DuelFighterView:
	return _view_a if _view_a.character_id == id else _view_b


func _show_event(e: DuelEvent) -> void:
	var who: String = _name_of(e.character_id)
	var part_name: String = String(e.part_id)
	if _kernel.ctx.defs.body_parts.has(e.part_id):
		part_name = _kernel.ctx.defs.body_parts[e.part_id].display_name
	match e.kind:
		&"swing":
			_view_of(e.character_id).restart_clip()
		&"hit":
			_note("%s is struck on the %s: [color=%s]%s[/color]." % [who, part_name, LEVEL_COLORS.get(e.level, "#ffffff"), LEVEL_WORDS.get(e.level, "unhurt")])
			if e.character_id == _fight.a.character_id and not _auto:
				_controls.rumble(0.6)
			_splash(e.character_id, 0.6)
		&"severed":
			_note("[color=#ff4030]%s loses the %s![/color]" % [who, part_name], true)
			_splash(e.character_id, 1.6)
			_show_severed(e)
		&"parried":
			_note("%s parries." % who)
		&"guard_broken":
			_note("%s's guard is broken." % who)
		&"shield_lost":
			_note("%s can no longer hold a shield." % who)
		&"down":
			_note("[color=#e0a040]%s goes down.[/color]" % who, true)
			_fall(e.character_id, e.part_id, FALL_PUSH_QUIET)
		&"yielded":
			_note("[color=#e0a040]%s gives up.[/color]" % who, true)
		&"dead":
			_note("[color=#ff4030]%s is dead.[/color]" % who, true)
			_fall(e.character_id, e.part_id, FALL_PUSH if e.part_id != &"" else FALL_PUSH_QUIET)
		&"over":
			_on_over()


## A body falls away from whoever struck it.
func _fall(character_id: int, part_id: StringName, force: float) -> void:
	var view: DuelFighterView = _view_of(character_id)
	var other: DuelFighter = _fight.other_of(view.fighter)
	var away: Vector2 = (view.fighter.position - other.position).normalized()
	var push: Vector3 = (Vector3(away.x, FALL_LIFT, away.y)).normalized() * force
	var limb_bone: String = LimbView.BONES.get(part_id, "spine_03")
	var struck: String = STRUCK_BONES.get(part_id, limb_bone)
	view.go_limp(self, push, struck)


func _show_severed(e: DuelEvent) -> void:
	var view: DuelFighterView = _view_of(e.character_id)
	LimbView.drop_piece(self, view.body, e.part_id, view.face, view.male, view.age, view.worn, e.part_id == &"neck", view.tint)
	var c: CharacterData = _kernel.ctx.character(e.character_id)
	if c == null:
		c = _kernel.ctx.world.archived_characters.get(e.character_id, null)
	if c != null:
		view.show_body(c)


func _splash(character_id: int, amount: float) -> void:
	var view: DuelFighterView = _view_of(character_id)
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
	view.add_child(blood)
	blood.position = Vector3(0.0, 1.15, 0.1)
	get_tree().create_timer(1.2).timeout.connect(blood.queue_free)


func _on_over() -> void:
	_log.hold = true
	if _fight.winner_id >= 0:
		_note("[color=#ffffff]%s wins.[/color]" % _name_of(_fight.winner_id), true)
	if _auto:
		_decide(_kernel.ctx.character(_fight.winner_id) != null and _kernel.ctx.character(_fight.winner_id).traits.has(&"cruel"))
	elif _kernel.ctx.character(_fight.loser_id) != null and _fight.winner_id == _fight.a.character_id:
		_end_prompt = "X kills, A spares. Back lets 30 days pass. Start begins a new fight." if _controls.using_pad else "K kills, Enter spares. T lets 30 days pass. R starts a new fight."
		_prompt.text = _end_prompt
	else:
		_prompt.text = "Back lets 30 days pass. Start begins a new fight." if _controls.using_pad else "T lets 30 days pass. R starts a new fight."


## Every line goes to the console when the fight plays itself. Only who fell, and how it ended, goes on screen.
func _note(line: String, shown: bool = false) -> void:
	if shown:
		_log.add(line)
	if _auto:
		print(RegEx.create_from_string(r"\[.*?\]").sub(line, "", true))


func _process(delta: float) -> void:
	if _auto or OS.get_cmdline_user_args().has("--side"):
		_update_camera()
	else:
		_controls.update_camera(_camera, _fight.a, delta)
	if not _auto and not _fight.over:
		_prompt.text = ""
	_status(_left_panel, _fight.a)
	_update_aim_label()
	if _shot_index < _shots.size() and _elapsed >= _shots[_shot_index]:
		_take_shot()
	elif not ViewUtil.arg("out", "").is_empty() and _shot_index >= _shots.size():
		get_tree().quit(0)


func _take_shot() -> void:
	var path: String = ViewUtil.arg("out", "") % _shot_index
	_shot_index += 1
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)


func _update_camera() -> void:
	var me: DuelFighter = _fight.a
	var other: DuelFighter = _fight.b
	var ahead: Vector2 = (other.position - me.position).normalized()
	var right: Vector2 = Vector2(-ahead.y, ahead.x)
	# Stands off to one side once it is over, so whoever is on the ground can be seen.
	var eye: Vector2 = me.position - ahead * CAMERA_BACK + right * (CAMERA_SIDE_OVER if _fight.over else CAMERA_SIDE)
	var middle: Vector2 = (me.position + other.position) * 0.5
	if OS.get_cmdline_user_args().has("--side"):
		eye = middle + right * 3.2
		var close_up: String = ViewUtil.arg("watch", "")
		if not close_up.is_empty():
			var angle: float = deg_to_rad(close_up.to_float())
			var fallen: Vector3 = ViewUtil.find_skeleton(_view_b.body).to_global(ViewUtil.find_skeleton(_view_b.body).get_bone_global_pose(1).origin)
			_camera.global_position = fallen + Vector3(sin(angle) * 2.2, 1.5, cos(angle) * 2.2)
			_camera.look_at(fallen, Vector3.UP)
			return
	_camera.global_position = Vector3(eye.x, CAMERA_UP, eye.y)
	_camera.look_at(Vector3(middle.x, CAMERA_LOOK_UP, middle.y), Vector3.UP)


func _status(view: FightVitals, f: DuelFighter) -> void:
	var ctx: SimContext = _kernel.ctx
	var c: CharacterData = ctx.character(f.character_id)
	if c == null:
		c = ctx.world.archived_characters.get(f.character_id, null)
		var cause: String = c.death_cause if c != null else ""
		_show_vitals(view, c, 0.0, cause)
		return
	_show_vitals(view, c, f.stamina, "")
