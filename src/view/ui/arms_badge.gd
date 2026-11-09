class_name ArmsBadge
extends Control
## A realm's arms on a heater shield, drawn from Heraldry so they match the surcoats, shields and banners of the
## realm. No realm draws a plain grey shield.

var field: Color = Heraldry.NONE_FIELD
var metal: Color = Heraldry.METALS[1]
var charge: Heraldry.Charge = Heraldry.Charge.PALE
var plain: bool = true


static func make(f: FactionData, side: float = 48.0) -> ArmsBadge:
	var out: ArmsBadge = ArmsBadge.new()
	out.show_realm(f)
	out.custom_minimum_size = Vector2(side, side * 1.15)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


func show_realm(f: FactionData) -> void:
	field = Heraldry.field(f)
	metal = Heraldry.charge_color(f)
	charge = Heraldry.charge(f)
	plain = f == null
	queue_redraw()


func _draw() -> void:
	var w: float = minf(size.x, size.y / 1.15)
	var origin: Vector2 = Vector2((size.x - w) * 0.5, (size.y - w * 1.15) * 0.5)
	var outline: PackedVector2Array = _shield(origin, w)
	var shadow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in outline:
		shadow.append(point + Vector2(w * 0.03, w * 0.05))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.5))
	draw_colored_polygon(outline, field)
	if not plain:
		for shape: PackedVector2Array in _charge(origin, w):
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(shape, outline):
				draw_colored_polygon(clipped, metal)
	# Light from the upper left, a darker foot, and an iron rim.
	var shine: PackedVector2Array = PackedVector2Array([origin + Vector2(0.14, 0.08) * w, origin + Vector2(0.5, 0.08) * w,
			origin + Vector2(0.5, 0.5) * w, origin + Vector2(0.14, 0.42) * w])
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(shine, outline):
		draw_colored_polygon(clipped, Color(1.0, 0.95, 0.85, 0.08))
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color(0.12, 0.1, 0.08), maxf(w * 0.05, 1.5), true)
	draw_polyline(closed, Color(0.62, 0.5, 0.3, 0.8), maxf(w * 0.015, 1.0), true)


func _shield(origin: Vector2, w: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var top: float = 0.06
	var waist: float = 0.5
	var foot: float = 1.1
	out.append(origin + Vector2(0.08, top) * w)
	out.append(origin + Vector2(0.92, top) * w)
	for i: int in range(1, 13):
		var t: float = float(i) / 12.0
		out.append(origin + Vector2(0.92 - 0.42 * (1.0 - cos(t * PI * 0.5)), waist + (foot - waist) * sin(t * PI * 0.5)) * w)
	for i: int in range(11, -1, -1):
		var t: float = float(i) / 12.0
		out.append(origin + Vector2(0.08 + 0.42 * (1.0 - cos(t * PI * 0.5)), waist + (foot - waist) * sin(t * PI * 0.5)) * w)
	return out


func _charge(origin: Vector2, w: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var c: Vector2 = Vector2(0.5, 0.48)
	var band: float = 0.17
	match charge:
		Heraldry.Charge.CROSS:
			out.append(_rect(origin, w, Vector2(c.x - band * 0.5, -0.1), Vector2(c.x + band * 0.5, 1.2)))
			out.append(_rect(origin, w, Vector2(-0.1, c.y - 0.08 - band * 0.5), Vector2(1.1, c.y - 0.08 + band * 0.5)))
		Heraldry.Charge.SALTIRE:
			out.append(_bar(origin, w, Vector2(0.0, 0.0), Vector2(1.0, 1.15), band))
			out.append(_bar(origin, w, Vector2(1.0, 0.0), Vector2(0.0, 1.15), band))
		Heraldry.Charge.CHEVRON:
			out.append(PackedVector2Array([origin + Vector2(-0.1, 0.95) * w, origin + Vector2(c.x, 0.36) * w, origin + Vector2(1.1, 0.95) * w,
					origin + Vector2(1.1, 0.95 + band * 1.3) * w, origin + Vector2(c.x, 0.36 + band * 1.3) * w, origin + Vector2(-0.1, 0.95 + band * 1.3) * w]))
		Heraldry.Charge.PALE:
			out.append(_rect(origin, w, Vector2(0.35, -0.1), Vector2(0.65, 1.2)))
		Heraldry.Charge.FESS:
			out.append(_rect(origin, w, Vector2(-0.1, 0.33), Vector2(1.1, 0.6)))
		Heraldry.Charge.BEND:
			out.append(_bar(origin, w, Vector2(0.0, 0.0), Vector2(1.0, 1.15), band * 1.4))
		Heraldry.Charge.QUARTERLY:
			out.append(_rect(origin, w, Vector2(c.x, -0.1), Vector2(1.1, c.y)))
			out.append(_rect(origin, w, Vector2(-0.1, c.y), Vector2(c.x, 1.2)))
		_:
			var ring: PackedVector2Array = PackedVector2Array()
			for i: int in range(24):
				var a: float = TAU * float(i) / 24.0
				ring.append(origin + (c + Vector2(cos(a), sin(a)) * 0.2) * w)
			out.append(ring)
	return out


func _rect(origin: Vector2, w: float, a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([origin + a * w, origin + Vector2(b.x, a.y) * w, origin + b * w, origin + Vector2(a.x, b.y) * w])


func _bar(origin: Vector2, w: float, a: Vector2, b: Vector2, thick: float) -> PackedVector2Array:
	var along: Vector2 = (b - a).normalized()
	var across: Vector2 = Vector2(-along.y, along.x) * thick * 0.5
	return PackedVector2Array([origin + (a + across) * w, origin + (b + across) * w, origin + (b - across) * w, origin + (a - across) * w])
