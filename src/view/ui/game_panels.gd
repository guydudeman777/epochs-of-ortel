class_name GamePanels
extends CanvasLayer
## The big panels over the map: character, inventory, party, family, kingdom, quests, book, chronicle. One open at a
## time, picked from a row of bookmarks or by its key (see OverworldControls.PANEL_KEYS). Each page is a GamePanel
## built fresh from state when shown, in a book bound in leather and iron (PanelStyle).

const ORDER: Array[StringName] = [&"character", &"inventory", &"party", &"family", &"kingdom", &"quests", &"book", &"chronicle"]
const TITLES: Dictionary[StringName, String] = {
	&"character": "Character", &"inventory": "Inventory", &"party": "Party", &"family": "Family",
	&"kingdom": "Kingdom", &"quests": "Quests", &"book": "Book of Ortel", &"chronicle": "Chronicle",
}
const KEYS: Dictionary[StringName, String] = {
	&"character": "C", &"inventory": "I", &"party": "P", &"family": "L", &"kingdom": "K", &"quests": "J", &"book": "N",
	&"chronicle": "",
}
## The sign on each bookmark.
const SIGNS: Dictionary[StringName, StringName] = {
	&"character": &"helm", &"inventory": &"chest", &"party": &"banner", &"family": &"tree_family", &"kingdom": &"crown",
	&"quests": &"seal", &"book": &"book", &"chronicle": &"quill",
}
const MARGIN_X: float = 48.0
const MARGIN_Y: float = 28.0

var _ctx: SimContext
var _open: StringName = &""
var _root: Control
var _shade: ColorRect
var _vignette: TextureRect
var _panel: PanelContainer
var _tabs: HBoxContainer
var _tab_buttons: Dictionary[StringName, Button] = {}
var _title: Label
var _subtitle: Label
var _body: Control
var _scroller: ScrollContainer
var _page: GamePanel
var _shots: PortraitShots
## Pages keep their own small state (such as the book's chosen page) while the map scene lives.
var _pages: Dictionary[StringName, GamePanel] = {}


func setup(ctx: SimContext) -> void:
	_ctx = ctx
	layer = 5
	_shots = PortraitShots.new()
	_shots.ctx = ctx
	add_child(_shots)
	# A layer does not pass a theme down, so the root carries it.
	_root = MenuStyle.hud_root(self)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_vignette = MenuStyle.vignette(_root, 0.8)
	var frame: Control = Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = MARGIN_X
	frame.offset_right = -MARGIN_X
	frame.offset_top = MARGIN_Y
	frame.offset_bottom = -MARGIN_Y
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme = PanelStyle.theme()
	_root.add_child(frame)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override(&"separation", -2)
	frame.add_child(outer)
	# The bookmarks stand out above the binding.
	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override(&"separation", 0)
	outer.add_child(tab_row)
	var indent: Control = Control.new()
	indent.custom_minimum_size = Vector2(26.0, 0.0)
	tab_row.add_child(indent)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 4)
	tab_row.add_child(_tabs)
	for panel: StringName in ORDER:
		_tabs.add_child(_make_tab(panel))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(spacer)
	var shut: Button = Button.new()
	shut.text = "Close  Esc"
	shut.theme_type_variation = &"Tab"
	shut.focus_mode = Control.FOCUS_NONE
	shut.pressed.connect(close)
	tab_row.add_child(shut)
	var tail: Control = Control.new()
	tail.custom_minimum_size = Vector2(26.0, 0.0)
	tab_row.add_child(tail)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"Page"
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	_panel.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override(&"separation", 16)
	column.add_child(heading)
	_title = MenuStyle.title("", 28)
	heading.add_child(_title)
	_subtitle = MenuStyle.label("", 16, MenuStyle.DIM)
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_subtitle)
	column.add_child(MenuStyle.rule())
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	_scroller = ScrollContainer.new()
	_scroller.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroller)
	_set_visible(false)


func _make_tab(panel: StringName) -> Button:
	var tab: Button = Button.new()
	tab.name = String(panel)
	tab.text = "      " + TITLES[panel]
	tab.theme_type_variation = &"Tab"
	tab.focus_mode = Control.FOCUS_NONE
	tab.tooltip_text = TITLES[panel] if KEYS[panel].is_empty() else "%s (%s)" % [TITLES[panel], KEYS[panel]]
	tab.pressed.connect(show_panel.bind(panel))
	var sign: Glyph = Glyph.make(SIGNS[panel], 18.0, PanelStyle.GILT)
	sign.position = Vector2(10.0, 8.0)
	sign.size = Vector2(18.0, 18.0)
	tab.add_child(sign)
	_tab_buttons[panel] = tab
	return tab


func is_open() -> bool:
	return _open != &""


func open_panel() -> StringName:
	return _open


func toggle(panel: StringName) -> void:
	if _open == panel:
		close()
	else:
		show_panel(panel)


func show_panel(panel: StringName) -> void:
	if not TITLES.has(panel):
		return
	_open = panel
	for key: StringName in _tab_buttons:
		var tab: Button = _tab_buttons[key]
		tab.theme_type_variation = &"TabOn" if key == panel else &"Tab"
		var sign: Glyph = tab.get_child(0) as Glyph
		sign.color = PanelStyle.GOLD if key == panel else PanelStyle.GILT
		sign.queue_redraw()
	_title.text = TITLES[panel].to_upper()
	if _page != null and _page.get_parent() != null:
		_page.get_parent().remove_child(_page)
	_page = _page_for(panel)
	_scroller.visible = _page.scrolls
	if _page.scrolls:
		_scroller.add_child(_page)
		_scroller.scroll_vertical = 0
	else:
		_page.set_anchors_preset(Control.PRESET_FULL_RECT)
		_body.add_child(_page)
	refresh()
	_set_visible(true)


## Builds the open page again from state.
func refresh() -> void:
	if _page == null:
		return
	_page.clear()
	var me: CharacterData = _ctx.character(_ctx.world.player_character_id)
	_subtitle.text = _when()
	if me == null:
		_page.text("Nobody.")
		return
	_subtitle.text = "%s   ·   %s" % [me.given_name, _when()]
	_page.fill(me)


func close() -> void:
	_open = &""
	_set_visible(false)


## The date as the chronicle writes it.
func _when() -> String:
	var day: int = _ctx.today()
	return "Year %d, month %d, day %d" % [floori(float(day) / CalendarData.DAYS_PER_YEAR), floori(float(day % CalendarData.DAYS_PER_YEAR) / CalendarData.DAYS_PER_MONTH) + 1,
			day % CalendarData.DAYS_PER_MONTH + 1]


func _page_for(panel: StringName) -> GamePanel:
	if _pages.has(panel):
		return _pages[panel]
	var page: GamePanel
	match panel:
		&"character":
			page = CharacterPanel.new()
		&"inventory":
			page = InventoryPanel.new()
		&"party":
			page = PartyPanel.new()
		&"family":
			page = FamilyPanel.new()
		&"kingdom":
			page = KingdomPanel.new()
		&"quests":
			page = QuestsPanel.new()
		&"book":
			page = BookPanel.new()
		_:
			page = ChroniclePanel.new()
	page.ctx = _ctx
	page.shots = _shots
	page.redraw = refresh
	_pages[panel] = page
	return page


func _set_visible(on: bool) -> void:
	_shade.visible = on
	_vignette.visible = on
	(_panel.get_parent().get_parent() as Control).visible = on


func _exit_tree() -> void:
	for panel: StringName in _pages:
		if _pages[panel].get_parent() == null:
			_pages[panel].free()
