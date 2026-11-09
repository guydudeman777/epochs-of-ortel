class_name ChroniclePanel
extends GamePanel
## What has happened in Ortel, newest first, written up year by year on vellum, with a mark for each kind of
## happening and a row of filters to read only wars, or only deaths, or only your own doings.

const SHOWN: int = 200
## Filter -> [title, the entry kinds it shows, its sign]. All shows everything.
const FILTERS: Array[Array] = [
	[&"all", "All", [], &"book"], [&"war", "Wars", [&"war"], &"sword"], [&"realm", "Realms", [&"faction"], &"crown"],
	[&"law", "Laws", [&"law"], &"scroll"], [&"death", "Deaths", [&"death", &"maimed"], &"skull"], [&"bondage", "Bondage", [&"bondage"], &"chain"],
	[&"revolt", "Revolts", [&"revolt"], &"flame"], [&"craft", "Crafts", [&"tech"], &"anvil"], [&"player", "You", [&"player"], &"helm"],
]
const KIND_SIGNS: Dictionary[StringName, StringName] = {
	&"war": &"sword", &"faction": &"crown", &"law": &"scroll", &"death": &"skull", &"maimed": &"drop", &"bondage": &"chain",
	&"revolt": &"flame", &"tech": &"anvil", &"player": &"helm",
}

var _filter: StringName = &"all"


func fill(_me: CharacterData) -> void:
	var bar: HFlowContainer = HFlowContainer.new()
	bar.add_theme_constant_override(&"h_separation", 6)
	bar.add_theme_constant_override(&"v_separation", 6)
	add_child(bar)
	var kinds: Array = []
	for filter: Array in FILTERS:
		var button: Button = Button.new()
		button.text = "      %s" % (filter[1] as String)
		button.theme_type_variation = &"TabOn" if filter[0] == _filter else &"Tab"
		button.focus_mode = Control.FOCUS_NONE
		button.name = "filter_" + String(filter[0] as StringName)
		button.pressed.connect(_choose.bind(filter[0] as StringName))
		var sign: Glyph = Glyph.make(filter[3] as StringName, 16.0, PanelStyle.GOLD if filter[0] == _filter else PanelStyle.GILT)
		sign.position = Vector2(10.0, 8.0)
		sign.size = Vector2(16.0, 16.0)
		button.add_child(sign)
		bar.add_child(button)
		if filter[0] == _filter:
			kinds = filter[2] as Array
	var page: BoxContainer = PanelStyle.boxed(self, &"Vellum", true, 3)
	var entries: Array[ChronicleEntry] = ctx.world.chronicle
	var year: int = -1
	var shown: int = 0
	for i: int in range(entries.size() - 1, -1, -1):
		var e: ChronicleEntry = entries[i]
		if not kinds.is_empty() and not kinds.has(e.kind):
			continue
		var entry_year: int = floori(float(e.day) / CalendarData.DAYS_PER_YEAR)
		if entry_year != year:
			year = entry_year
			var header: Label = MenuStyle.title("Year %d" % year, 18, PanelStyle.RUBRIC, 3)
			header.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
			if shown > 0:
				var gap: Control = Control.new()
				gap.custom_minimum_size = Vector2(0.0, 8.0)
				page.add_child(gap)
			page.add_child(header)
		page.add_child(_line(e))
		shown += 1
		if shown >= SHOWN:
			break
	if shown == 0:
		page.add_child(PanelStyle.ink("Nothing of that kind worth writing down, yet." if not kinds.is_empty() else "Nothing worth writing down, yet.", 17,
				PanelStyle.INK_FADED))


func _line(e: ChronicleEntry) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	var when: Label = PanelStyle.ink("M%d D%d" % [floori(float(e.day % CalendarData.DAYS_PER_YEAR) / CalendarData.DAYS_PER_MONTH) + 1, e.day % CalendarData.DAYS_PER_MONTH + 1],
			14, PanelStyle.INK_FADED)
	when.autowrap_mode = TextServer.AUTOWRAP_OFF
	when.custom_minimum_size = Vector2(64.0, 0.0)
	line.add_child(when)
	var sign: Glyph = Glyph.make(KIND_SIGNS.get(e.kind, &"quill") as StringName, 18.0, PanelStyle.RUBRIC if e.kind == &"war" or e.kind == &"death" else PanelStyle.INK)
	sign.shadow = false
	line.add_child(sign)
	var words: Label = PanelStyle.ink(e.text, 16)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	return line


func _choose(filter: StringName) -> void:
	_filter = filter
	if redraw.is_valid():
		redraw.call()
