class_name ItemSlot
extends Button
## One thing worn or carried, in an iron-rimmed hollow: its picture from assets/icons, or the faint sign of the slot
## when nothing is in it, with a count in the corner. Pressing it does what the page gave it.

const ICON_DIRS: Array[String] = ["res://assets/icons/garments/%s.png", "res://assets/icons/weapons/%s.png"]

static var _icons: Dictionary[StringName, Texture2D] = {}

var _picture: TextureRect
var _ghost: Glyph
var _count: Label


## The baked picture of a garment or weapon, or null if none was baked.
static func icon_of(id: StringName) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var found: Texture2D = null
	for pattern: String in ICON_DIRS:
		var path: String = pattern % String(id)
		if ResourceLoader.exists(path):
			found = load(path) as Texture2D
			break
	_icons[id] = found
	return found


## A slot showing item (or nothing, with the sign of what goes there), count when more than one.
static func make(item: StringName, sign_kind: StringName, side: float = 72.0, count: int = 1) -> ItemSlot:
	var out: ItemSlot = ItemSlot.new()
	out.custom_minimum_size = Vector2(side, side)
	out.show_item(item, sign_kind, count)
	return out


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	add_theme_stylebox_override(&"normal", PanelStyle.slot_box(false, true))
	add_theme_stylebox_override(&"hover", PanelStyle.slot_box(true, true))
	add_theme_stylebox_override(&"pressed", PanelStyle.slot_box(true, true))
	add_theme_stylebox_override(&"hover_pressed", PanelStyle.slot_box(true, true))
	add_theme_stylebox_override(&"disabled", PanelStyle.slot_box(false, false))
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_picture = TextureRect.new()
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.offset_left = 4.0
	_picture.offset_top = 4.0
	_picture.offset_right = -4.0
	_picture.offset_bottom = -4.0
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_ghost = Glyph.make(&"shield", 10.0, Color(PanelStyle.GILT, 0.22))
	_ghost.shadow = false
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ghost.offset_left = 14.0
	_ghost.offset_top = 14.0
	_ghost.offset_right = -14.0
	_ghost.offset_bottom = -14.0
	add_child(_ghost)
	_count = MenuStyle.label("", 13, MenuStyle.BRIGHT)
	_count.add_theme_constant_override(&"outline_size", 4)
	_count.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left = -30.0
	_count.offset_top = -20.0
	_count.offset_right = -5.0
	_count.offset_bottom = -2.0
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)


func show_item(item: StringName, sign_kind: StringName, count: int = 1) -> void:
	var picture: Texture2D = icon_of(item) if item != &"" else null
	_picture.texture = picture
	_picture.visible = picture != null
	# Something with no picture yet shows its slot's sign, brighter than an empty slot's.
	_ghost.visible = picture == null
	_ghost.kind = sign_kind
	_ghost.color = Color(PanelStyle.GOLD, 0.75) if item != &"" else Color(PanelStyle.GILT, 0.2)
	_ghost.queue_redraw()
	_count.text = str(count) if count > 1 else ""
	add_theme_stylebox_override(&"normal", PanelStyle.slot_box(false, item != &""))
