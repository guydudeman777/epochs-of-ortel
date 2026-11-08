extends Control
## Making the person you will be, in two steps. First the people you are born among: one of the human cultures, or the
## one realm of an old race. That sets your race, the towns you can start in and the faces you can have. Then the
## person. The world is raised first, without you in it, so every town is a real town and you come out of a real group
## of people in the one you pick. Behind it all the camera drifts over the land itself.
##
## godot --path . res://src/view/menu/character_screen.tscn
## Drag the figure to turn it, the wheel moves between face and body. Options: --seed=number, --people=culture id
## (goes straight to making the person), --close=0..1, --yaw=radians, --out=path.png to save a picture.

const OVERWORLD_SCENE: String = "res://src/view/overworld/overworld_scene.tscn"
const MENU_SCENE: String = "res://src/view/menu/main_menu.tscn"
const FORM_WIDTH: float = 470.0
const TURN_PER_PIXEL: float = 0.01
const IDLE_TURN: float = 0.12
const REBUILD_DELAY: float = 0.15
const TOWN_HEIGHT: float = 190.0
## The face sliders worth offering. The rest still come from the dice and from parents.
const LOOK_SLIDERS: Array[StringName] = [
	&"head_width", &"forehead_height", &"brow_ridge", &"eye_size", &"eye_spacing", &"cheekbones", &"nose_size",
	&"nose_width", &"nose_hump", &"mouth_width", &"upper_lip", &"jaw_bones", &"chin_width", &"chin_forward", &"ear_size",
]
const LINE_NAMES: Dictionary[StringName, String] = {&"caucasian": "Western", &"asian": "Eastern", &"african": "Southern"}
const LAWS: Array[String] = ["Bondage is banned.", "Only criminals are bonded.", "Debtors can be bonded.", "People are owned."]
const PROBLEMS: Dictionary[StringName, String] = {
	&"no_name": "You need a name.", &"no_town": "Choose where you start.", &"not_their_town": "That town is not of your people.",
	&"nobody_there": "Nobody of that kind lives there.", &"no_background": "Choose what you were.",
}

var _ctx: SimContext
var _spec: PlayerSpec = PlayerSpec.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _name_typed: bool = false
var _peoples: Array[PlayerStart.People] = []
var _people: PlayerStart.People = null
var _towns: Array[int] = []
var _hair_choices: Array[StringName] = []
var _beard_choices: Array[StringName] = []
var _eye_choices: Array[StringName] = []
var _lines: Array[StringName] = []
var _quiet: bool = false

var _flyover: MapFlyover
var _busy: Label

# Step one: the people.
var _people_panel: PanelContainer
var _seed_edit: LineEdit
var _people_list: VBoxContainer
var _people_buttons: Array[Button] = []
var _people_text: RichTextLabel

# Step two: the person.
var _maker_panel: PanelContainer
var _form: VBoxContainer
var _people_label: Label
var _name_edit: LineEdit
var _family_edit: LineEdit
var _sex_pick: OptionButton
var _background_pick: OptionButton
var _background_text: Label
var _town_pick: OptionButton
var _town_text: Label
var _age_slider: HSlider
var _age_label: Label
var _trait_boxes: Dictionary[StringName, CheckBox] = {}
var _line_pick: OptionButton
var _hair_pick: OptionButton
var _beard_pick: OptionButton
var _eye_pick: OptionButton
var _tone_slider: HSlider
var _tone_box: VBoxContainer
var _look_sliders: Dictionary[StringName, HSlider] = {}
var _summary: RichTextLabel
var _problem: Label
var _begin: Button

var _stage_holder: SubViewportContainer
var _stage: SubViewport
var _hint: Label
var _figure_root: Node3D
var _figure: Node3D
var _camera: Camera3D
var _yaw: float = 0.35
var _close: float = 0.12
var _dragging: bool = false
var _touched_at: float = -10.0
var _rebuild_in: float = -1.0
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuStyle.apply(self)
	theme = MenuStyle.theme()
	var black: ColorRect = ColorRect.new()
	black.color = MenuStyle.BACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	_rng.randomize()
	_busy = MenuStyle.label("Raising the world...", 22, MenuStyle.GOLD)
	_busy.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_busy)
	# A frame to show the words before the world takes its time.
	await get_tree().process_frame
	await get_tree().process_frame
	_flyover = MapFlyover.new()
	add_child(_flyover)
	_raise_world(ViewUtil.arg("seed", str(_rng.randi() % 100000)).to_int())
	black.visible = false
	_build_stage()
	_build_people_panel()
	_build_maker_panel()
	_fill_peoples()
	_to_people()
	_close = ViewUtil.arg("close", str(_close)).to_float()
	_yaw = ViewUtil.arg("yaw", str(_yaw)).to_float()
	var wanted: StringName = StringName(ViewUtil.arg("people", ""))
	for i: int in range(_peoples.size()):
		if _peoples[i].culture_id == wanted:
			_pick_people(i)
			_to_maker()
			break
	_busy.visible = false
	var out_path: String = ViewUtil.arg("out", "")
	if not out_path.is_empty():
		if _maker_panel.visible:
			_rebuild_figure()
		await ViewUtil.save_shot_and_quit(self, out_path)


func _raise_world(world_seed: int) -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = world_seed
	config.place_player = false
	World.new_game(config)
	GameClock.paused = true
	_ctx = Simulation.kernel.ctx
	_peoples = PlayerStart.peoples(_ctx)
	_flyover.build(_ctx)


# --- Layout ------------------------------------------------------------------

func _panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 24.0
	panel.offset_top = 24.0
	panel.offset_right = 24.0 + FORM_WIDTH
	panel.offset_bottom = -24.0
	add_child(panel)
	return panel


func _build_stage() -> void:
	_stage_holder = SubViewportContainer.new()
	_stage_holder.stretch = true
	_stage_holder.anchor_right = 1.0
	_stage_holder.anchor_bottom = 1.0
	_stage_holder.offset_left = FORM_WIDTH + 40.0
	_stage_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_holder.gui_input.connect(_stage_input)
	add_child(_stage_holder)
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	# See-through, so the land shows round the figure.
	_stage.transparent_bg = true
	_stage.msaa_3d = Viewport.MSAA_4X
	_stage_holder.add_child(_stage)
	_figure_root = Node3D.new()
	_stage.add_child(_figure_root)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-24.0, 30.0, 0.0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 0.9
	# One cascade over a few metres, so the shadow map is fine enough for plates and fingers, blurred a little at the edge.
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 6.0
	key.shadow_blur = 2.0
	key.shadow_normal_bias = 1.0
	_stage.add_child(key)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	rim.light_color = Color(0.62, 0.7, 0.95)
	rim.light_energy = 0.55
	_stage.add_child(rim)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.58, 0.55)
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_stage.add_child(world_environment)
	_camera = Camera3D.new()
	_camera.fov = 26.0
	_stage.add_child(_camera)
	_hint = MenuStyle.label("Drag to turn. Wheel for face or body.", 14, MenuStyle.DIM)
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -360.0
	_hint.offset_top = -40.0
	_hint.offset_right = -24.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint)


func _build_people_panel() -> void:
	_people_panel = _panel()
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 10)
	_people_panel.add_child(outer)
	outer.add_child(MenuStyle.title("Your people", 26))
	outer.add_child(MenuStyle.rule())
	outer.add_child(MenuStyle.heading("World"))
	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override(&"separation", 6)
	outer.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.tooltip_text = "The land is always Ortel. The seed decides its people and what becomes of them."
	seed_row.add_child(_seed_edit)
	_small_button(seed_row, "Raise", _on_new_world.bind(false))
	_small_button(seed_row, "Dice", _on_new_world.bind(true))
	outer.add_child(MenuStyle.heading("Born among"))
	_people_list = VBoxContainer.new()
	_people_list.add_theme_constant_override(&"separation", 4)
	outer.add_child(_people_list)
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroller)
	_people_text = RichTextLabel.new()
	_people_text.bbcode_enabled = true
	_people_text.fit_content = true
	_people_text.scroll_active = false
	_people_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_people_text.add_theme_font_size_override(&"normal_font_size", 15)
	scroller.add_child(_people_text)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	outer.add_child(buttons)
	_small_button(buttons, "Back", func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var go: Button = _small_button(buttons, "Choose", _to_maker)
	go.custom_minimum_size = Vector2(130.0, 40.0)
	go.add_theme_font_size_override(&"font_size", 19)


func _build_maker_panel() -> void:
	_maker_panel = _panel()
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 10)
	_maker_panel.add_child(outer)
	outer.add_child(MenuStyle.title("A new life", 26))
	outer.add_child(MenuStyle.rule())
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroller)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override(&"separation", 6)
	scroller.add_child(_form)

	_section("Born among")
	var people_row: HBoxContainer = _row()
	_people_label = MenuStyle.label("", 16, MenuStyle.GOLD)
	_people_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	people_row.add_child(_people_label)
	_small_button(people_row, "Change", _to_people)

	_section("Who you are")
	var name_row: HBoxContainer = _row()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Given name"
	_name_edit.max_length = 24
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_typed)
	name_row.add_child(_name_edit)
	_small_button(name_row, "Dice", _on_roll_name)
	_family_edit = LineEdit.new()
	_family_edit.placeholder_text = "Name of your line (optional)"
	_family_edit.max_length = 32
	_family_edit.text_changed.connect(func(_text: String) -> void: _refresh_summary())
	_form.add_child(_family_edit)
	_sex_pick = _option("Sex", ["Man", "Woman"], _on_sex)
	_age_label = MenuStyle.label("", 15)
	_form.add_child(_age_label)
	_age_slider = HSlider.new()
	_age_slider.step = 1.0
	_age_slider.value_changed.connect(_on_age)
	_form.add_child(_age_slider)

	_section("What you were")
	var names: Array[String] = []
	for id: StringName in PlayerStart.BACKGROUND_ORDER:
		names.append(PlayerStart.BACKGROUNDS[id]["name"] as String)
	_background_pick = _option("", names, _on_background)
	_background_text = _note()

	_section("Where you start")
	_town_pick = _option("", [], _on_town)
	_town_text = _note()

	_section("Nature (up to %d)" % PlayerStart.MAX_TRAITS)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	_form.add_child(grid)
	for id: StringName in _ctx.defs.trait_ids:
		var box: CheckBox = CheckBox.new()
		box.text = _ctx.defs.traits[id].display_name
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.toggled.connect(_on_trait.bind(id))
		grid.add_child(box)
		_trait_boxes[id] = box

	_section("Look")
	var face_row: HBoxContainer = _row()
	_small_button(face_row, "New face", _on_new_face)
	_small_button(face_row, "Even out", _on_even_face)
	_line_pick = _option("Line", [], _on_line)
	_hair_pick = _option("Hair", [], _on_style)
	_beard_pick = _option("Beard", [], _on_style)
	_eye_pick = _option("Eyes", [], _on_style)
	_tone_box = VBoxContainer.new()
	_form.add_child(_tone_box)
	_tone_box.add_child(MenuStyle.label("Hair colour", 14, MenuStyle.DIM))
	_tone_slider = _slider(0.0, 1.0)
	_tone_slider.value_changed.connect(func(_v: float) -> void: _on_style(0))
	_tone_box.add_child(_tone_slider)
	for key: StringName in LOOK_SLIDERS:
		_form.add_child(MenuStyle.label(String(key).capitalize(), 13, MenuStyle.DIM))
		var slider: HSlider = _slider(-FaceService.SLIDER_LIMIT, FaceService.SLIDER_LIMIT)
		slider.value_changed.connect(_on_look_slider.bind(key))
		_form.add_child(slider)
		_look_sliders[key] = slider

	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.custom_minimum_size = Vector2(0.0, 60.0)
	outer.add_child(_summary)
	_problem = MenuStyle.label("", 14, MenuStyle.BAD)
	outer.add_child(_problem)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	outer.add_child(buttons)
	_small_button(buttons, "Back", _to_people)
	_small_button(buttons, "All at random", _randomise_all)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_begin = _small_button(buttons, "Begin", _on_begin)
	_begin.custom_minimum_size = Vector2(130.0, 40.0)
	_begin.add_theme_font_size_override(&"font_size", 19)


func _section(title: String) -> void:
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	_form.add_child(gap)
	_form.add_child(MenuStyle.heading(title))
	var line: ColorRect = ColorRect.new()
	line.color = Color(MenuStyle.EDGE, 0.35)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	_form.add_child(line)


func _note() -> Label:
	var note: Label = MenuStyle.label("", 14, MenuStyle.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(note)
	return note


func _row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	_form.add_child(row)
	return row


func _small_button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _option(title: String, items: Array[String], action: Callable) -> OptionButton:
	var row: HBoxContainer = _row()
	if not title.is_empty():
		var label: Label = MenuStyle.label(title, 15)
		label.custom_minimum_size = Vector2(70.0, 0.0)
		row.add_child(label)
	var pick: OptionButton = OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.fit_to_longest_item = false
	for item: String in items:
		pick.add_item(item)
	pick.item_selected.connect(action)
	row.add_child(pick)
	return pick


func _row_of(pick: OptionButton) -> Control:
	return pick.get_parent() as Control


func _slider(low: float, high: float) -> HSlider:
	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


# --- Step one: the people ------------------------------------------------------

func _fill_peoples() -> void:
	_seed_edit.text = str(_ctx.world.world_seed)
	for button: Button in _people_buttons:
		_people_list.remove_child(button)
		button.queue_free()
	_people_buttons.clear()
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in range(_peoples.size()):
		var people: PlayerStart.People = _peoples[i]
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s  ·  %s" % [people.display_name, _ctx.defs.races[people.race_id].display_name]
		button.pressed.connect(_pick_people.bind(i))
		_people_list.add_child(button)
		_people_buttons.append(button)


func _pick_people(index: int) -> void:
	_people = _peoples[index]
	_people_buttons[index].button_pressed = true
	var towns: Array[int] = PlayerStart.towns_of(_ctx, _people, &"tiller")
	var view: Vector3 = _flyover.view_of(towns)
	_flyover.fly_to(Vector2(view.x, view.y), view.z)
	_flyover.mark_towns(towns)
	_people_text.text = _people_words(_people)


func _people_words(people: PlayerStart.People) -> String:
	var race: RaceDef = _ctx.defs.races[people.race_id]
	var culture: CultureDef = _ctx.defs.cultures[people.culture_id]
	var towns: Array[int] = PlayerStart.towns_of(_ctx, people, &"tiller")
	var folk: int = 0
	for id: int in towns:
		for group: PopGroupData in _ctx.world.settlements[id].pop_groups:
			folk += group.count
	var realms: Array[int] = []
	for id: int in _ctx.faction_ids():
		var f: FactionData = _ctx.faction(id)
		if not f.destroyed and (f.id == people.realm_id or (people.realm_id < 0 and f.culture_id == people.culture_id)):
			realms.append(id)
	var gold: String = MenuStyle.GOLD.to_html(false)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[font_size=20][color=#%s]%s[/color][/font_size]" % [gold, people.display_name])
	lines.append("%s, of the %s. %d towns, about %d people. %s" % [race.display_name, culture.display_name, towns.size(), folk, LAWS[culture.bondage_law]])
	if race.lifespan > 0.0:
		lines.append("Grown at %d, old by %d." % [race.adult_age, roundi(race.lifespan * 0.8)])
	for id: int in realms:
		var realm: RealmDef = _realm_def(id)
		var f: FactionData = _ctx.faction(id)
		lines.append("")
		lines.append("[color=#%s]%s[/color]" % [gold, f.display_name])
		if realm != null and not realm.lore.is_empty():
			lines.append(realm.lore)
	return "\n".join(lines)


## The realm as the map wrote it, found through the first of its towns.
func _realm_def(faction_id: int) -> RealmDef:
	var land: LandDef = _ctx.defs.land
	var f: FactionData = _ctx.faction(faction_id)
	for town_id: int in f.settlement_ids:
		var place: PlaceDef = _place_def(town_id)
		if place == null:
			continue
		for realm: RealmDef in land.realms:
			if realm.id == place.realm:
				return realm
	return null


func _place_def(town_id: int) -> PlaceDef:
	var s: SettlementData = _ctx.settlement(town_id)
	if s == null or s.place_id == &"":
		return null
	for place: PlaceDef in _ctx.defs.land.places:
		if place.id == s.place_id:
			return place
	return null


func _to_people() -> void:
	_people_panel.visible = true
	_maker_panel.visible = false
	_stage_holder.visible = false
	_hint.visible = false
	var index: int = _peoples.find(_people)
	_pick_people(maxi(index, 0))


func _to_maker() -> void:
	var same: bool = _spec.face != null and _spec.culture_id == _people.culture_id and _spec.realm_id == _people.realm_id
	if not same:
		_spec = PlayerStart.random_spec(_ctx, _rng, _people)
		_name_typed = false
		_quiet = true
		_family_edit.text = ""
		_quiet = false
	_people_label.text = "%s  ·  %s" % [_people.display_name, _ctx.defs.races[_people.race_id].display_name]
	_people_panel.visible = false
	_maker_panel.visible = true
	_stage_holder.visible = true
	_hint.visible = true
	_show_spec()


func _on_new_world(roll: bool) -> void:
	var world_seed: int = _rng.randi() % 100000 if roll else _seed_edit.text.to_int()
	var kept: PlayerStart.People = _people
	_busy.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_raise_world(world_seed)
	_busy.visible = false
	_spec = PlayerSpec.new()
	_fill_peoples()
	var index: int = 0
	for i: int in range(_peoples.size()):
		if _peoples[i].culture_id == kept.culture_id and (kept.realm_id < 0) == (_peoples[i].realm_id < 0):
			index = i
	_pick_people(index)


# --- Step two: the person ------------------------------------------------------

func _randomise_all() -> void:
	_spec = PlayerStart.random_spec(_ctx, _rng, _people)
	_name_typed = false
	_quiet = true
	_family_edit.text = ""
	_quiet = false
	_show_spec()


## Puts every control in line with the spec, without any of them changing it back.
func _show_spec() -> void:
	_quiet = true
	_name_edit.text = _spec.given_name
	_sex_pick.select(0 if _spec.sex == SimEnums.Sex.MALE else 1)
	for i: int in range(PlayerStart.BACKGROUND_ORDER.size()):
		var background: StringName = PlayerStart.BACKGROUND_ORDER[i]
		_background_pick.set_item_disabled(i, PlayerStart.towns_of(_ctx, _people, background).is_empty())
	_background_pick.select(PlayerStart.BACKGROUND_ORDER.find(_spec.background))
	_background_text.text = PlayerStart.BACKGROUNDS[_spec.background]["text"] as String
	var years: Vector2 = PlayerStart.age_range(_ctx, _spec.race_id)
	_age_slider.min_value = years.x
	_age_slider.max_value = floorf(years.y)
	_age_slider.value = _spec.age_years
	_age_label.text = "Age %d" % roundi(_spec.age_years)
	_fill_towns()
	_fill_look()
	_refresh_traits()
	_quiet = false
	_refresh_summary()
	_queue_figure()


func _fill_towns() -> void:
	_towns = PlayerStart.towns_of(_ctx, _people, _spec.background)
	_towns.sort_custom(func(a: int, b: int) -> bool: return _town_label(a) < _town_label(b))
	_town_pick.clear()
	for id: int in _towns:
		_town_pick.add_item(_town_label(id))
	if not _towns.has(_spec.settlement_id) and not _towns.is_empty():
		_spec.settlement_id = _towns[0]
	_town_pick.select(_towns.find(_spec.settlement_id))
	_town_pick.disabled = _towns.is_empty()
	_show_town()


func _show_town() -> void:
	_town_text.text = _town_words(_spec.settlement_id)
	_flyover.mark_towns(_towns, _spec.settlement_id)
	if _ctx.world.map.positions.has(_spec.settlement_id):
		_flyover.fly_to(_ctx.world.map.positions[_spec.settlement_id], TOWN_HEIGHT)


func _town_label(id: int) -> String:
	var s: SettlementData = _ctx.settlement(id)
	var f: FactionData = _ctx.faction(s.faction_id)
	return "%s  (%s)" % [s.display_name, f.display_name if f != null else "free"]


func _town_words(id: int) -> String:
	var s: SettlementData = _ctx.settlement(id)
	if s == null:
		return "Nobody of your kind lives as that anywhere among your people."
	var people: int = 0
	for group: PopGroupData in s.pop_groups:
		people += group.count
	var f: FactionData = _ctx.faction(s.faction_id)
	var law: String = LAWS[f.laws.bondage_law] if f != null else ""
	var place: PlaceDef = _place_def(id)
	var lore: String = "\n" + place.lore if place != null and not place.lore.is_empty() else ""
	return "%s, about %d people. %s%s" % [s.display_name, people, law, lore]


func _fill_look() -> void:
	var face: FaceData = _spec.face
	var male: bool = _spec.sex == SimEnums.Sex.MALE
	var featured: bool = not face.features.is_empty()
	var race: RaceDef = _ctx.defs.races[_spec.race_id]
	_lines = PlayerStart.face_lines(_ctx, _people)
	_line_pick.clear()
	for line: StringName in _lines:
		_line_pick.add_item(LINE_NAMES[line])
	_line_pick.select(_lines.find(FaceView.dominant_population(face)))
	_row_of(_line_pick).visible = _lines.size() > 1
	_hair_choices.assign(FaceService.MALE_HAIR if male else FaceService.FEMALE_HAIR)
	_hair_choices.append_array(FaceService.AFRO_LINE_HAIR)
	_hair_choices.insert(0, &"")
	_fill_styles(_hair_pick, _hair_choices, face.hair_style, "Shaved")
	_row_of(_hair_pick).visible = not featured
	_beard_choices.assign(FaceService.BEARDS)
	_beard_choices.insert(0, &"")
	_fill_styles(_beard_pick, _beard_choices, face.beard_style, "None")
	_row_of(_beard_pick).visible = male and not featured
	_eye_choices.assign(race.face_eye_colors if not race.face_eye_colors.is_empty() else FaceService.LIGHT_EYES)
	var unique: Array[StringName] = []
	for eye: StringName in _eye_choices:
		if not unique.has(eye):
			unique.append(eye)
	if not unique.has(face.eye_color):
		unique.append(face.eye_color)
	_eye_choices = unique
	_fill_styles(_eye_pick, _eye_choices, face.eye_color, "")
	_tone_slider.value = face.hair_tone
	_tone_box.visible = not featured
	for key: StringName in _look_sliders:
		_look_sliders[key].value = face.sliders.get(key, 0.0)


func _fill_styles(pick: OptionButton, choices: Array[StringName], current: StringName, empty_name: String) -> void:
	pick.clear()
	for id: StringName in choices:
		pick.add_item(empty_name if id == &"" else _style_name(id))
	pick.select(maxi(choices.find(current), 0))


func _style_name(id: StringName) -> String:
	var text: String = String(id)
	for prefix: String in ["elvs_", "rehmanpolanski_", "grinsegold_", "culturalibre_", "wdg_"]:
		text = text.trim_prefix(prefix)
	return text.trim_suffix("_wip").replace("_", " ").capitalize()


func _refresh_traits() -> void:
	var chosen: Array[StringName] = PlayerStart.clean_traits(_ctx, _spec.traits)
	_spec.traits = chosen
	for id: StringName in _trait_boxes:
		var box: CheckBox = _trait_boxes[id]
		box.set_pressed_no_signal(chosen.has(id))
		var blocked: bool = chosen.size() >= PlayerStart.MAX_TRAITS and not chosen.has(id)
		for kept: StringName in chosen:
			blocked = blocked or _ctx.defs.traits[kept].opposites.has(id) or _ctx.defs.traits[id].opposites.has(kept)
		box.disabled = blocked and not chosen.has(id)


func _refresh_summary() -> void:
	_spec.given_name = _name_edit.text
	_spec.family_name = _family_edit.text
	var race: RaceDef = _ctx.defs.races[_spec.race_id]
	var kit: Dictionary = PlayerStart.BACKGROUNDS[_spec.background]
	var free: String = "bonded" if PlayerStart.is_bonded(_spec.background) else "free"
	var s: SettlementData = _ctx.settlement(_spec.settlement_id)
	var mods: PackedStringArray = PackedStringArray()
	for id: StringName in _spec.traits:
		for attribute: StringName in _ctx.defs.traits[id].attribute_mods:
			var amount: int = _ctx.defs.traits[id].attribute_mods[attribute]
			mods.append("%s %+d" % [String(attribute).capitalize(), amount])
	_summary.text = "[color=#%s]%s[/color], a %s %s of %d, of %s. Starts with %d coin.%s" % [
			MenuStyle.GOLD.to_html(false), _spec.given_name if not _spec.given_name.is_empty() else "Nobody",
			free, race.display_name.to_lower(), roundi(_spec.age_years), s.display_name if s != null else "nowhere",
			kit.get("gold", 0) as int, "\n" + ", ".join(mods) if not mods.is_empty() else ""]
	var problem: StringName = PlayerStart.problem(_ctx, _spec)
	_problem.text = PROBLEMS.get(problem, "That life cannot be started.") as String if problem != &"" else ""
	_begin.disabled = problem != &""


func _rolled_name() -> String:
	return PlayerStart.roll_name(_ctx, _spec.race_id, _spec.settlement_id, _spec.sex, _rng)


func _on_name_typed(_text: String) -> void:
	if _quiet:
		return
	_name_typed = true
	_refresh_summary()


func _on_roll_name() -> void:
	_name_typed = false
	_spec.given_name = _rolled_name()
	_quiet = true
	_name_edit.text = _spec.given_name
	_quiet = false
	_refresh_summary()


func _on_sex(index: int) -> void:
	if _quiet:
		return
	_spec.sex = SimEnums.Sex.MALE if index == 0 else SimEnums.Sex.FEMALE
	_new_face_keeping_line()
	if not _name_typed:
		_spec.given_name = _rolled_name()
	_show_spec()


func _on_age(value: float) -> void:
	if _quiet:
		return
	_spec.age_years = value
	_age_label.text = "Age %d" % roundi(value)
	_refresh_summary()
	_queue_figure()


func _on_background(index: int) -> void:
	if _quiet:
		return
	_spec.background = PlayerStart.BACKGROUND_ORDER[index]
	_show_spec()


func _on_town(index: int) -> void:
	if _quiet or index < 0 or index >= _towns.size():
		return
	_spec.settlement_id = _towns[index]
	_show_town()
	if not _name_typed:
		_spec.given_name = _rolled_name()
		_quiet = true
		_name_edit.text = _spec.given_name
		_quiet = false
	_refresh_summary()


func _on_trait(pressed: bool, id: StringName) -> void:
	if _quiet:
		return
	if pressed and not _spec.traits.has(id):
		_spec.traits.append(id)
	elif not pressed:
		_spec.traits.erase(id)
	_refresh_traits()
	_refresh_summary()


func _rolled_face(line: StringName) -> FaceData:
	var s: SettlementData = _ctx.settlement(_spec.settlement_id)
	return CharacterFactory.face_for(_ctx, _spec.race_id, s.faction_id if s != null else -1, _spec.sex == SimEnums.Sex.MALE, _rng, line)


func _new_face_keeping_line() -> void:
	var line: StringName = FaceView.dominant_population(_spec.face) if _spec.face != null else &""
	if not PlayerStart.face_lines(_ctx, _people).has(line):
		line = &""
	_spec.face = _rolled_face(line)


func _on_new_face() -> void:
	_new_face_keeping_line()
	_show_spec()


## Pulls every slider halfway back to the average of the race.
func _on_even_face() -> void:
	var race: RaceDef = _ctx.defs.races[_spec.race_id]
	for key: StringName in _spec.face.sliders:
		var average: float = race.face_bias.get(key, 0.0)
		_spec.face.sliders[key] = lerpf(_spec.face.sliders[key], average, 0.5)
	_show_spec()


func _on_line(index: int) -> void:
	if _quiet or index < 0 or index >= _lines.size():
		return
	_spec.face = _rolled_face(_lines[index])
	_show_spec()


func _on_style(_index: int) -> void:
	if _quiet:
		return
	var face: FaceData = _spec.face
	face.hair_style = _hair_choices[maxi(_hair_pick.selected, 0)]
	face.beard_style = _beard_choices[maxi(_beard_pick.selected, 0)] if _spec.sex == SimEnums.Sex.MALE else &""
	face.eye_color = _eye_choices[maxi(_eye_pick.selected, 0)]
	face.hair_tone = _tone_slider.value
	if not face.features.is_empty():
		face.hair_style = &""
		face.beard_style = &""
	_queue_figure()


func _on_look_slider(value: float, key: StringName) -> void:
	if _quiet:
		return
	_spec.face.sliders[key] = value
	_queue_figure()


func _on_begin() -> void:
	_refresh_summary()
	if PlayerStart.place(_ctx, _spec) == null:
		_problem.text = "That life cannot be started."
		return
	_ctx.rebuild_indexes()
	get_tree().change_scene_to_file(OVERWORLD_SCENE)


# --- The figure --------------------------------------------------------------

func _queue_figure() -> void:
	_rebuild_in = REBUILD_DELAY


func _rebuild_figure() -> void:
	_rebuild_in = -1.0
	if _figure != null:
		_figure_root.remove_child(_figure)
		_figure.queue_free()
		_figure = null
	var face: FaceData = _spec.face
	if face == null:
		return
	var male: bool = _spec.sex == SimEnums.Sex.MALE
	var race: RaceDef = _ctx.defs.races[_spec.race_id]
	var looks: float = clampf((_spec.age_years - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)
	var gear: EquipmentData = EquipmentData.new()
	var kit: Dictionary = PlayerStart.BACKGROUNDS[_spec.background]
	gear.weapon_id = kit.get("weapon", &"") as StringName
	# Dressed as the people dress a newcomer of this kind, the background's kit over it, as PlayerStart will.
	gear.armour_ids = Outfits.outfit(_ctx.defs, _spec.culture_id, _spec.race_id, male, Outfits.POOR, &"commoner", 0)
	var armour: Array = kit.get("armour", [])
	for id: StringName in armour:
		Outfits.put_on(_ctx.defs, gear.armour_ids, id)
	var worn: Array[String] = BodyView.worn_for(gear, hash(_spec.given_name))
	_figure = BodyView.make(face, male, looks, worn)
	_figure_root.add_child(_figure)
	if not BodyView.has_own_body(face):
		FaceView.attach(_figure, face, male, looks)
	var clip: StringName = &"idle_unarmed" if gear.weapon_id == &"" else BodyView.kit_clip(ViewUtil.find_player(_figure), &"idle", worn)
	ViewUtil.play(_figure, clip, true)


func _process(delta: float) -> void:
	_time += delta
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			_rebuild_figure()
	if _figure_root == null:
		return
	if not _dragging and _time - _touched_at > 3.0:
		_yaw += IDLE_TURN * delta
	_figure_root.rotation.y = _yaw
	var eyes: float = 1.62
	if _figure != null:
		var skeleton: Skeleton3D = ViewUtil.find_skeleton(_figure)
		if skeleton != null:
			eyes = BodyView.eye_height(skeleton)
	var look_at: Vector3 = Vector3(0.0, lerpf(eyes * 0.55, eyes - 0.04, _close), 0.0)
	var distance: float = lerpf(eyes * 3.1, 0.95, _close)
	var from: Vector3 = Vector3(0.0, look_at.y + lerpf(0.15, 0.0, _close), distance)
	_camera.look_at_from_position(from, look_at, Vector3.UP)


func _stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
				_touched_at = _time
			MOUSE_BUTTON_WHEEL_UP:
				_close = clampf(_close + 0.08, 0.0, 1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_close = clampf(_close - 0.08, 0.0, 1.0)
	elif event is InputEventMouseMotion and _dragging:
		_yaw += (event as InputEventMouseMotion).relative.x * TURN_PER_PIXEL
		_touched_at = _time
