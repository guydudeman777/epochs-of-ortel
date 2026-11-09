class_name Glyph
extends Control
## A small drawn sign, like those stamped on a ledger or burnt into a tally stick: a coin, a sword, a crown. Drawn in
## lines and shapes at whatever size it is given, so it stays sharp. kind names the sign; color is its ink.

const KINDS: Array[StringName] = [
	&"coin", &"sword", &"shield", &"crown", &"scroll", &"book", &"quill", &"skull", &"heart", &"drop", &"foot", &"hand", &"eye",
	&"tower", &"castle", &"house", &"wheat", &"fish", &"tree", &"pick", &"anvil", &"hammer", &"chest", &"bag", &"banner",
	&"people", &"tree_family", &"helm", &"star", &"flame", &"chain", &"sail", &"weight", &"plus", &"cross", &"arrow_up", &"hourglass",
	&"wheel", &"salt", &"grapes", &"sheep", &"horse", &"stone", &"seal", &"spear", &"bow",
]

@export var kind: StringName = &"coin"
@export var color: Color = Color(0.93, 0.84, 0.62)
## A darker edge drawn under the sign, so it reads on any ground.
@export var shadow: bool = true


static func make(sign_kind: StringName, size: float = 20.0, ink: Color = Color(0.93, 0.84, 0.62)) -> Glyph:
	var out: Glyph = Glyph.new()
	out.kind = sign_kind
	out.color = ink
	out.custom_minimum_size = Vector2(size, size)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var origin: Vector2 = (size - Vector2(side, side)) * 0.5
	if shadow:
		_sign(origin + Vector2(0.0, side * 0.05), side, Color(0.0, 0.0, 0.0, 0.55))
	_sign(origin, side, color)


var _origin: Vector2 = Vector2.ZERO
var _side: float = 1.0


## A point in a 0..1 square, on the control.
func _p(x: float, y: float) -> Vector2:
	return _origin + Vector2(x, y) * _side


func _sign(origin: Vector2, side: float, ink: Color) -> void:
	_origin = origin
	_side = side
	var w: float = maxf(side * 0.08, 1.2)
	match kind:
		&"coin":
			draw_circle(_p(0.5, 0.5), side * 0.4, ink)
			draw_circle(_p(0.5, 0.5), side * 0.3, ink.darkened(0.35))
			draw_rect(Rect2(_p(0.45, 0.32), Vector2(side * 0.1, side * 0.36)), ink)
		&"sword":
			draw_line(_p(0.2, 0.8), _p(0.82, 0.18), ink, w * 1.2)
			draw_line(_p(0.12, 0.6), _p(0.4, 0.88), ink, w)
			draw_line(_p(0.12, 0.88), _p(0.22, 0.78), ink, w * 1.4)
		&"spear":
			draw_line(_p(0.15, 0.85), _p(0.72, 0.28), ink, w * 0.9)
			draw_colored_polygon(PackedVector2Array([_p(0.88, 0.12), _p(0.62, 0.26), _p(0.74, 0.38)]), ink)
		&"bow":
			draw_arc(_p(0.25, 0.5), side * 0.42, -1.25, 1.25, 16, ink, w)
			draw_line(_p(0.37, 0.12), _p(0.37, 0.88), ink, maxf(w * 0.4, 1.0))
		&"shield":
			draw_colored_polygon(heater(origin, side, 0.18, 0.12, 0.64, 0.8), ink)
			draw_colored_polygon(heater(origin, side, 0.26, 0.2, 0.48, 0.66), ink.darkened(0.35))
		&"crown":
			draw_colored_polygon(PackedVector2Array([_p(0.12, 0.78), _p(0.12, 0.32), _p(0.3, 0.55), _p(0.5, 0.22), _p(0.7, 0.55),
					_p(0.88, 0.32), _p(0.88, 0.78)]), ink)
			draw_rect(Rect2(_p(0.12, 0.8), Vector2(side * 0.76, side * 0.08)), ink)
		&"helm":
			draw_colored_polygon(PackedVector2Array([_p(0.2, 0.85), _p(0.2, 0.42), _p(0.35, 0.18), _p(0.65, 0.18), _p(0.8, 0.42),
					_p(0.8, 0.85)]), ink)
			draw_rect(Rect2(_p(0.28, 0.48), Vector2(side * 0.44, side * 0.07)), ink.darkened(0.6))
			draw_rect(Rect2(_p(0.47, 0.48), Vector2(side * 0.06, side * 0.3)), ink.darkened(0.6))
		&"scroll":
			draw_rect(Rect2(_p(0.22, 0.2), Vector2(side * 0.56, side * 0.6)), ink)
			draw_circle(_p(0.22, 0.22), side * 0.08, ink.darkened(0.25))
			draw_circle(_p(0.78, 0.78), side * 0.08, ink.darkened(0.25))
			for i: int in range(3):
				draw_line(_p(0.32, 0.36 + i * 0.13), _p(0.68, 0.36 + i * 0.13), ink.darkened(0.55), maxf(w * 0.5, 1.0))
		&"seal":
			draw_circle(_p(0.5, 0.45), side * 0.3, ink)
			draw_colored_polygon(PackedVector2Array([_p(0.35, 0.65), _p(0.3, 0.92), _p(0.42, 0.82), _p(0.5, 0.95), _p(0.5, 0.7)]), ink.darkened(0.2))
			draw_circle(_p(0.5, 0.45), side * 0.18, ink.darkened(0.3))
		&"book":
			draw_colored_polygon(PackedVector2Array([_p(0.08, 0.25), _p(0.48, 0.32), _p(0.48, 0.85), _p(0.08, 0.78)]), ink)
			draw_colored_polygon(PackedVector2Array([_p(0.92, 0.25), _p(0.52, 0.32), _p(0.52, 0.85), _p(0.92, 0.78)]), ink)
		&"quill":
			draw_colored_polygon(PackedVector2Array([_p(0.85, 0.1), _p(0.55, 0.3), _p(0.3, 0.62), _p(0.38, 0.66), _p(0.66, 0.4)]), ink)
			draw_line(_p(0.34, 0.64), _p(0.15, 0.9), ink, w * 0.7)
		&"hourglass":
			draw_colored_polygon(PackedVector2Array([_p(0.25, 0.15), _p(0.75, 0.15), _p(0.52, 0.5), _p(0.75, 0.85), _p(0.25, 0.85),
					_p(0.48, 0.5)]), ink)
			draw_rect(Rect2(_p(0.18, 0.1), Vector2(side * 0.64, side * 0.07)), ink)
			draw_rect(Rect2(_p(0.18, 0.83), Vector2(side * 0.64, side * 0.07)), ink)
		&"skull":
			draw_circle(_p(0.5, 0.42), side * 0.3, ink)
			draw_rect(Rect2(_p(0.34, 0.6), Vector2(side * 0.32, side * 0.22)), ink)
			draw_circle(_p(0.39, 0.44), side * 0.08, ink.darkened(0.8))
			draw_circle(_p(0.61, 0.44), side * 0.08, ink.darkened(0.8))
		&"heart":
			draw_circle(_p(0.35, 0.38), side * 0.18, ink)
			draw_circle(_p(0.65, 0.38), side * 0.18, ink)
			draw_colored_polygon(PackedVector2Array([_p(0.18, 0.45), _p(0.82, 0.45), _p(0.5, 0.86)]), ink)
		&"drop":
			draw_circle(_p(0.5, 0.62), side * 0.24, ink)
			draw_colored_polygon(PackedVector2Array([_p(0.27, 0.56), _p(0.5, 0.12), _p(0.73, 0.56)]), ink)
		&"foot":
			draw_colored_polygon(PackedVector2Array([_p(0.35, 0.12), _p(0.6, 0.12), _p(0.62, 0.6), _p(0.85, 0.75), _p(0.85, 0.88),
					_p(0.3, 0.88)]), ink)
		&"hand":
			draw_rect(Rect2(_p(0.28, 0.45), Vector2(side * 0.44, side * 0.42)), ink)
			for i: int in range(4):
				draw_rect(Rect2(_p(0.28 + i * 0.115, 0.15 + absf(i - 1.5) * 0.06), Vector2(side * 0.09, side * 0.35)), ink)
			draw_line(_p(0.3, 0.6), _p(0.12, 0.4), ink, w * 1.2)
		&"eye":
			draw_colored_polygon(PackedVector2Array([_p(0.08, 0.5), _p(0.3, 0.3), _p(0.7, 0.3), _p(0.92, 0.5), _p(0.7, 0.7),
					_p(0.3, 0.7)]), ink)
			draw_circle(_p(0.5, 0.5), side * 0.14, ink.darkened(0.8))
		&"tower":
			draw_rect(Rect2(_p(0.3, 0.3), Vector2(side * 0.4, side * 0.6)), ink)
			for i: int in range(3):
				draw_rect(Rect2(_p(0.27 + i * 0.17, 0.14), Vector2(side * 0.12, side * 0.18)), ink)
			draw_rect(Rect2(_p(0.44, 0.66), Vector2(side * 0.12, side * 0.24)), ink.darkened(0.7))
		&"castle":
			draw_rect(Rect2(_p(0.1, 0.42), Vector2(side * 0.8, side * 0.48)), ink)
			for x: float in [0.1, 0.38, 0.66]:
				draw_rect(Rect2(_p(x, 0.2), Vector2(side * 0.24, side * 0.26)), ink)
				draw_rect(Rect2(_p(x + 0.02, 0.12), Vector2(side * 0.06, side * 0.1)), ink)
				draw_rect(Rect2(_p(x + 0.16, 0.12), Vector2(side * 0.06, side * 0.1)), ink)
			draw_rect(Rect2(_p(0.42, 0.62), Vector2(side * 0.16, side * 0.28)), ink.darkened(0.7))
		&"house":
			draw_colored_polygon(PackedVector2Array([_p(0.1, 0.5), _p(0.5, 0.15), _p(0.9, 0.5)]), ink)
			draw_rect(Rect2(_p(0.2, 0.5), Vector2(side * 0.6, side * 0.38)), ink)
			draw_rect(Rect2(_p(0.44, 0.64), Vector2(side * 0.13, side * 0.24)), ink.darkened(0.7))
		&"wheat":
			draw_line(_p(0.5, 0.9), _p(0.5, 0.15), ink, w * 0.6)
			for i: int in range(4):
				var y: float = 0.22 + i * 0.14
				draw_colored_polygon(_leaf(_p(0.5, y + 0.06), _p(0.3, y), side * 0.07), ink)
				draw_colored_polygon(_leaf(_p(0.5, y + 0.06), _p(0.7, y), side * 0.07), ink)
		&"fish":
			draw_colored_polygon(PackedVector2Array([_p(0.1, 0.5), _p(0.35, 0.3), _p(0.65, 0.32), _p(0.78, 0.5), _p(0.65, 0.68),
					_p(0.35, 0.7)]), ink)
			draw_colored_polygon(PackedVector2Array([_p(0.74, 0.5), _p(0.94, 0.3), _p(0.94, 0.7)]), ink)
			draw_circle(_p(0.28, 0.46), side * 0.04, ink.darkened(0.8))
		&"tree":
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.08), _p(0.82, 0.55), _p(0.62, 0.55), _p(0.86, 0.78), _p(0.14, 0.78),
					_p(0.38, 0.55), _p(0.18, 0.55)]), ink)
			draw_rect(Rect2(_p(0.45, 0.78), Vector2(side * 0.1, side * 0.15)), ink)
		&"tree_family":
			draw_line(_p(0.5, 0.88), _p(0.5, 0.45), ink, w)
			draw_line(_p(0.5, 0.55), _p(0.25, 0.3), ink, w * 0.8)
			draw_line(_p(0.5, 0.55), _p(0.75, 0.3), ink, w * 0.8)
			for c: Vector2 in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.5, 0.18)]:
				draw_circle(_p(c.x, c.y), side * 0.12, ink)
		&"pick":
			draw_line(_p(0.25, 0.88), _p(0.62, 0.3), ink, w)
			draw_arc(_p(0.62, 0.62), side * 0.42, -2.6, -0.6, 12, ink, w * 1.2)
		&"anvil":
			draw_colored_polygon(PackedVector2Array([_p(0.08, 0.35), _p(0.82, 0.35), _p(0.92, 0.45), _p(0.66, 0.52), _p(0.66, 0.68),
					_p(0.78, 0.82), _p(0.22, 0.82), _p(0.34, 0.68), _p(0.34, 0.52), _p(0.18, 0.48)]), ink)
		&"hammer":
			draw_line(_p(0.25, 0.88), _p(0.6, 0.38), ink, w)
			draw_colored_polygon(PackedVector2Array([_p(0.42, 0.22), _p(0.66, 0.08), _p(0.88, 0.38), _p(0.64, 0.52)]), ink)
		&"chest":
			draw_rect(Rect2(_p(0.12, 0.42), Vector2(side * 0.76, side * 0.42)), ink)
			draw_colored_polygon(PackedVector2Array([_p(0.12, 0.42), _p(0.16, 0.24), _p(0.84, 0.24), _p(0.88, 0.42)]), ink.lightened(0.15))
			draw_rect(Rect2(_p(0.44, 0.4), Vector2(side * 0.12, side * 0.16)), ink.darkened(0.6))
		&"bag":
			draw_circle(_p(0.5, 0.62), side * 0.3, ink)
			draw_colored_polygon(PackedVector2Array([_p(0.36, 0.38), _p(0.3, 0.16), _p(0.5, 0.26), _p(0.7, 0.16), _p(0.64, 0.38)]), ink)
			draw_line(_p(0.34, 0.36), _p(0.66, 0.36), ink.darkened(0.6), maxf(w * 0.6, 1.0))
		&"banner":
			draw_line(_p(0.2, 0.92), _p(0.2, 0.08), ink, w * 0.7)
			draw_colored_polygon(PackedVector2Array([_p(0.22, 0.12), _p(0.85, 0.12), _p(0.85, 0.55), _p(0.62, 0.45), _p(0.4, 0.55),
					_p(0.22, 0.48)]), ink)
		&"people":
			for c: Vector3 in [Vector3(0.3, 0.38, 0.13), Vector3(0.7, 0.38, 0.13), Vector3(0.5, 0.3, 0.15)]:
				draw_circle(_p(c.x, c.y), side * c.z, ink)
				draw_colored_polygon(PackedVector2Array([_p(c.x - c.z * 1.6, 0.9), _p(c.x - c.z * 1.2, c.y + c.z * 1.4),
						_p(c.x + c.z * 1.2, c.y + c.z * 1.4), _p(c.x + c.z * 1.6, 0.9)]), ink)
		&"star":
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in range(10):
				var r: float = 0.42 if i % 2 == 0 else 0.18
				var a: float = -PI * 0.5 + TAU * float(i) / 10.0
				pts.append(_p(0.5 + cos(a) * r, 0.52 + sin(a) * r))
			draw_colored_polygon(pts, ink)
		&"flame":
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.08), _p(0.72, 0.42), _p(0.78, 0.68), _p(0.62, 0.9), _p(0.38, 0.9),
					_p(0.22, 0.68), _p(0.3, 0.45), _p(0.4, 0.55)]), ink)
		&"chain":
			draw_arc(_p(0.33, 0.5), side * 0.17, 0.0, TAU, 14, ink, w)
			draw_arc(_p(0.67, 0.5), side * 0.17, 0.0, TAU, 14, ink, w)
		&"sail":
			draw_line(_p(0.45, 0.08), _p(0.45, 0.78), ink, w * 0.6)
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.1), _p(0.82, 0.65), _p(0.5, 0.65)]), ink)
			draw_colored_polygon(PackedVector2Array([_p(0.1, 0.75), _p(0.9, 0.75), _p(0.75, 0.9), _p(0.25, 0.9)]), ink)
		&"weight":
			draw_colored_polygon(PackedVector2Array([_p(0.3, 0.3), _p(0.7, 0.3), _p(0.88, 0.88), _p(0.12, 0.88)]), ink)
			draw_arc(_p(0.5, 0.24), side * 0.12, PI, TAU, 10, ink, w * 0.8)
		&"plus":
			draw_rect(Rect2(_p(0.42, 0.15), Vector2(side * 0.16, side * 0.7)), ink)
			draw_rect(Rect2(_p(0.15, 0.42), Vector2(side * 0.7, side * 0.16)), ink)
		&"cross":
			draw_line(_p(0.2, 0.2), _p(0.8, 0.8), ink, w * 1.4)
			draw_line(_p(0.8, 0.2), _p(0.2, 0.8), ink, w * 1.4)
		&"arrow_up":
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.1), _p(0.88, 0.5), _p(0.64, 0.5), _p(0.64, 0.9), _p(0.36, 0.9),
					_p(0.36, 0.5), _p(0.12, 0.5)]), ink)
		&"wheel":
			draw_arc(_p(0.5, 0.5), side * 0.36, 0.0, TAU, 20, ink, w)
			for i: int in range(4):
				var a: float = PI * 0.25 * float(i)
				draw_line(_p(0.5 + cos(a) * 0.36, 0.5 + sin(a) * 0.36), _p(0.5 - cos(a) * 0.36, 0.5 - sin(a) * 0.36), ink, w * 0.6)
		&"salt":
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.15), _p(0.88, 0.85), _p(0.12, 0.85)]), ink)
		&"grapes":
			for c: Vector2 in [Vector2(0.38, 0.35), Vector2(0.62, 0.35), Vector2(0.5, 0.52), Vector2(0.3, 0.52), Vector2(0.7, 0.52), Vector2(0.42, 0.68),
					Vector2(0.58, 0.68), Vector2(0.5, 0.84)]:
				draw_circle(_p(c.x, c.y), side * 0.1, ink)
			draw_line(_p(0.5, 0.25), _p(0.6, 0.08), ink, w * 0.6)
		&"sheep":
			draw_circle(_p(0.45, 0.5), side * 0.28, ink)
			draw_circle(_p(0.78, 0.45), side * 0.12, ink.darkened(0.4))
			draw_rect(Rect2(_p(0.3, 0.72), Vector2(side * 0.06, side * 0.18)), ink)
			draw_rect(Rect2(_p(0.56, 0.72), Vector2(side * 0.06, side * 0.18)), ink)
		&"horse":
			draw_colored_polygon(PackedVector2Array([_p(0.15, 0.55), _p(0.6, 0.5), _p(0.72, 0.18), _p(0.9, 0.3), _p(0.78, 0.42),
					_p(0.75, 0.62), _p(0.7, 0.9), _p(0.62, 0.9), _p(0.6, 0.7), _p(0.3, 0.7), _p(0.26, 0.9), _p(0.18, 0.9)]), ink)
		&"stone":
			draw_colored_polygon(PackedVector2Array([_p(0.1, 0.8), _p(0.2, 0.45), _p(0.45, 0.3), _p(0.75, 0.38), _p(0.9, 0.8)]), ink)
			draw_line(_p(0.3, 0.55), _p(0.55, 0.6), ink.darkened(0.5), maxf(w * 0.5, 1.0))
		_:
			draw_circle(_p(0.5, 0.5), side * 0.3, ink)


## A heater shield's outline in a square, from its top left and size as shares of the side.
static func heater(origin: Vector2, side: float, x: float, y: float, w: float, h: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.append(origin + Vector2(x, y) * side)
	out.append(origin + Vector2(x + w, y) * side)
	for i: int in range(9):
		var t: float = float(i) / 8.0
		var bx: float = x + w - w * 0.5 * (1.0 - cos(t * PI * 0.5))
		var by: float = y + h * 0.45 + h * 0.55 * sin(t * PI * 0.5)
		out.append(origin + Vector2(bx, by) * side)
	# The point at the foot is already in, from the right side.
	for i: int in range(7, -1, -1):
		var t: float = float(i) / 8.0
		var bx: float = x + w * 0.5 * (1.0 - cos(t * PI * 0.5))
		var by: float = y + h * 0.45 + h * 0.55 * sin(t * PI * 0.5)
		out.append(origin + Vector2(bx, by) * side)
	return out


static func _leaf(root: Vector2, tip: Vector2, half: float) -> PackedVector2Array:
	var along: Vector2 = (tip - root).normalized()
	var across: Vector2 = Vector2(-along.y, along.x) * half
	var middle: Vector2 = (root + tip) * 0.5
	return PackedVector2Array([root, middle + across, tip, middle - across])
