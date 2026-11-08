class_name GamePanels
extends CanvasLayer
## The big panels over the map: character, inventory, party, family, kingdom, quests, book, chronicle. One open at a
## time, picked from a tab row or by its key (see OverworldControls.PANEL_KEYS). Each page is a GamePanel built fresh
## from state when shown. The lead owns this folder.

const ORDER: Array[StringName] = [&"character", &"inventory", &"party", &"family", &"kingdom", &"quests", &"book", &"chronicle"]
const TITLES: Dictionary[StringName, String] = {
	&"character": "Character", &"inventory": "Inventory", &"party": "Party", &"family": "Family",
	&"kingdom": "Kingdom", &"quests": "Quests", &"book": "Book of Ortel", &"chronicle": "Chronicle",
}
const KEYS: Dictionary[StringName, String] = {
	&"character": "C", &"inventory": "I", &"party": "P", &"family": "L", &"kingdom": "K", &"quests": "J", &"book": "N",
	&"chronicle": "",
}

var _ctx: SimContext
var _open: StringName = &""
var _root: Control
var _shade: ColorRect
var _panel: PanelContainer
var _tabs: HFlowContainer
var _title: Label
var _scroller: ScrollContainer
var _page: GamePanel
## Pages keep their own small state (such as the book's chosen page) while the map scene lives.
var _pages: Dictionary[StringName, GamePanel] = {}


func setup(ctx: SimContext) -> void:
	_ctx = ctx
	layer = 5
	# A layer does not pass a theme down, so the root carries it.
	_root = MenuStyle.hud_root(self)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.5)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 60.0
	_panel.offset_right = -60.0
	_panel.offset_top = 40.0
	_panel.offset_bottom = -40.0
	_root.add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	_panel.add_child(column)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override(&"h_separation", 6)
	_tabs.add_theme_constant_override(&"v_separation", 6)
	for panel: StringName in ORDER:
		var tab: Button = Button.new()
		tab.text = TITLES[panel] if KEYS[panel].is_empty() else "%s (%s)" % [TITLES[panel], KEYS[panel]]
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(show_panel.bind(panel))
		tab.name = String(panel)
		_tabs.add_child(tab)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(spacer)
	var shut: Button = Button.new()
	shut.text = "Close (Esc)"
	shut.focus_mode = Control.FOCUS_NONE
	shut.pressed.connect(close)
	_tabs.add_child(shut)
	column.add_child(_tabs)
	_title = MenuStyle.title("", 26)
	column.add_child(_title)
	column.add_child(MenuStyle.rule())
	_scroller = ScrollContainer.new()
	_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroller)
	_set_visible(false)


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
	for tab: Node in _tabs.get_children():
		if tab is Button and (tab as Button).toggle_mode:
			(tab as Button).button_pressed = tab.name == String(panel)
	_title.text = TITLES[panel]
	if _page != null and _page.get_parent() == _scroller:
		_scroller.remove_child(_page)
	_page = _page_for(panel)
	_scroller.add_child(_page)
	_scroller.scroll_vertical = 0
	refresh()
	_set_visible(true)


## Builds the open page again from state.
func refresh() -> void:
	if _page == null:
		return
	_page.clear()
	var me: CharacterData = _ctx.character(_ctx.world.player_character_id)
	if me == null:
		_page.text("Nobody.")
		return
	_page.fill(me)


func close() -> void:
	_open = &""
	_set_visible(false)


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
	page.redraw = refresh
	_pages[panel] = page
	return page


func _set_visible(on: bool) -> void:
	_shade.visible = on
	_panel.visible = on


func _exit_tree() -> void:
	for panel: StringName in _pages:
		if _pages[panel].get_parent() == null:
			_pages[panel].free()
