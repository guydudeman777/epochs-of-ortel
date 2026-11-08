class_name GamePanels
extends CanvasLayer
## The big panels over the map: character, inventory, party, family, kingdom, quests, book, chronicle. One open at a
## time, picked from a tab row or by its key (see OverworldControls.PANEL_KEYS). They read state; anything you decide in
## them goes through Actions. The lead owns this folder.

const ORDER: Array[StringName] = [&"character", &"inventory", &"party", &"family", &"kingdom", &"quests", &"book", &"chronicle"]
const TITLES: Dictionary[StringName, String] = {
	&"character": "Character", &"inventory": "Inventory", &"party": "Party", &"family": "Family",
	&"kingdom": "Kingdom", &"quests": "Quests", &"book": "Book of Ortel", &"chronicle": "Chronicle",
}

var _ctx: SimContext
var _open: StringName = &""
var _root: Control
var _shade: ColorRect
var _panel: PanelContainer
var _tabs: HBoxContainer
var _title: Label
var _body: RichTextLabel


func setup(ctx: SimContext) -> void:
	_ctx = ctx
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	MenuStyle.apply(_root)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.5)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 60.0
	_panel.offset_right = -60.0
	_panel.offset_top = 50.0
	_panel.offset_bottom = -50.0
	_root.add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	_panel.add_child(column)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 6)
	for panel: StringName in ORDER:
		var tab: Button = Button.new()
		tab.text = TITLES[panel]
		tab.toggle_mode = true
		tab.pressed.connect(show_panel.bind(panel))
		tab.name = String(panel)
		_tabs.add_child(tab)
	column.add_child(_tabs)
	_title = MenuStyle.title("", 26)
	column.add_child(_title)
	column.add_child(MenuStyle.rule())
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(_body)
	column.add_child(scroller)
	_set_visible(false)


func is_open() -> bool:
	return _open != &""


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
		(tab as Button).button_pressed = tab.name == String(panel)
	_title.text = TITLES[panel]
	_body.text = _words_for(panel)
	_set_visible(true)


func close() -> void:
	_open = &""
	_set_visible(false)


func _set_visible(on: bool) -> void:
	_shade.visible = on
	_panel.visible = on


## Stub text for each panel until it gets its own view.
func _words_for(panel: StringName) -> String:
	var c: CharacterData = _ctx.character(_ctx.world.player_character_id)
	if c == null:
		return "Nobody."
	match panel:
		&"character":
			return "[b]%s[/b], %d years old, %s." % [c.given_name, floori(_ctx.age_years(c)), GeneticsService.dominant_race(c)]
		&"inventory":
			var lines: PackedStringArray = PackedStringArray(["Coin %d" % c.inventory.gold])
			for item: StringName in c.inventory.items:
				lines.append("%s x%d" % [item, c.inventory.items[item]])
			lines.append("Worn: %s" % ", ".join(PackedStringArray(c.equipment.armour_ids)))
			return "\n".join(lines)
		&"quests":
			var open: PackedStringArray = PackedStringArray()
			for id: int in _ctx.world.quests:
				var q: QuestData = _ctx.world.quests[id]
				if q.taker_id == c.id and q.state == QuestData.State.TAKEN:
					open.append(q.summary)
			return "\n".join(open) if not open.is_empty() else "You have given your word to nobody."
		&"chronicle":
			var lines: PackedStringArray = PackedStringArray()
			var entries: Array[ChronicleEntry] = _ctx.world.chronicle
			for i: int in range(entries.size() - 1, maxi(entries.size() - 60, 0) - 1, -1):
				lines.append(entries[i].text)
			return "\n".join(lines)
	return "Not written yet."
