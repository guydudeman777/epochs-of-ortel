class_name RankBadge
extends Control
## A soldier's rank: a small iron shield with the tier in numerals, gilt the higher it is.

const NUMERALS: Array[String] = ["", "I", "II", "III", "IV", "V", "VI"]
const FILLS: Array[Color] = [Color(0.25, 0.22, 0.2), Color(0.3, 0.27, 0.24), Color(0.38, 0.3, 0.2), Color(0.42, 0.3, 0.14), Color(0.5, 0.36, 0.12),
		Color(0.62, 0.44, 0.12), Color(0.7, 0.5, 0.14)]

var tier: int = 1


static func make(rank: int, side: float = 30.0) -> RankBadge:
	var out: RankBadge = RankBadge.new()
	out.tier = rank
	out.custom_minimum_size = Vector2(side, side * 1.15)
	out.mouse_filter = Control.MOUSE_FILTER_PASS
	out.tooltip_text = "Rank %d" % rank
	return out


func _draw() -> void:
	var w: float = minf(size.x, size.y / 1.15)
	var origin: Vector2 = Vector2((size.x - w) * 0.5, (size.y - w * 1.15) * 0.5)
	var outline: PackedVector2Array = Glyph.heater(origin, w, 0.06, 0.04, 0.88, 1.06)
	var t: int = clampi(tier, 0, FILLS.size() - 1)
	draw_colored_polygon(outline, FILLS[t])
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, PanelStyle.GOLD if tier >= 4 else Color(0.62, 0.55, 0.42), maxf(w * 0.06, 1.5), true)
	var text: String = NUMERALS[clampi(tier, 0, NUMERALS.size() - 1)]
	var font: Font = MenuStyle.caps_font(true, 0)
	var font_size: int = int(w * (0.5 if text.length() < 3 else 0.38))
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at: Vector2 = origin + Vector2((w - width) * 0.5, w * 0.62)
	draw_string(font, at + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.0, 0.0, 0.0, 0.7))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, MenuStyle.BRIGHT)
