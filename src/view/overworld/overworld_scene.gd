class_name OverworldScene
extends Node3D
## The game: you, a nobody, on a real map of the living world. It reads state, sends what you decide through Actions, and
## moves the clock on while you travel. Time stands still when you do.
##
## godot --path . res://src/view/overworld/overworld_scene.tscn
## Controls live in OverworldControls. Panels (C, I, P, K, L, J, N) live in GamePanels. Town walking goes through TownEntry.
## Options: --seed=number, --demo (plays itself into a fight), --out=path%d.png and --shots=seconds,seconds to save pictures,
## --zoom=height and --look=x,y to frame them, --panel=name to open a panel.

class MenuOption:
	var label: String = ""
	var action: Callable

	func _init(text: String, what: Callable) -> void:
		label = text
		action = what


const SAVE_PATH: String = "user://ortel_save.res"
const MENU_SCENE: String = "res://src/view/menu/main_menu.tscn"
const BATTLE_SCENE: String = "res://src/view/duel/battle_scene.tscn"
const WATCHES_PER_SECOND: float = 5.0
const MAX_WATCHES_PER_FRAME: int = 4
const TOWN_NAME_SIZE: float = 0.0013
const TOWN_NAME_HEIGHT: float = 24.0
const ENTER_TOWN_RANGE: float = 34.0
const ESCAPE_TRY_EVERY_DAYS: int = 7
const MENU_WIDTH: float = 560.0
const FACTION_COLORS: Array[Color] = [
	Color(0.85, 0.4, 0.32), Color(0.62, 0.78, 0.42), Color(0.86, 0.82, 0.6), Color(0.62, 0.56, 0.9),
	Color(0.92, 0.66, 0.3), Color(0.45, 0.72, 0.9), Color(0.82, 0.48, 0.72), Color(0.5, 0.82, 0.72),
]
const REASONS: Dictionary[StringName, String] = {
	&"no_gold": "You cannot pay for that.", &"not_adult": "You are too young for that.",
	&"forbidden_by_law": "The law here forbids it.", &"no_recruits": "Nobody here will sign on.",
	&"no_equipment": "The town cannot arm them.", &"no_tech": "Nobody here knows that craft.",
	&"at_war": "They are at war with your people and will not deal with you.", &"no_stock": "The market has none.",
	&"no_vacancy": "They have no place for you.", &"unfit": "Your wounds will not let you.",
	&"caught": "You were caught, and beaten for it.", &"not_leader": "That is your leader's decision.",
	&"no_buyers": "Nobody here can pay for them.", &"no_market": "There is no market here.",
	&"caught_again": "They are on you again and there is nowhere left to run.", &"on_the_road": "You must be in a town.",
	&"in_debt": "You owe too much already.", &"too_few_people": "There are not enough people here to build and man stronger walls.",
	&"walls_at_most": "The walls are as strong as this town can make them.", &"already_in_warband": "You already march with a band.",
}

var _kernel: SimKernel
var _controls: OverworldControls
var _panels: GamePanels
var _ctx: SimContext
var _land: Node3D
var _tokens: Dictionary[int, BandToken] = {}
var _town_labels: Dictionary[int, Label3D] = {}
## How each town was last drawn, so it is drawn again when it grows or changes.
var _town_looks: Dictionary[int, String] = {}
var _town_nodes: Dictionary[int, Node3D] = {}
var _land_seen: int = 0
var _fixed_look: PackedFloat64Array = PackedFloat64Array()
var _clearings_seen: Dictionary[int, float] = {}
var _status: HudPlate
var _date: HudPlate
var _hint: HudPlate
var _hover: HudPlate
var _log: HudPlate
var _menu_panel: PanelContainer
var _menu_shade: ColorRect
var _menu_scroller: ScrollContainer
var _menu_title: Label
var _menu_text: RichTextLabel
var _menu_buttons: VBoxContainer
var _menu_open: bool = false
var _player_seen: int = -2
var _news: PackedStringArray = PackedStringArray()
var _clock: float = 0.0
var _town_count: int = 0
var _demo: bool = false
var _demo_time: float = 0.0
var _shots: Array[float] = []
var _shot_index: int = 0
var _elapsed: float = 0.0
var _town_shown: int = -1


func _ready() -> void:
	_demo = OS.get_cmdline_user_args().has("--demo")
	for item: String in ViewUtil.arg("shots", "").split(",", false):
		_shots.append(item.to_float())
	if World.state == null:
		var config: WorldGenConfig = WorldGenConfig.new()
		config.world_seed = ViewUtil.arg("seed", str(randi() % 100000)).to_int()
		World.new_game(config)
	_kernel = Simulation.kernel
	_ctx = _kernel.ctx
	GameClock.paused = true
	_land = Node3D.new()
	add_child(_land)
	var land_began: int = Time.get_ticks_msec()
	OverworldLand.build(_land, _ctx)
	print("Land drawn in %d ms" % (Time.get_ticks_msec() - land_began))
	_controls = OverworldControls.new()
	add_child(_controls)
	_controls.setup(self)
	_land_seen = _ctx.world.map.land_version
	_clearings_seen = _ctx.world.map.clearings.duplicate()
	_build_towns()
	_build_hud()
	_panels = GamePanels.new()
	add_child(_panels)
	_panels.setup(_ctx)
	if not ViewUtil.arg("panel", "").is_empty():
		_close_menu.call_deferred()
		_panels.show_panel.call_deferred(StringName(ViewUtil.arg("panel", "")))
	_sync_all_tokens()
	_fixed_look = ViewUtil.arg("look", "").split_floats(",", false)
	_controls.snap_camera()
	_player_seen = _ctx.world.player_character_id
	var c: CharacterData = _player()
	if _fixed_look.size() == 2:
		pass
	elif c != null and World.state.calendar.day_index == 0 and World.state.calendar.watch == 0:
		_open_start()
	else:
		_check_state()
	# Faces and hair take time to load, and a body seen for the first time should not wait on them.
	load(BodyView.BODY_SCENE)


# --- Building the screen ---------------------------------------------------

func _build_towns() -> void:
	for id: int in _ctx.settlement_ids():
		_add_town(_ctx.world.settlements[id])
	_town_count = _ctx.world.settlements.size()


func _add_town(s: SettlementData) -> void:
	var town: Node3D = OverworldLand.build_town(_land, _ctx, s)
	_town_nodes[s.id] = town
	_town_looks[s.id] = TownView.look_of(_ctx, s)
	var label: Label3D = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.pixel_size = TOWN_NAME_SIZE
	label.font_size = 24
	label.outline_size = 8
	MenuStyle.style_label_3d(label)
	label.position = Vector3(0.0, TOWN_NAME_HEIGHT, 0.0)
	town.add_child(label)
	_town_labels[s.id] = label
	_refresh_town_label(s)


func _refresh_town_label(s: SettlementData) -> void:
	var label: Label3D = _town_labels[s.id]
	label.text = s.display_name
	label.modulate = FACTION_COLORS[s.faction_id % FACTION_COLORS.size()]


func _build_hud() -> void:
	MenuStyle.apply(self)
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	var layer: Control = MenuStyle.hud_root(canvas)
	_status = _plate(layer, &"HudPanel", 0.0, Vector2(0.0, 0.0), Vector2(16.0, 14.0))
	_date = _plate(layer, &"BannerPanel", 0.0, Vector2(1.0, 0.0), Vector2(-16.0, 14.0), 18)
	_hint = _plate(layer, &"HudPanel", 0.0, Vector2(0.5, 1.0), Vector2(0.0, -14.0), 15)
	_log = _plate(layer, &"HudPanel", 500.0, Vector2(0.0, 1.0), Vector2(16.0, -60.0), 15)
	_hover = _plate(layer, &"HudPanel", 0.0, Vector2(0.0, 0.0), Vector2(0.0, 0.0), 15)
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
	_menu_scroller = ScrollContainer.new()
	_menu_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_buttons = VBoxContainer.new()
	_menu_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_buttons.add_theme_constant_override(&"separation", 6)
	_menu_scroller.add_child(_menu_buttons)
	column.add_child(_menu_title)
	column.add_child(MenuStyle.rule())
	column.add_child(_menu_text)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 4.0)
	column.add_child(gap)
	column.add_child(_menu_scroller)
	_menu_panel.add_child(column)
	layer.add_child(_menu_panel)
	_menu_panel.visible = false


func _plate(layer: Control, variation: StringName, width: float, anchor: Vector2, at: Vector2, font_size: int = 0) -> HudPlate:
	var plate: HudPlate = HudPlate.new(variation, width, font_size)
	layer.add_child(plate)
	plate.pin(anchor, at)
	return plate


## Shrinks the menu round what it holds, keeps it in the middle, and lets a long list scroll.
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


# --- Who and where you are -------------------------------------------------

func _player() -> CharacterData:
	return _ctx.character(_ctx.world.player_character_id)


func my_band() -> WarbandData:
	var c: CharacterData = _player()
	return _ctx.warband(c.warband_id) if c != null else null


func i_lead_it(band: WarbandData) -> bool:
	return band != null and band.leader_id == _ctx.world.player_character_id


## The point the view follows: your band, or the town you are in.
func my_place() -> Vector2:
	var band: WarbandData = my_band()
	if band != null:
		return WarbandOps.place_of(_ctx, band)
	var c: CharacterData = _player()
	if c != null and _ctx.world.map.positions.has(c.settlement_id):
		return _ctx.world.map.positions[c.settlement_id]
	return (_ctx.terrain().low + _ctx.terrain().high) * 0.5


func _is_travelling(band: WarbandData) -> bool:
	return band != null and (band.has_destination or band.chase_band_id >= 0)


# --- Time ------------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	_controls.steer_and_turn(delta)
	if _demo:
		_run_demo(delta)
	if not is_menu_open() and is_inside_tree():
		_run_clock(delta)
	# A choice may just have sent the whole scene off to a battle.
	if not is_inside_tree():
		return
	_update_tokens(delta)
	_controls.update_camera(delta)
	_update_hud()
	if _shot_index < _shots.size() and _elapsed >= _shots[_shot_index]:
		_take_shot()
	elif not ViewUtil.arg("out", "").is_empty() and _shot_index >= _shots.size() and not _demo:
		get_tree().quit(0)


func _take_shot() -> void:
	var path: String = ViewUtil.arg("out", "") % _shot_index
	_shot_index += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("OVERWORLD t=%.1f fps=%d draw_calls=%d primitives=%d" % [_elapsed, Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _time_should_run() -> bool:
	if _controls.time_speed() <= 0.0:
		return false
	var band: WarbandData = my_band()
	if band == null:
		return _controls.wants_time()
	if not i_lead_it(band):
		return true
	return _is_travelling(band) or _controls.wants_time()


func _run_clock(delta: float) -> void:
	if not _time_should_run():
		_clock = 0.0
		return
	_clock += delta * WATCHES_PER_SECOND * _controls.time_speed() * (4.0 if _demo else 1.0)
	var ran: int = 0
	while _clock >= 1.0 and ran < MAX_WATCHES_PER_FRAME:
		_clock -= 1.0
		ran += 1
		_kernel.advance_watch()
		_sync_all_tokens()
		_check_state()
		if _menu_open:
			_clock = 0.0
			return
	_clock = minf(_clock, 1.0)


## Looks at the world as it now stands, and asks you whatever it needs to ask you.
func _check_state() -> void:
	if _ctx.world.player_character_id != _player_seen:
		_player_seen = _ctx.world.player_character_id
		_open_succession()
		return
	var c: CharacterData = _player()
	if c == null:
		_open_line_ended()
		return
	if _ctx.world.encounter_band_id >= 0:
		_open_encounter()
		return
	if LegalService.is_bonded(c):
		_open_captive()
		return
	var band: WarbandData = my_band()
	if band == null:
		enter_town(c.settlement_id)
		return
	if band.at_settlement_id >= 0 and _town_shown != band.at_settlement_id and i_lead_it(band):
		_town_shown = band.at_settlement_id
		enter_town(band.at_settlement_id)
		return
	if band.at_settlement_id < 0:
		_town_shown = -1
	if not _news.is_empty():
		_open_news()


func _open_news() -> void:
	var words: String = "\n".join(_news)
	_news = PackedStringArray()
	_open_menu("Word comes", words, [MenuOption.new("Go on", _close_menu)])


# --- Menus -----------------------------------------------------------------

func _open_menu(title: String, words: String, options: Array[MenuOption]) -> void:
	_menu_open = true
	_menu_title.text = title
	_menu_text.text = words
	for child: Node in _menu_buttons.get_children():
		_menu_buttons.remove_child(child)
		child.queue_free()
	var first: Button = null
	for option: MenuOption in options:
		var button: Button = Button.new()
		button.text = option.label
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 40.0)
		button.pressed.connect(option.action)
		_menu_buttons.add_child(button)
		if first == null:
			first = button
	_menu_panel.visible = true
	_menu_shade.visible = true
	_fit_menu.call_deferred()
	if first != null:
		first.grab_focus()


func _close_menu() -> void:
	_menu_open = false
	_menu_panel.visible = false
	_menu_shade.visible = false
	_check_state()


func _reason(result: ActionResult) -> String:
	return REASONS.get(result.reason, "That cannot be done: %s." % String(result.reason).replace("_", " "))


func _open_start() -> void:
	var c: CharacterData = _player()
	var s: SettlementData = _ctx.settlement(c.settlement_id)
	var kin: String = ""
	var heir: CharacterData = SuccessionService.find_heir(_ctx, c)
	if heir != null:
		kin = " Your only kin is %s, in the same town. If you die, what little you have is theirs, and so is the story." % heir.given_name
	var standing: String = "free" if c.legal.status == SimEnums.LegalStatus.FREE else "bonded"
	var hand: String = "nothing to your hand"
	if _ctx.defs.weapons.has(c.equipment.weapon_id):
		hand = "a %s to your hand" % _ctx.defs.weapons[c.equipment.weapon_id].display_name.to_lower()
	var words: String = "You are %s, a %s %s of %s, %d years old. You have %d coin, no name anyone knows, and %s.%s\n\nThe world will not wait for you. Lords, slavers and bandits are already on the roads." % [
			c.given_name, standing, GeneticsService.dominant_race(c), s.display_name if s != null else "nowhere", floori(_ctx.age_years(c)), c.inventory.gold, hand, kin]
	_open_menu("A nobody", words, [MenuOption.new("Begin", _close_menu)])


func _open_succession() -> void:
	var c: CharacterData = _player()
	if c == null:
		_open_line_ended()
		return
	var place: SettlementData = _ctx.settlement(c.settlement_id)
	var words: String = "You are dead. The name goes on with %s, a %d year old %s%s. What you owned is theirs now, and the band you led follows whoever is next in it, if anyone is." % [
			c.given_name, floori(_ctx.age_years(c)), GeneticsService.dominant_race(c), " in %s" % place.display_name if place != null else ""]
	_town_shown = -1
	_sync_all_tokens()
	_open_menu("Your heir", words, [MenuOption.new("Go on as %s" % c.given_name, _close_menu)])


func _open_line_ended() -> void:
	_open_menu("The line has ended", "There is nobody left of your blood. The world goes on without you.", [MenuOption.new("Start again in a new world", _new_world)])


func _open_pause() -> void:
	_open_menu("Ortel waits", "Time stands still while you think.", [
		MenuOption.new("Go on", _close_menu),
		MenuOption.new("Save", _save_from_pause),
		MenuOption.new("Load the saved life", _load_from_pause),
		MenuOption.new("To the title", func() -> void: get_tree().change_scene_to_file(MENU_SCENE)),
		MenuOption.new("Leave the game", func() -> void: get_tree().quit()),
	])


func _save_from_pause() -> void:
	var saved: Error = World.save_game(SAVE_PATH)
	_news.append("Saved." if saved == OK else "Could not save: %s." % error_string(saved))
	_close_menu()


func _load_from_pause() -> void:
	if FileAccess.file_exists(SAVE_PATH) and World.load_game(SAVE_PATH) == OK:
		get_tree().reload_current_scene()


func _new_world() -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = randi() % 100000
	World.new_game(config)
	get_tree().reload_current_scene()


func _open_encounter() -> void:
	var other: WarbandData = _ctx.warband(_ctx.world.encounter_band_id)
	var mine: WarbandData = my_band()
	if other == null or mine == null:
		Actions.end_encounter(_ctx)
		return
	var laws: FactionLawsData = LegalService.laws_for(_ctx, other.faction_id)
	var c: CharacterData = _player()
	var fate: String = "Their law would let them keep you." if LegalService.can_enslave_standing(laws, LegalService.standing_of(_ctx, c, other.faction_id), SimEnums.BondageOrigin.CAPTIVE) else "Their law would not let them keep you, but they would take all you have."
	var words: String = "%s have come upon you: %d of them, %s.\nYou are %d.\n\n%s" % [
			other.display_name, WarbandOps.headcount(other), _faction_words(other.faction_id), WarbandOps.headcount(mine), fate]
	var options: Array[MenuOption] = [MenuOption.new("Fight", _choose_fight)]
	if i_lead_it(mine):
		if _ctx.world.encounter_can_flee:
			options.append(MenuOption.new("Run for it", _choose_flee))
		else:
			words += "\n\nThey have run you down once already. There is nowhere left to run."
		options.append(MenuOption.new("Surrender", _choose_surrender))
	_open_menu("On the road", words, options)


func _faction_words(faction_id: int) -> String:
	var f: FactionData = _ctx.faction(faction_id)
	return "of %s" % f.display_name if f != null else "answering to nobody"


func _choose_fight() -> void:
	var battle: FieldBattle = FieldBattle.begin(_ctx)
	if battle == null:
		Actions.end_encounter(_ctx)
		_close_menu()
		return
	_menu_open = false
	_menu_panel.visible = false
	_menu_shade.visible = false
	Simulation.field_battle = battle
	Simulation.overworld = self
	var tree: SceneTree = get_tree()
	var scene: Node = (load(BATTLE_SCENE) as PackedScene).instantiate()
	tree.root.remove_child(self)
	tree.root.add_child(scene)
	tree.current_scene = scene


## The battle hands the scene back here. Whatever the battle did is already in the world.
func came_back(summary: String) -> void:
	returned(summary)


func _choose_flee() -> void:
	var result: ActionResult = Actions.flee_encounter(_ctx, _ctx.world.player_character_id)
	if not result.success:
		_news.append(_reason(result))
	else:
		_news.append("You run. Pick your way, and keep moving: they will come after you.")
	_close_menu()


func _choose_surrender() -> void:
	var c: CharacterData = _player()
	Actions.surrender_encounter(_ctx, c.id)
	if LegalService.is_bonded(c):
		_news.append("You lay down what you carry and hold out your hands.")
	else:
		_news.append("They take everything you own and leave you by the road.")
	_sync_all_tokens()
	_close_menu()


func _open_captive() -> void:
	var c: CharacterData = _player()
	var price: int = Actions.freedom_price(_ctx, c)
	var place: SettlementData = _ctx.settlement(c.settlement_id)
	var words: String = "You are held%s, the property of %s. You have %d coin.\n\nFreedom costs %d." % [
			" in %s" % place.display_name if place != null else "", _owner_words(c), c.inventory.gold, price]
	var options: Array[MenuOption] = [
		MenuOption.new("Try to escape", _try_escape),
		MenuOption.new("Buy your freedom", _try_buy_freedom),
		MenuOption.new("Wait a month", _wait_days.bind(CalendarData.DAYS_PER_MONTH)),
	]
	_open_menu("In bondage", words, options)


func _owner_words(c: CharacterData) -> String:
	if c.legal.owner_kind == SimEnums.OwnerKind.FACTION:
		var f: FactionData = _ctx.faction(c.legal.owner_id)
		return f.display_name if f != null else "nobody"
	var owner: CharacterData = _ctx.character(c.legal.owner_id)
	return owner.given_name if owner != null else "nobody"


func _try_escape() -> void:
	var result: ActionResult = Actions.attempt_escape(_ctx, _ctx.world.player_character_id)
	_news.append("You got away." if result.success else _reason(result))
	if result.success:
		_close_menu()
	else:
		# Nobody gets a second try the same day. It takes a week to find another chance.
		_wait_days(ESCAPE_TRY_EVERY_DAYS)


func _try_buy_freedom() -> void:
	var result: ActionResult = Actions.buy_freedom(_ctx, _ctx.world.player_character_id)
	_news.append("You are free." if result.success else _reason(result))
	_close_menu()


func _wait_days(days: int) -> void:
	_kernel.advance_days(days)
	_sync_all_tokens()
	_close_menu()


# --- Towns -----------------------------------------------------------------

func open_town_menu() -> void:
	var c: CharacterData = _player()
	var band: WarbandData = my_band()
	var site: int = band.at_settlement_id if band != null else c.settlement_id
	var s: SettlementData = _ctx.settlement(site)
	if s == null:
		return
	var f: FactionData = _ctx.faction(s.faction_id)
	var words: PackedStringArray = PackedStringArray()
	words.append("%s of %s. %d people. Bondage law: %s." % [s.display_name, f.display_name if f != null else "no realm", PopService.total(s), str(SimEnums.BondageLaw.keys()[LegalService.laws_for(_ctx, s.faction_id).bondage_law]).to_lower()])
	var place: PlaceDef = _ctx.defs.land.place_named(s.place_id) if _ctx.defs.land != null else null
	if place != null:
		words.append(place.lore)
	words.append("You have %d coin." % c.inventory.gold)
	if band != null:
		words.append("Band chest %d, supplies for %d days." % [band.inventory.gold, floori(band.supplies / maxf(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY, 0.001))])
	words.append_array(_news)
	_news = PackedStringArray()
	var options: Array[MenuOption] = []
	if band == null:
		options.append(MenuOption.new("Take to the road with your own band", _form_band))
		_add_work_options(options, s, c)
		_add_band_options(options, s)
	elif i_lead_it(band):
		options.append(MenuOption.new("Leave town", _close_menu))
		if c.inventory.gold > 0:
			options.append(MenuOption.new("Put your %d coin in the band's chest" % c.inventory.gold, _do_fund.bind(c.inventory.gold)))
		_add_recruit_options(options)
		options.append(MenuOption.new("Buy a month of supplies", _do_supplies))
		_add_captive_options(options, band)
		options.append(MenuOption.new("Disband and stay here", _do_disband))
	else:
		options.append(MenuOption.new("March on with them", _close_menu))
		options.append(MenuOption.new("Leave their band", _do_leave_band))
	_add_land_options(options, s, c)
	options.append(MenuOption.new("Steal", _do_action.bind(Actions.steal, "You lift a purse.")))
	options.append(MenuOption.new("Borrow 20 coin", _do_loan))
	options.append(MenuOption.new("Wait a week", _wait_days.bind(7)))
	options.append(MenuOption.new("Wait a month", _wait_days.bind(CalendarData.DAYS_PER_MONTH)))
	_open_menu(s.display_name, "\n".join(words), options)


func _add_work_options(options: Array[MenuOption], s: SettlementData, c: CharacterData) -> void:
	if c.employer_business_id >= 0:
		var job: BusinessData = _ctx.business(c.employer_business_id)
		options.append(MenuOption.new("Quit your work at the %s" % str(job.building_id).replace("_", " "), _do_action.bind(Actions.quit_job, "You walk out.")))
		return
	for id: int in s.business_ids:
		var b: BusinessData = _ctx.business(id)
		if b != null and b.employee_ids.size() < Actions.job_slots(_ctx, id):
			options.append(MenuOption.new("Ask for work at the %s" % str(b.building_id).replace("_", " "), _do_job.bind(id)))
			return


func _add_band_options(options: Array[MenuOption], s: SettlementData) -> void:
	var added: int = 0
	for id: int in _ctx.warband_ids():
		var band: WarbandData = _ctx.warband(id)
		if band != null and band.at_settlement_id == s.id and added < 4:
			options.append(MenuOption.new("Join %s (%d)" % [band.display_name, WarbandOps.headcount(band)], _do_join.bind(id)))
			added += 1


func _add_recruit_options(options: Array[MenuOption]) -> void:
	for troop: StringName in [&"levy_spearman", &"archer", &"man_at_arms"]:
		var def: TroopDef = _ctx.defs.troops[troop]
		options.append(MenuOption.new("Hire one %s, %d coin" % [def.display_name.to_lower(), def.recruit_cost], _do_recruit.bind(troop)))


func _add_captive_options(options: Array[MenuOption], band: WarbandData) -> void:
	var races: Array[StringName] = []
	races.assign(band.captives.keys())
	races.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	for race: StringName in races:
		var held: int = band.captives[race]
		options.append(MenuOption.new("Sell %d %s captives" % [held, race], _do_sell.bind(race, held)))
	if not races.is_empty():
		options.append(MenuOption.new("Free your captives here", _do_action.bind(Actions.release_captives, "They go, and do not thank you.")))


func _after_town_action(words: String) -> void:
	_news.append(words)
	_sync_all_tokens()
	open_town_menu()


func _form_band() -> void:
	var c: CharacterData = _player()
	var result: ActionResult = Actions.form_warband(_ctx, c.id, SimEnums.WarbandRole.PARTY, c.inventory.gold)
	if not result.success:
		_after_town_action(_reason(result))
		return
	_town_shown = c.settlement_id
	_news.append("A spear, a bag, and your coin in a chest with one lock. You are a band of one.")
	_sync_all_tokens()
	open_town_menu()


func _do_fund(amount: int) -> void:
	var result: ActionResult = Actions.fund_band(_ctx, _ctx.world.player_character_id, amount)
	_after_town_action("It goes in the chest." if result.success else _reason(result))


func _do_recruit(troop: StringName) -> void:
	var result: ActionResult = Actions.recruit_troops(_ctx, _ctx.world.player_character_id, troop, 1)
	_after_town_action("%s signs on." % _ctx.defs.troops[troop].display_name if result.success else _reason(result))


func _do_supplies() -> void:
	var band: WarbandData = my_band()
	var units: int = maxi(ceili(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY * CalendarData.DAYS_PER_MONTH), 1)
	var result: ActionResult = Actions.buy_supplies(_ctx, _ctx.world.player_character_id, units)
	_after_town_action("Grain, and enough of it." if result.success else _reason(result))


func _do_sell(race: StringName, count: int) -> void:
	var result: ActionResult = Actions.sell_captives(_ctx, _ctx.world.player_character_id, race, count)
	_after_town_action("Sold %d." % result.value if result.success else _reason(result))


func _do_disband() -> void:
	var result: ActionResult = Actions.disband_warband(_ctx, _ctx.world.player_character_id)
	_after_town_action("Your people go their own ways." if result.success else _reason(result))


func _do_leave_band() -> void:
	var result: ActionResult = Actions.leave_warband(_ctx, _ctx.world.player_character_id)
	_after_town_action("You take your leave." if result.success else _reason(result))


func _do_join(band_id: int) -> void:
	var result: ActionResult = Actions.join_warband(_ctx, _ctx.world.player_character_id, band_id)
	if result.success:
		_news.append("You fall in with them. They decide where you go.")
		_sync_all_tokens()
		_close_menu()
		return
	_after_town_action(_reason(result))


func _do_job(business_id: int) -> void:
	var result: ActionResult = Actions.take_job(_ctx, _ctx.world.player_character_id, business_id)
	_after_town_action("You start tomorrow. Pay comes at the turn of the month." if result.success else _reason(result))


func _do_loan() -> void:
	var result: ActionResult = Actions.take_loan(_ctx, _ctx.world.player_character_id, 20)
	_after_town_action("Twenty coin, and you will owe more than that." if result.success else _reason(result))


## What someone with coin or a crown can do to the land from here.
func _add_land_options(options: Array[MenuOption], s: SettlementData, c: CharacterData) -> void:
	var f: FactionData = _ctx.faction(s.faction_id)
	if f != null and f.ruler_id == c.id and LandOps.woods_to_fell(_ctx, s) >= Actions.CLEAR_LAND_MIN_WOODS:
		options.append(MenuOption.new("Clear the woods around %s, %d from the treasury" % [s.display_name, Actions.CLEAR_LAND_COST], _do_action.bind(Actions.ruler_clear_land.bind(s.id), "The axes go out.")))
	if f != null and f.ruler_id == c.id and s.fortification < Actions.WALLS_MOST - 0.01:
		options.append(MenuOption.new("Raise the walls of %s, %d from the treasury" % [s.display_name, Actions.wall_cost(s)], _do_action.bind(Actions.ruler_raise_walls.bind(s.id), "Masons and diggers go to work on the walls.")))
	if Actions.wallet_of(_ctx, c).gold >= Actions.FOUND_SETTLEMENT_COST:
		options.append(MenuOption.new("Lead settlers out to found a town, %d coin" % Actions.FOUND_SETTLEMENT_COST, _do_action.bind(_found_town, "They go out with what they can carry, and a road follows them.")))


func _found_town(ctx: SimContext, actor_id: int) -> ActionResult:
	return Actions.found_settlement(ctx, actor_id, "%s's Stead" % ctx.character(actor_id).given_name)


func _do_action(action: Callable, words: String) -> void:
	var result: ActionResult = action.call(_ctx, _ctx.world.player_character_id)
	_after_town_action(words if result.success else _reason(result))


# --- Tokens and the view ---------------------------------------------------

func _token_for(band: WarbandData) -> BandToken:
	if _tokens.has(band.id):
		return _tokens[band.id]
	var token: BandToken = BandToken.new()
	add_child(token)
	token.setup(band.id)
	token.place_at(WarbandOps.place_of(_ctx, band))
	_tokens[band.id] = token
	return token


## Brings every token up to where its band now is, and forgets any band that is gone.
func _sync_all_tokens() -> void:
	var seen: Dictionary[int, bool] = {}
	for id: int in _ctx.warband_ids():
		var band: WarbandData = _ctx.warband(id)
		if band == null:
			continue
		seen[id] = true
		var token: BandToken = _token_for(band)
		token.move_to(WarbandOps.place_of(_ctx, band))
		token.show_band(band, "%s (%d)" % [band.display_name, WarbandOps.headcount(band)])
	for id: int in _tokens.keys():
		if not seen.has(id):
			_tokens[id].queue_free()
			_tokens.erase(id)
	if _ctx.world.settlements.size() != _town_count:
		_town_count = _ctx.world.settlements.size()
		OverworldLand.build_roads(_land, _ctx)
		for id: int in _ctx.settlement_ids():
			if not _town_labels.has(id):
				_add_town(_ctx.world.settlements[id])
	_redraw_changed_land()
	_redraw_changed_town()
	for id: int in _town_labels:
		if _ctx.world.settlements.has(id):
			_refresh_town_label(_ctx.world.settlements[id])


func _update_tokens(_delta: float) -> void:
	var alpha: float = shown_clock()
	var mine: Vector2 = my_place()
	var my_band: WarbandData = my_band()
	var budget: int = 1
	var terrain: OverworldTerrain = _ctx.terrain()
	for id: int in _tokens:
		var token: BandToken = _tokens[id]
		var band: WarbandData = _ctx.warband(id)
		if band == null:
			continue
		var at: Vector2 = token.shown_at(alpha)
		# Whoever is inside a town walls, you among them, is not out on the land to be seen.
		token.visible = band.at_settlement_id < 0 and (band == my_band or at.distance_to(mine) <= Actions.SIGHT_RANGE)
		if not token.visible:
			continue
		token.position = Vector3(at.x, OverworldLand.stand_height(terrain, at), at.y)
		if budget > 0 and token.wants_a_figure():
			token.add_figure(_ctx, band)
			budget -= 1
		token.update_clip(token.is_moving() and not is_menu_open() and _time_should_run())


## Draws again the first town found to have grown, shrunk, built or lost a trade, or changed its walls. One a time, so
## the game does not stop for it.
func _redraw_changed_town() -> void:
	for id: int in _ctx.settlement_ids():
		if not _town_nodes.has(id):
			continue
		var s: SettlementData = _ctx.world.settlements[id]
		if TownView.look_of(_ctx, s) == _town_looks[id]:
			continue
		var old: Node3D = _town_nodes[id]
		_land.remove_child(old)
		old.free()
		_add_town(s)
		return


## Draws again the ground around anywhere whose woods have been felled or grown back since last time, or that has newly
## been settled.
func _redraw_changed_land() -> void:
	var map: MapData = _ctx.world.map
	if map.land_version == _land_seen:
		return
	_land_seen = map.land_version
	for id: int in _ctx.settlement_ids():
		var reach: float = map.clearings.get(id, 0.0)
		var was: float = _clearings_seen.get(id, -1.0)
		if floori(reach / LandOps.CLEARING_STEP) != floori(was / LandOps.CLEARING_STEP):
			_clearings_seen[id] = reach
			OverworldLand.redraw_around(_land, _ctx, map.positions[id], maxf(reach, was) + OverworldTerrain.TOWN_FLAT)


func town_near_me() -> int:
	var at: Vector2 = my_place()
	var site: int = WarbandOps.nearest_settlement(_ctx, at)
	if site >= 0 and _ctx.world.map.positions[site].distance_to(at) <= ENTER_TOWN_RANGE:
		return site
	return -1


func walk_into(site: int) -> void:
	var band: WarbandData = my_band()
	if band != null and band.at_settlement_id == site:
		enter_town(site)
		return
	Actions.march_to_settlement(_ctx, _ctx.world.player_character_id, site)


## You are in a town. TownEntry may take you into the town to walk about; if it does not, the town's menu opens.
func enter_town(site: int) -> void:
	if not TownEntry.enter(self, site):
		open_town_menu()


# --- What the controls, panels and town scene read -------------------------

func sim() -> SimContext:
	return _ctx


func fixed_look() -> PackedFloat64Array:
	return _fixed_look


func token_map() -> Dictionary[int, BandToken]:
	return _tokens


func town_label_map() -> Dictionary[int, Label3D]:
	return _town_labels


func land_node() -> Node3D:
	return _land


## How far between the last watch and the next the tokens are drawn.
func shown_clock() -> float:
	return 1.0 if is_menu_open() else _clock


## True while a menu or a panel is up. Time stands still then.
func is_menu_open() -> bool:
	return _menu_open or _panels.is_open()


func toggle_panel(panel: StringName) -> void:
	if _menu_open:
		return
	_panels.toggle(panel)


func escape_pressed() -> void:
	if _panels.is_open():
		_panels.close()
	elif not _menu_open:
		_open_pause()


func quick_save() -> void:
	var saved: Error = World.save_game(SAVE_PATH)
	_news.append("Saved." if saved == OK else "Could not save: %s." % error_string(saved))
	if not is_menu_open():
		_open_news()


func quick_load() -> void:
	if FileAccess.file_exists(SAVE_PATH) and World.load_game(SAVE_PATH) == OK:
		get_tree().reload_current_scene()


## Back from the town scene, or anything else that took over the screen. Whatever it did is already in the world.
func returned(summary: String) -> void:
	if not summary.is_empty():
		_news.append(summary)
	_clock = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_all_tokens()
	_controls.snap_camera()
	_check_state()


# --- The HUD ---------------------------------------------------------------

func _update_hud() -> void:
	var calendar: CalendarData = _ctx.world.calendar
	_date.text = "[color=#%s]Year %d[/color]   ·   Month %d   ·   Day %d" % [MenuStyle.GOLD.to_html(false), calendar.year(), calendar.month() + 1, calendar.day_of_month() + 1]
	var c: CharacterData = _player()
	if c == null:
		_status.text = "[b]Nobody[/b]"
	else:
		_status.text = _status_words(c)
	var entries: Array[ChronicleEntry] = _ctx.world.chronicle
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(maxi(entries.size() - 5, 0), entries.size()):
		# Older news fades.
		var age: int = entries.size() - 1 - i
		lines.append("[color=#%s]%s[/color]" % [MenuStyle.TEXT.darkened(0.12 * float(age)).to_html(false), entries[i].text])
	_log.text = "\n".join(lines)
	_update_hover()
	_hint.text = _hint_words()


func _status_words(c: CharacterData) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var realm: FactionData = _ctx.faction(c.faction_id)
	lines.append("[b]%s[/b], %d, %s %s, %s" % [c.given_name, floori(_ctx.age_years(c)), GeneticsService.dominant_race(c), c.occupation, realm.display_name if realm != null else "no realm"])
	lines.append("Coin %d    Fight %d%%    Blood %d%%" % [c.inventory.gold, roundi(LimbService.fighting_capacity(_ctx, c) * 100.0), roundi(c.body.blood * 100.0)])
	var band: WarbandData = my_band()
	if band != null:
		var troops: PackedStringArray = PackedStringArray()
		var kinds: Array[StringName] = []
		kinds.assign(band.troops.keys())
		kinds.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
		for kind: StringName in kinds:
			troops.append("%d %s" % [band.troops[kind], _ctx.defs.troops[kind].display_name.to_lower()])
		lines.append("%s: %d%s" % [band.display_name, WarbandOps.headcount(band), ", with " + ", ".join(troops) if not troops.is_empty() else ""])
		var held: int = 0
		for race: StringName in band.captives:
			held += band.captives[race]
		lines.append("Chest %d    Supplies %d    Captives %d" % [band.inventory.gold, floori(band.supplies), held])
		var ground: OverworldTerrain.Kind = _ctx.terrain().kind_at(WarbandOps.place_of(_ctx, band))
		lines.append("On %s, %d a day" % [str(OverworldTerrain.Kind.keys()[ground]).to_lower(), roundi(WarbandOps.travel_speed(_ctx, band) * OverworldTerrain.SPEED[ground])])
	return "\n".join(lines)


func _hint_words() -> String:
	if _menu_open:
		return ""
	if my_band() == null:
		return "You are on foot. Form a band or join one in town to take to the road.   C I P L K J N for panels."
	if not i_lead_it(my_band()):
		return "You march where your leader goes."
	var mode: String = _controls.time_words()
	var lead: String = "[b]%s[/b]   " % mode if not mode.is_empty() else ""
	var town: String = "E goes into town.   " if town_near_me() >= 0 else ""
	return "%sClick to travel, hold to steer. Click a band to chase, a town to go in. %sWASD pans, Q/E turn, F follows. Space or 1/2/3 for time. C I P L K J N for panels." % [lead, town]


func _update_hover() -> void:
	var at: Vector2 = get_viewport().get_mouse_position()
	var words: String = ""
	if not _menu_open:
		var id: int = _controls.band_under(at)
		if id >= 0:
			var band: WarbandData = _ctx.warband(id)
			if band != null:
				var mine: WarbandData = my_band()
				var hostile: bool = mine != null and WarbandSystem.is_hostile(_ctx, band, mine)
				words = "%s, %d\n%s%s" % [band.display_name, WarbandOps.headcount(band), _faction_words(band.faction_id), "\nhostile" if hostile else ""]
		else:
			var site: int = _controls.town_under(at)
			if site >= 0:
				var s: SettlementData = _ctx.settlement(site)
				var f: FactionData = _ctx.faction(s.faction_id)
				words = "%s\n%s, %d people" % [s.display_name, f.display_name if f != null else "no realm", PopService.total(s)]
	_hover.text = words
	_hover.pin(Vector2.ZERO, at + Vector2(20.0, 14.0))


# --- Playing itself, to test the whole road from a town to a battle and back ---

func _run_demo(delta: float) -> void:
	_demo_time -= delta
	if _demo_time > 0.0:
		return
	_demo_time = 0.5
	if _menu_open:
		_demo_answer()
		return
	var band: WarbandData = my_band()
	if band == null or not i_lead_it(band):
		return
	var at: Vector2 = WarbandOps.place_of(_ctx, band)
	var best: WarbandData = null
	var best_distance: float = INF
	for id: int in _ctx.warband_ids():
		var other: WarbandData = _ctx.warband(id)
		if other != null and other != band and WarbandSystem.is_hostile(_ctx, other, band):
			var distance: float = at.distance_to(WarbandOps.place_of(_ctx, other))
			if distance < best_distance:
				best = other
				best_distance = distance
	if best == null:
		return
	if best_distance <= Actions.SIGHT_RANGE:
		Actions.give_chase(_ctx, _ctx.world.player_character_id, best.id)
	else:
		Actions.march_to(_ctx, _ctx.world.player_character_id, WarbandOps.place_of(_ctx, best))


func _demo_answer() -> void:
	print("DEMO menu: %s | %s" % [_menu_title.text, _menu_text.text.replace("\n", " ")])
	var buttons: Array[Node] = _menu_buttons.get_children()
	for wanted: String in ["Fight", "Hire one levy", "Put your", "Take to the road", "Go on", "Begin", "Leave town", "Try to escape", "Start again"]:
		for node: Node in buttons:
			var button: Button = node as Button
			if button.text.begins_with(wanted) and not (wanted == "Hire one levy" and _demo_cannot_hire()):
				print("DEMO picks: %s" % button.text)
				button.pressed.emit()
				return


func _demo_cannot_hire() -> bool:
	var band: WarbandData = my_band()
	return band == null or band.inventory.gold < 4 or WarbandOps.troop_count(band) >= 3
