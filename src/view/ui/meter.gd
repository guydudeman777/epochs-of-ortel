class_name Meter
extends Control
## A bar in an iron channel, filled to a share, with words over it: blood, experience, supplies, strength.

var share: float = 0.0
var fill: Color = PanelStyle.XP_BAR
var words: String = ""
## A mark at another share, as where an upgrade falls.
var mark: float = -1.0


static func make(value: float, color: Color, label: String = "", width: float = 0.0, height: float = 18.0) -> Meter:
	var out: Meter = Meter.new()
	out.share = clampf(value, 0.0, 1.0)
	out.fill = color
	out.words = label
	out.custom_minimum_size = Vector2(width, height)
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_SHRINK_BEGIN
	out.mouse_filter = Control.MOUSE_FILTER_PASS
	return out


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.03, 0.025, 0.02, 0.95))
	var inner: Rect2 = rect.grow(-2.0)
	if share > 0.0:
		var filled: Rect2 = Rect2(inner.position, Vector2(inner.size.x * share, inner.size.y))
		draw_rect(filled, fill.darkened(0.25))
		draw_rect(Rect2(filled.position, Vector2(filled.size.x, filled.size.y * 0.45)), fill.lightened(0.1))
		draw_rect(Rect2(filled.position + Vector2(0.0, filled.size.y - 2.0), Vector2(filled.size.x, 2.0)), fill.darkened(0.5))
	if mark >= 0.0 and mark <= 1.0:
		var x: float = inner.position.x + inner.size.x * mark
		draw_line(Vector2(x, 1.0), Vector2(x, size.y - 1.0), PanelStyle.GOLD, 2.0)
	draw_rect(rect, Color(0.36, 0.3, 0.2), false, 1.0)
	if not words.is_empty():
		var font: Font = MenuStyle.font(true)
		var font_size: int = clampi(int(size.y * 0.72), 10, 16)
		var width: float = font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var at: Vector2 = Vector2((size.x - width) * 0.5, size.y * 0.5 + font_size * 0.36)
		draw_string_outline(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 3, Color(0.0, 0.0, 0.0, 0.85))
		draw_string(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, MenuStyle.BRIGHT)
