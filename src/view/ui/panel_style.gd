class_name PanelStyle
extends RefCounted
## The look of the big panels over the map: a book bound in dark tooled leather and iron, its pages of old vellum
## written in iron-gall ink, with gilt where it matters. Everything is drawn here in code, so no image file holds any
## of it. MenuStyle's theme still sets the fonts and the buttons; this adds the pages, cards, slots and marks.

const LEATHER: Color = Color(0.11, 0.075, 0.05)
const LEATHER_LIGHT: Color = Color(0.2, 0.135, 0.085)
const IRON: Color = Color(0.2, 0.2, 0.21)
const IRON_LIGHT: Color = Color(0.46, 0.45, 0.43)
const VELLUM: Color = Color(0.8, 0.72, 0.56)
const VELLUM_DARK: Color = Color(0.62, 0.52, 0.36)
const INK: Color = Color(0.17, 0.1, 0.06)
const INK_FADED: Color = Color(0.36, 0.26, 0.17)
const RUBRIC: Color = Color(0.55, 0.12, 0.07)
const GOLD: Color = Color(0.93, 0.8, 0.5)
const GILT: Color = Color(0.72, 0.56, 0.3)
const SLOT: Color = Color(0.055, 0.045, 0.038)
const GOOD: Color = Color(0.55, 0.75, 0.4)
const WOUND_COLORS: Array[Color] = [Color(0.3, 0.27, 0.22), Color(0.78, 0.62, 0.3), Color(0.85, 0.42, 0.18), Color(0.8, 0.16, 0.1),
		Color(0.45, 0.04, 0.04), Color(0.1, 0.08, 0.07)]
## How bars are filled for the things people have.
const BLOOD_BAR: Color = Color(0.62, 0.1, 0.07)
const XP_BAR: Color = Color(0.78, 0.6, 0.25)
const FOOD_BAR: Color = Color(0.45, 0.58, 0.24)
const STRENGTH_BAR: Color = Color(0.36, 0.5, 0.62)

static var _textures: Dictionary[StringName, Texture2D] = {}
static var _theme: Theme = null


## Variations for the panels, on top of MenuStyle's theme: Page, Card, Vellum, Slot, SlotLit, Tab and TabOn.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.set_type_variation(&"Page", &"PanelContainer")
	t.set_stylebox(&"panel", &"Page", page())
	t.set_type_variation(&"Card", &"PanelContainer")
	t.set_stylebox(&"panel", &"Card", card())
	t.set_type_variation(&"Vellum", &"PanelContainer")
	t.set_stylebox(&"panel", &"Vellum", vellum())
	t.set_type_variation(&"Ink", &"Label")
	t.set_color(&"font_color", &"Ink", INK)
	t.set_color(&"font_shadow_color", &"Ink", Color(0.0, 0.0, 0.0, 0.0))
	t.set_type_variation(&"InkText", &"RichTextLabel")
	t.set_color(&"default_color", &"InkText", INK)
	for kind: StringName in [&"Tab", &"TabOn"]:
		t.set_type_variation(kind, &"Button")
		var lit: bool = kind == &"TabOn"
		t.set_stylebox(&"normal", kind, _tab_box(lit, false))
		t.set_stylebox(&"hover", kind, _tab_box(lit, true))
		t.set_stylebox(&"pressed", kind, _tab_box(true, true))
		t.set_stylebox(&"hover_pressed", kind, _tab_box(true, true))
		t.set_stylebox(&"focus", kind, StyleBoxEmpty.new())
		t.set_color(&"font_color", kind, GOLD if lit else Color(0.72, 0.64, 0.5))
		t.set_color(&"font_hover_color", kind, MenuStyle.BRIGHT)
		t.set_color(&"font_pressed_color", kind, MenuStyle.BRIGHT)
		t.set_font(&"font", kind, MenuStyle.caps_font(true, 2))
		t.set_font_size(&"font_size", kind, 14)
	t.set_type_variation(&"Small", &"Button")
	t.set_font_size(&"font_size", &"Small", 14)
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"hover_pressed"]:
		var base: StyleBox = MenuStyle.theme().get_stylebox(state, &"Button").duplicate() as StyleBox
		base.content_margin_left = 10.0
		base.content_margin_right = 10.0
		base.content_margin_top = 4.0
		base.content_margin_bottom = 4.0
		t.set_stylebox(state, &"Small", base)
	_theme = t
	return t


## The leather the panels are bound in: grained, darker at the rim, with an iron band and rivets at the corners.
static func page() -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = _texture(&"page")
	style.texture_margin_left = 22.0
	style.texture_margin_right = 22.0
	style.texture_margin_top = 22.0
	style.texture_margin_bottom = 22.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.set_content_margin_all(26.0)
	return style


## A dark inset card on the leather, for a block of a page.
static func card(margin: float = 12.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.047, 0.036, 0.88)
	style.border_color = Color(0.32, 0.25, 0.16, 0.9)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(3)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 2.0)
	style.anti_aliasing = true
	return style


## A leaf of old vellum, stained and darker at its edges, to write on in ink.
static func vellum() -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = _texture(&"vellum")
	style.texture_margin_left = 18.0
	style.texture_margin_right = 18.0
	style.texture_margin_top = 18.0
	style.texture_margin_bottom = 18.0
	style.set_content_margin_all(18.0)
	return style


## An iron-rimmed hollow for one thing worn or carried. lit when the hand is over it or it is chosen.
static func slot_box(lit: bool = false, filled: bool = true) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SLOT.lightened(0.06) if filled else SLOT
	style.border_color = GILT if lit else Color(0.3, 0.27, 0.23)
	style.set_border_width_all(2)
	style.border_width_top = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4.0)
	style.shadow_color = Color(GOLD, 0.35) if lit else Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 6 if lit else 3
	style.anti_aliasing = true
	return style


static func _tab_box(lit: bool, hover: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.13, 0.07, 0.98) if lit else (Color(0.13, 0.09, 0.06, 0.95) if hover else Color(0.08, 0.06, 0.045, 0.92))
	style.border_color = GILT if lit else Color(0.3, 0.24, 0.16)
	style.border_width_top = 2
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 3 if lit else 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 7.0
	if lit:
		style.shadow_color = Color(GOLD, 0.18)
		style.shadow_size = 6
	style.anti_aliasing = true
	return style


static func _texture(which: StringName) -> Texture2D:
	if _textures.has(which):
		return _textures[which]
	var image: Image
	match which:
		&"page":
			image = _leather_image()
		_:
			image = _vellum_image()
	_textures[which] = ImageTexture.create_from_image(image)
	return _textures[which]


static func _noise(seed_value: int, frequency: float, octaves: int = 4) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


static func _leather_image() -> Image:
	var size: int = 128
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var grain: FastNoiseLite = _noise(3, 0.09, 3)
	var pores: FastNoiseLite = _noise(9, 0.6, 1)
	for y: int in range(size):
		for x: int in range(size):
			var edge: int = mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			var g: float = grain.get_noise_2d(float(x), float(y)) * 0.5 + pores.get_noise_2d(float(x), float(y)) * 0.25
			var c: Color = LEATHER.lerp(LEATHER_LIGHT, clampf(0.35 + g, 0.0, 1.0))
			if edge < 22:
				c = c.darkened(0.45 * (1.0 - float(edge) / 22.0))
			match edge:
				0:
					c = Color(0.01, 0.01, 0.01)
				1, 2, 3:
					c = IRON.lerp(IRON_LIGHT, 0.35 if edge == 1 else 0.1)
				4:
					c = Color(0.02, 0.02, 0.02)
				9:
					c = c.lerp(GILT, 0.5)
			c.a = 0.985
			image.set_pixel(x, y, c)
	for corner: Vector2i in [Vector2i(10, 10), Vector2i(size - 11, 10), Vector2i(10, size - 11), Vector2i(size - 11, size - 11)]:
		for dy: int in range(-5, 6):
			for dx: int in range(-5, 6):
				var d: float = Vector2(dx, dy).length()
				if d <= 4.6:
					var lit: float = clampf(1.0 - (Vector2(dx, dy) + Vector2(1.5, 1.5)).length() / 5.0, 0.0, 1.0)
					image.set_pixel(corner.x + dx, corner.y + dy, IRON.lerp(Color(0.75, 0.73, 0.68), lit))
	return image


static func _vellum_image() -> Image:
	var size: int = 96
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var stain: FastNoiseLite = _noise(17, 0.035, 4)
	var fibre: FastNoiseLite = _noise(21, 0.4, 2)
	for y: int in range(size):
		for x: int in range(size):
			var edge: float = float(mini(mini(x, y), mini(size - 1 - x, size - 1 - y)))
			var s: float = stain.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var f: float = fibre.get_noise_2d(float(x), float(y))
			var c: Color = VELLUM.lerp(VELLUM_DARK, clampf(s * 0.6 + f * 0.1, 0.0, 1.0))
			c = c.darkened(clampf((14.0 - edge) / 14.0, 0.0, 1.0) * 0.45)
			if edge < 1.0:
				c = c.darkened(0.5)
			image.set_pixel(x, y, c)
	return image


# --- Pieces -----------------------------------------------------------------------

## A title in carved gilt capitals.
static func caps(text: String, size: int = 16, color: Color = GOLD, spacing: int = 2) -> Label:
	return MenuStyle.title(text, size, color, spacing)


## Words in ink, for a vellum leaf.
static func ink(text: String, size: int = 17, color: Color = INK) -> Label:
	var out: Label = MenuStyle.label(text, size, color)
	out.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return out


## A plain word line on the leather.
static func words(text: String, size: int = 16, color: Color = MenuStyle.TEXT) -> Label:
	var out: Label = MenuStyle.label(text, size, color)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return out


## Rich text that grows to fit, on leather or (with ink colours) on vellum.
static func rich(bbcode: String, size: int = 16, on_vellum: bool = false) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"normal_font_size", size)
	label.add_theme_font_size_override(&"bold_font_size", size)
	label.add_theme_font_size_override(&"italics_font_size", size)
	if on_vellum:
		label.add_theme_color_override(&"default_color", INK)
	label.text = bbcode
	return label


## A panel of the given variation round a box of the given kind, returning the box.
static func boxed(parent: Control, variation: StringName, vertical: bool = true, separation: int = 6) -> BoxContainer:
	var holder: PanelContainer = PanelContainer.new()
	holder.theme_type_variation = variation
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.add_theme_constant_override(&"separation", separation)
	holder.add_child(box)
	return box


## A heading with a sign before it and a thin gilt rule after.
static func heading(parent: Control, text: String, sign_kind: StringName = &"") -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	if sign_kind != &"":
		line.add_child(Glyph.make(sign_kind, 18.0, GILT))
	var label: Label = MenuStyle.heading(text)
	label.add_theme_color_override(&"font_color", GILT)
	line.add_child(label)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(GILT, 0.3)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(rule)
	parent.add_child(line)
	return line


## A sign and a number side by side, as "coin 120".
static func tally(sign_kind: StringName, text: String, color: Color = MenuStyle.TEXT, tip: String = "") -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 5)
	line.add_child(Glyph.make(sign_kind, 18.0, GILT))
	line.add_child(MenuStyle.label(text, 16, color))
	line.tooltip_text = tip
	line.mouse_filter = Control.MOUSE_FILTER_PASS if not tip.is_empty() else Control.MOUSE_FILTER_IGNORE
	return line


## A small button.
static func button(text: String, action: Callable) -> Button:
	var out: Button = Button.new()
	out.text = text
	out.theme_type_variation = &"Small"
	out.focus_mode = Control.FOCUS_NONE
	out.pressed.connect(action)
	return out
