class_name MenuStyle
extends RefCounted
## The look shared by every screen: dark leather, old gold, iron and soot.
##
## The theme is built once and set on the root window, so every control in every scene takes it, HUD layers too.
## Panels are a carved frame drawn here in code, so no image file holds any of it.

const BACK: Color = Color(0.045, 0.04, 0.035)
const PANEL: Color = Color(0.075, 0.066, 0.055, 0.97)
const EDGE: Color = Color(0.45, 0.39, 0.27)
const BRONZE: Color = Color(0.3, 0.24, 0.15)
const GOLD: Color = Color(0.93, 0.84, 0.62)
const BRIGHT: Color = Color(1.0, 0.93, 0.74)
const TEXT: Color = Color(0.86, 0.82, 0.74)
const DIM: Color = Color(0.6, 0.56, 0.48)
const FAINT: Color = Color(0.4, 0.37, 0.32)
const BAD: Color = Color(0.9, 0.5, 0.42)
const BLOOD: Color = Color(0.55, 0.12, 0.08)
const MAP_TEXTURE: String = "res://tools/map/ortel_preview.png"
## Old book faces found on most machines, for when the bundled ones are missing.
const SERIF: PackedStringArray = ["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "Times New Roman", "serif"]
const BOOK: String = "res://assets/fonts/EBGaramond.ttf"
const BOOK_ITALIC: String = "res://assets/fonts/EBGaramond-Italic.ttf"
const CAPS: String = "res://assets/fonts/Cinzel.ttf"
const FRAME_SIZE: int = 48
const FRAME_MARGIN: int = 14

static var _theme: Theme
static var _fonts: Dictionary[StringName, Font] = {}


## The book face (EB Garamond), plain, bold, italic or both. Old faces on the machine stand in if the files are gone.
static func font(bold: bool = false, italic: bool = false) -> Font:
	var key: StringName = StringName("%s%s" % ["b" if bold else "", "i" if italic else ""])
	if not _fonts.has(key):
		_fonts[key] = _weighted(BOOK_ITALIC if italic else BOOK, 600 if bold else 420, bold, italic)
	return _fonts[key]


## Carved capitals (Cinzel) cut wide apart, for titles and headings.
static func caps_font(bold: bool = true, spacing: int = 3) -> Font:
	var key: StringName = StringName("caps%s%d" % ["b" if bold else "", spacing])
	if not _fonts.has(key):
		var wide: FontVariation = _weighted(CAPS, 700 if bold else 500, bold, false)
		wide.set_spacing(TextServer.SPACING_GLYPH, spacing)
		_fonts[key] = wide
	return _fonts[key]


static func _weighted(path: String, weight: int, bold: bool, italic: bool) -> FontVariation:
	var out: FontVariation = FontVariation.new()
	if ResourceLoader.exists(path):
		var file: FontFile = load(path) as FontFile
		file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		file.hinting = TextServer.HINTING_LIGHT
		out.base_font = file
		var wght: int = TextServerManager.get_primary_interface().name_to_tag("wght")
		out.variation_opentype = {wght: weight}
	else:
		var system: SystemFont = SystemFont.new()
		system.font_names = SERIF
		system.font_weight = 700 if bold else 400
		system.font_italic = italic
		out.base_font = system
	return out


static func box(fill: Color, edge: Color, margin: float = 10.0, width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_content_margin_all(margin)
	style.set_corner_radius_all(2)
	style.anti_aliasing = true
	return style


## A button: a heavier bar down its left side, dull at rest and gilt with a glow when the hand is on it.
static func _button_box(fill: Color, edge: Color, glow: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = box(fill, edge, 8.0)
	style.content_margin_left = 16.0
	style.content_margin_right = 14.0
	style.border_width_left = 3
	style.border_width_bottom = 2
	if glow > 0.0:
		style.shadow_color = Color(GOLD, glow)
		style.shadow_size = 8
	return style


## Every look in one theme, built once.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	t.set_stylebox(&"panel", &"PanelContainer", frame())
	t.set_stylebox(&"panel", &"Panel", frame())
	_buttons(t)
	t.set_stylebox(&"normal", &"LineEdit", box(Color(0.06, 0.053, 0.044), BRONZE, 7.0))
	t.set_stylebox(&"focus", &"LineEdit", box(Color(0.0, 0.0, 0.0, 0.0), GOLD, 7.0))
	t.set_stylebox(&"read_only", &"LineEdit", box(Color(0.06, 0.053, 0.044), Color(0.18, 0.16, 0.12), 7.0))
	t.set_color(&"font_color", &"LineEdit", GOLD)
	t.set_color(&"caret_color", &"LineEdit", BRIGHT)
	t.set_color(&"selection_color", &"LineEdit", Color(EDGE, 0.5))
	t.set_color(&"font_placeholder_color", &"LineEdit", FAINT)
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_shadow_color", &"Label", Color(0.0, 0.0, 0.0, 0.45))
	t.set_constant(&"shadow_offset_x", &"Label", 0)
	t.set_constant(&"shadow_offset_y", &"Label", 1)
	for kind: StringName in [&"CheckBox", &"CheckButton"]:
		t.set_stylebox(&"normal", kind, StyleBoxEmpty.new())
		t.set_stylebox(&"hover", kind, StyleBoxEmpty.new())
		t.set_stylebox(&"pressed", kind, StyleBoxEmpty.new())
		t.set_stylebox(&"focus", kind, StyleBoxEmpty.new())
		t.set_color(&"font_color", kind, TEXT)
		t.set_color(&"font_hover_color", kind, GOLD)
		t.set_color(&"font_pressed_color", kind, GOLD)
		t.set_color(&"font_hover_pressed_color", kind, BRIGHT)
		t.set_color(&"font_focus_color", kind, GOLD)
		t.set_color(&"font_disabled_color", kind, FAINT)
	t.set_icon(&"checked", &"CheckBox", _check_icon(true))
	t.set_icon(&"unchecked", &"CheckBox", _check_icon(false))
	t.set_icon(&"radio_checked", &"CheckBox", _check_icon(true))
	t.set_icon(&"radio_unchecked", &"CheckBox", _check_icon(false))
	t.set_color(&"default_color", &"RichTextLabel", TEXT)
	t.set_font(&"normal_font", &"RichTextLabel", font())
	t.set_font(&"bold_font", &"RichTextLabel", font(true))
	t.set_font(&"italics_font", &"RichTextLabel", font(false, true))
	t.set_font(&"bold_italics_font", &"RichTextLabel", font(true, true))
	t.set_font_size(&"normal_font_size", &"RichTextLabel", 18)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", 18)
	t.set_font_size(&"italics_font_size", &"RichTextLabel", 18)
	t.set_constant(&"line_separation", &"RichTextLabel", 2)
	_sliders(t)
	_scrollbars(t)
	_popups(t)
	_hud(t)
	_theme = t
	return t


static func _buttons(t: Theme) -> void:
	for kind: StringName in [&"Button", &"OptionButton", &"MenuButton"]:
		t.set_stylebox(&"normal", kind, _button_box(Color(0.1, 0.087, 0.07, 0.96), Color(0.26, 0.21, 0.14), 0.0))
		var hover: StyleBoxFlat = _button_box(Color(0.17, 0.135, 0.085, 0.98), Color(0.62, 0.5, 0.3), 0.16)
		t.set_stylebox(&"hover", kind, hover)
		t.set_stylebox(&"hover_pressed", kind, hover)
		t.set_stylebox(&"pressed", kind, _button_box(Color(0.24, 0.18, 0.1), GOLD, 0.25))
		var focus: StyleBoxFlat = box(Color(0.0, 0.0, 0.0, 0.0), Color(GOLD, 0.75), 8.0)
		focus.border_width_left = 3
		t.set_stylebox(&"focus", kind, focus)
		t.set_stylebox(&"disabled", kind, _button_box(Color(0.07, 0.063, 0.053, 0.9), Color(0.16, 0.14, 0.11), 0.0))
		t.set_color(&"font_color", kind, TEXT)
		t.set_color(&"font_hover_color", kind, BRIGHT)
		t.set_color(&"font_pressed_color", kind, BRIGHT)
		t.set_color(&"font_hover_pressed_color", kind, BRIGHT)
		t.set_color(&"font_focus_color", kind, GOLD)
		t.set_color(&"font_disabled_color", kind, FAINT)
		t.set_color(&"font_outline_color", kind, Color(0.0, 0.0, 0.0, 0.6))
	# Buttons that are only a word, for small tools beside a field.
	t.set_type_variation(&"FlatButton", &"Button")
	var flat: StyleBoxFlat = box(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 4.0, 0)
	t.set_stylebox(&"normal", &"FlatButton", flat)
	t.set_stylebox(&"hover", &"FlatButton", box(Color(GOLD, 0.06), Color(0.0, 0.0, 0.0, 0.0), 4.0, 0))
	t.set_stylebox(&"pressed", &"FlatButton", box(Color(GOLD, 0.12), Color(0.0, 0.0, 0.0, 0.0), 4.0, 0))
	t.set_color(&"font_color", &"FlatButton", DIM)


static func _sliders(t: Theme) -> void:
	var track: StyleBoxFlat = box(Color(0.05, 0.045, 0.038), Color(0.22, 0.18, 0.12), 0.0)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	t.set_stylebox(&"slider", &"HSlider", track)
	var filled: StyleBoxFlat = box(Color(0.5, 0.4, 0.24), Color(0.62, 0.5, 0.3), 0.0)
	filled.content_margin_top = 3.0
	filled.content_margin_bottom = 3.0
	t.set_stylebox(&"grabber_area", &"HSlider", filled)
	var lit: StyleBoxFlat = filled.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.7, 0.58, 0.36)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", lit)
	t.set_icon(&"grabber", &"HSlider", _diamond_icon(16, Color(0.78, 0.66, 0.42), Color(0.12, 0.09, 0.05)))
	t.set_icon(&"grabber_highlight", &"HSlider", _diamond_icon(16, BRIGHT, Color(0.2, 0.15, 0.08)))
	t.set_icon(&"grabber_disabled", &"HSlider", _diamond_icon(16, FAINT, Color(0.1, 0.09, 0.07)))


static func _scrollbars(t: Theme) -> void:
	for kind: StringName in [&"VScrollBar", &"HScrollBar"]:
		var lane: StyleBoxFlat = box(Color(0.0, 0.0, 0.0, 0.25), Color(0.0, 0.0, 0.0, 0.0), 0.0, 0)
		lane.set_content_margin_all(3.0)
		t.set_stylebox(&"scroll", kind, lane)
		t.set_stylebox(&"scroll_focus", kind, lane)
		var grab: StyleBoxFlat = box(Color(0.36, 0.29, 0.18), Color(0.0, 0.0, 0.0, 0.0), 0.0, 0)
		grab.set_corner_radius_all(3)
		grab.set_content_margin_all(3.0)
		t.set_stylebox(&"grabber", kind, grab)
		var grab_lit: StyleBoxFlat = grab.duplicate() as StyleBoxFlat
		grab_lit.bg_color = Color(0.62, 0.5, 0.3)
		t.set_stylebox(&"grabber_highlight", kind, grab_lit)
		t.set_stylebox(&"grabber_pressed", kind, grab_lit)


static func _popups(t: Theme) -> void:
	var sheet: StyleBoxFlat = box(Color(0.07, 0.062, 0.052, 0.99), EDGE, 6.0)
	sheet.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	sheet.shadow_size = 10
	t.set_stylebox(&"panel", &"PopupMenu", sheet)
	t.set_stylebox(&"hover", &"PopupMenu", box(Color(0.2, 0.155, 0.095), Color(0.0, 0.0, 0.0, 0.0), 4.0, 0))
	t.set_color(&"font_color", &"PopupMenu", TEXT)
	t.set_color(&"font_hover_color", &"PopupMenu", BRIGHT)
	t.set_color(&"font_disabled_color", &"PopupMenu", FAINT)
	t.set_font(&"font", &"PopupMenu", font())
	t.set_stylebox(&"panel", &"TooltipPanel", sheet)
	t.set_color(&"font_color", &"TooltipLabel", TEXT)


## The plates the HUD sits on in the field: smoked glass with a thin gilt rim.
static func _hud(t: Theme) -> void:
	t.set_type_variation(&"HudPanel", &"PanelContainer")
	var plate: StyleBoxFlat = StyleBoxFlat.new()
	plate.bg_color = Color(0.04, 0.035, 0.03, 0.72)
	plate.border_color = Color(0.62, 0.5, 0.3, 0.45)
	plate.border_width_top = 1
	plate.border_width_bottom = 1
	plate.set_corner_radius_all(3)
	plate.content_margin_left = 14.0
	plate.content_margin_right = 14.0
	plate.content_margin_top = 9.0
	plate.content_margin_bottom = 9.0
	plate.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	plate.shadow_size = 6
	plate.anti_aliasing = true
	t.set_stylebox(&"panel", &"HudPanel", plate)
	# A banner: darker, heavier, gilt both ends. For counts and the date.
	t.set_type_variation(&"BannerPanel", &"PanelContainer")
	var banner: StyleBoxFlat = plate.duplicate() as StyleBoxFlat
	banner.bg_color = Color(0.05, 0.042, 0.034, 0.86)
	banner.border_color = Color(0.62, 0.5, 0.3, 0.8)
	banner.set_border_width_all(1)
	banner.border_width_left = 3
	banner.border_width_right = 3
	banner.content_margin_left = 22.0
	banner.content_margin_right = 22.0
	banner.content_margin_top = 6.0
	banner.content_margin_bottom = 6.0
	t.set_stylebox(&"panel", &"BannerPanel", banner)
	# Nothing behind it at all, for the fight, where the field must show.
	t.set_type_variation(&"BarePanel", &"PanelContainer")
	t.set_stylebox(&"panel", &"BarePanel", StyleBoxEmpty.new())
	t.set_type_variation(&"HudText", &"RichTextLabel")
	t.set_color(&"font_outline_color", &"HudText", Color(0.0, 0.0, 0.0, 0.8))
	t.set_constant(&"outline_size", &"HudText", 3)
	t.set_font_size(&"normal_font_size", &"HudText", 16)
	t.set_font_size(&"bold_font_size", &"HudText", 16)
	t.set_font_size(&"italics_font_size", &"HudText", 16)
	t.set_type_variation(&"HudLabel", &"Label")
	t.set_color(&"font_outline_color", &"HudLabel", Color(0.0, 0.0, 0.0, 0.85))
	t.set_constant(&"outline_size", &"HudLabel", 4)


## The carved frame round every menu: an iron rim, a bronze band, a gilt line set in, and a stud at each corner.
static func frame(fill_alpha: float = 0.97) -> StyleBoxTexture:
	var size: int = FRAME_SIZE
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var base: Color = Color(PANEL, fill_alpha)
	for y: int in range(size):
		for x: int in range(size):
			var edge: int = mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			var grain: float = rng.randf_range(-0.012, 0.012) + sin(float(y) * 0.9 + float(x) * 0.13) * 0.004
			var c: Color = Color(base.r + grain, base.g + grain * 0.9, base.b + grain * 0.7, base.a)
			if edge < FRAME_MARGIN:
				# Darker toward the rim, as leather wears.
				var wear: float = float(edge) / float(FRAME_MARGIN)
				c = c.darkened(0.35 * (1.0 - wear))
			match edge:
				0:
					c = Color(0.01, 0.009, 0.008, 1.0)
				1, 2:
					c = Color(0.36, 0.29, 0.18, 1.0).darkened(0.25 if edge == 2 else 0.0)
				3:
					c = Color(0.03, 0.026, 0.02, 1.0)
				6:
					c = Color(0.66, 0.54, 0.33, 0.85)
			image.set_pixel(x, y, c)
	# A gilt stud at each corner, over the inner line.
	for corner: Vector2i in [Vector2i(6, 6), Vector2i(size - 7, 6), Vector2i(6, size - 7), Vector2i(size - 7, size - 7)]:
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				var d: int = absi(dx) + absi(dy)
				if d <= 4:
					var lit: Color = BRIGHT if d <= 1 else (Color(0.78, 0.64, 0.38) if d <= 3 else Color(0.2, 0.15, 0.08))
					image.set_pixel(corner.x + dx, corner.y + dy, lit)
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.texture_margin_left = FRAME_MARGIN
	style.texture_margin_top = FRAME_MARGIN
	style.texture_margin_right = FRAME_MARGIN
	style.texture_margin_bottom = FRAME_MARGIN
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.set_content_margin_all(24.0)
	return style


static func _diamond_icon(size: int, fill: Color, rim: Color) -> ImageTexture:
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = float(size - 1) * 0.5
	for y: int in range(size):
		for x: int in range(size):
			var d: float = absf(float(x) - half) + absf(float(y) - half)
			if d <= half - 1.0:
				image.set_pixel(x, y, fill.lightened(0.25) if d < half * 0.35 else fill)
			elif d <= half:
				image.set_pixel(x, y, rim)
			else:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


static func _check_icon(on: bool) -> ImageTexture:
	var size: int = 18
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y: int in range(1, size - 1):
		for x: int in range(1, size - 1):
			var rim: bool = x == 1 or y == 1 or x == size - 2 or y == size - 2
			image.set_pixel(x, y, Color(0.62, 0.5, 0.3) if rim else Color(0.05, 0.045, 0.038))
	if on:
		var half: float = float(size - 1) * 0.5
		for y: int in range(size):
			for x: int in range(size):
				if absf(float(x) - half) + absf(float(y) - half) <= 4.5:
					image.set_pixel(x, y, GOLD)
	return ImageTexture.create_from_image(image)


## Sets the look on the whole window, for popups and anything parented to it.
static func apply(node: Node) -> void:
	node.get_tree().root.theme = theme()


## A see-through screen-sized control on a canvas layer, carrying the theme, since a layer does not pass one down.
static func hud_root(layer: CanvasLayer) -> Control:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme()
	layer.add_child(root)
	return root


## The book face on a name hung over the land.
static func style_label_3d(label: Label3D, color: Color = Color.WHITE) -> void:
	label.font = caps_font(true, 1)
	label.outline_modulate = Color(0.05, 0.035, 0.02, 0.9)
	if color != Color.WHITE:
		label.modulate = color


static func label(text: String, size: int = 17, color: Color = TEXT) -> Label:
	var out: Label = Label.new()
	out.text = text
	out.add_theme_font_size_override(&"font_size", size)
	out.add_theme_color_override(&"font_color", color)
	return out


## Wide-set capitals in gold, for the name of a screen or a menu.
static func title(text: String, size: int = 28, color: Color = GOLD, spacing: int = 3) -> Label:
	var out: Label = label(text.to_upper(), size, color)
	out.add_theme_font_override(&"font", caps_font(true, spacing))
	out.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	out.add_theme_constant_override(&"shadow_offset_y", 2)
	out.add_theme_constant_override(&"shadow_outline_size", 4)
	return out


## Small wide capitals, dim, over a group of fields.
static func heading(text: String) -> Label:
	var out: Label = label(text.to_upper(), 13, DIM)
	out.add_theme_font_override(&"font", caps_font(true, 2))
	return out


## A gilt rule with a stud at its middle, to part a title from what follows.
static func rule(width: float = 0.0) -> OrnateRule:
	var out: OrnateRule = OrnateRule.new()
	if width > 0.0:
		out.custom_minimum_size.x = width
		out.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return out


## Darkens the edges of the screen.
static func vignette(parent: Control, strength: float = 0.75) -> TextureRect:
	var shade: TextureRect = TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, strength))
	gradient.add_point(0.55, Color(0.0, 0.0, 0.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 1.05)
	texture.width = 256
	texture.height = 256
	shade.texture = texture
	parent.add_child(shade)
	return shade


## Sparks drifting up from somewhere below the screen.
static func embers(parent: Control) -> CPUParticles2D:
	var sparks: CPUParticles2D = CPUParticles2D.new()
	sparks.amount = 60
	sparks.lifetime = 9.0
	sparks.preprocess = 9.0
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.direction = Vector2(0.15, -1.0)
	sparks.spread = 18.0
	sparks.gravity = Vector2(0.0, -6.0)
	sparks.initial_velocity_min = 18.0
	sparks.initial_velocity_max = 46.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 2.6
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1.0, 0.6, 0.25, 0.0))
	fade.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	fade.add_point(0.15, Color(1.0, 0.72, 0.36, 0.85))
	fade.add_point(0.7, Color(1.0, 0.45, 0.15, 0.4))
	sparks.color_ramp = fade
	parent.add_child(sparks)
	var place: Callable = func() -> void:
		var area: Vector2 = parent.get_viewport_rect().size
		sparks.position = Vector2(area.x * 0.5, area.y + 10.0)
		sparks.emission_rect_extents = Vector2(area.x * 0.55, 6.0)
	place.call()
	parent.resized.connect(place)
	return sparks


## The map of Ortel, darkened, filling the screen behind a menu.
static func backdrop(parent: Control) -> TextureRect:
	var back: ColorRect = ColorRect.new()
	back.color = BACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(back)
	var map: TextureRect = TextureRect.new()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map.modulate = Color(0.42, 0.38, 0.32)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MAP_TEXTURE):
		map.texture = load(MAP_TEXTURE) as Texture2D
	parent.add_child(map)
	var shade: TextureRect = TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(BACK, 0.95))
	gradient.set_color(1, Color(BACK, 0.2))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	shade.texture = texture
	parent.add_child(shade)
	return map
