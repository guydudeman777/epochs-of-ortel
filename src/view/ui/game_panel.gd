class_name GamePanel
extends VBoxContainer
## One page of the big panels. fill() builds it from state each time it is shown or after you act in it. It reads
## state and sends what you decide through Actions; it never changes the world itself.

## Set by GamePanels before fill(); call it after an action so the page shows the new state.
var redraw: Callable
var ctx: SimContext


func _init() -> void:
	add_theme_constant_override(&"separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Builds the page. me is the player's character, never null.
func fill(_me: CharacterData) -> void:
	pass


func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func heading(text: String) -> void:
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	add_child(gap)
	add_child(MenuStyle.heading(text))


func text(bbcode: String) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = bbcode
	add_child(label)
	return label


## A line of text with buttons after it. Each action is [label, Callable].
func row(bbcode: String, actions: Array[Array] = []) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = bbcode
	line.add_child(label)
	for action: Array in actions:
		var button: Button = Button.new()
		button.text = action[0] as String
		button.custom_minimum_size = Vector2(110.0, 30.0)
		button.pressed.connect(action[1] as Callable)
		line.add_child(button)
	add_child(line)
	return line


## Runs an action for the player and shows the page again, with the reason if it failed.
func act(action: Callable) -> void:
	var result: ActionResult = action.call()
	if redraw.is_valid():
		redraw.call()
	if not result.success:
		text("[color=#%s]%s[/color]" % [MenuStyle.BAD.to_html(false), String(result.reason).replace("_", " ").capitalize()])


# --- Words shared by the pages ---------------------------------------------

## A living or dead person, by id.
func person(id: int) -> CharacterData:
	var c: CharacterData = ctx.character(id)
	if c == null:
		c = ctx.world.archived_characters.get(id, null)
	return c


func name_of(id: int) -> String:
	var c: CharacterData = person(id)
	if c == null:
		return "nobody"
	if c.death_day < 0:
		return c.given_name
	return "%s [color=#%s](dead)[/color]" % [c.given_name, MenuStyle.FAINT.to_html(false)]


func realm_name(faction_id: int) -> String:
	var f: FactionData = ctx.faction(faction_id)
	return f.display_name if f != null else "no realm"


func town_name(settlement_id: int) -> String:
	var s: SettlementData = ctx.settlement(settlement_id)
	return s.display_name if s != null else "nowhere"


static func enum_word(keys: Array, value: int) -> String:
	return str(keys[value]).replace("_", " ").to_lower()


static func sorted_names(keys: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(keys)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func dim(words: String) -> String:
	return "[color=#%s]%s[/color]" % [MenuStyle.DIM.to_html(false), words]
