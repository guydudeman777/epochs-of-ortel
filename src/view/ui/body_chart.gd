class_name BodyChart
extends Control
## A body drawn as a barber-surgeon's chart, front on, each part shaded by how badly it is hurt and struck through
## where it is lost. The person's left is on the chart's right, as when facing them.

## Part -> its shape in a 1 by 2 box, as a centre, a half size and a turn in radians (a capsule), or a circle.
const SHAPES: Dictionary[StringName, Array] = {
	&"head": [Vector2(0.5, 0.11), Vector2(0.085, 0.085), 0.0],
	&"neck": [Vector2(0.5, 0.215), Vector2(0.04, 0.035), 0.0],
	&"torso": [Vector2(0.5, 0.36), Vector2(0.16, 0.11), 0.0],
	&"abdomen": [Vector2(0.5, 0.56), Vector2(0.13, 0.09), 0.0],
	&"arm_r": [Vector2(0.27, 0.36), Vector2(0.045, 0.11), 0.2],
	&"arm_l": [Vector2(0.73, 0.36), Vector2(0.045, 0.11), -0.2],
	&"forearm_r": [Vector2(0.21, 0.56), Vector2(0.04, 0.1), 0.12],
	&"forearm_l": [Vector2(0.79, 0.56), Vector2(0.04, 0.1), -0.12],
	&"hand_r": [Vector2(0.18, 0.71), Vector2(0.035, 0.045), 0.1],
	&"hand_l": [Vector2(0.82, 0.71), Vector2(0.035, 0.045), -0.1],
	&"thigh_r": [Vector2(0.42, 0.78), Vector2(0.06, 0.13), 0.04],
	&"thigh_l": [Vector2(0.58, 0.78), Vector2(0.06, 0.13), -0.04],
	&"shin_r": [Vector2(0.41, 1.06), Vector2(0.045, 0.13), 0.0],
	&"shin_l": [Vector2(0.59, 1.06), Vector2(0.045, 0.13), 0.0],
	&"foot_r": [Vector2(0.39, 1.24), Vector2(0.05, 0.03), 0.0],
	&"foot_l": [Vector2(0.61, 1.24), Vector2(0.05, 0.03), 0.0],
}
const TALL: float = 1.3

## Part -> SimEnums.WoundLevel.
var levels: Dictionary[StringName, int] = {}
var bleeding: Dictionary[StringName, bool] = {}


static func of(ctx: SimContext, c: CharacterData) -> BodyChart:
	var out: BodyChart = BodyChart.new()
	for part: StringName in SHAPES:
		if ctx.defs.body_parts.has(part):
			out.levels[part] = LimbService.part_level(ctx, c, part)
	for part: StringName in c.body.lost_parts:
		out.levels[part] = SimEnums.WoundLevel.LOST
	for w: WoundData in c.body.wounds:
		if w.bleed > 0.0:
			out.bleeding[w.part_id] = true
	out.custom_minimum_size = Vector2(150.0, 200.0)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


func _draw() -> void:
	var scale_by: float = minf(size.x, size.y / TALL)
	var origin: Vector2 = Vector2((size.x - scale_by) * 0.5, (size.y - scale_by * TALL) * 0.5)
	for part: StringName in SHAPES:
		var spec: Array = SHAPES[part]
		var level: int = levels.get(part, 0)
		var colour: Color = PanelStyle.WOUND_COLORS[clampi(level, 0, PanelStyle.WOUND_COLORS.size() - 1)]
		var centre: Vector2 = origin + (spec[0] as Vector2) * scale_by
		var half: Vector2 = (spec[1] as Vector2) * scale_by
		var turn: float = spec[2] as float
		var outline: PackedVector2Array = _capsule(centre, half, turn)
		if level == SimEnums.WoundLevel.LOST:
			var closed_lost: PackedVector2Array = outline.duplicate()
			closed_lost.append(outline[0])
			draw_polyline(closed_lost, Color(0.55, 0.12, 0.08, 0.8), 1.5, true)
			draw_line(centre - half, centre + half, Color(0.7, 0.15, 0.1), 2.0)
			draw_line(centre + Vector2(-half.x, half.y), centre + Vector2(half.x, -half.y), Color(0.7, 0.15, 0.1), 2.0)
			continue
		draw_colored_polygon(outline, colour)
		var closed: PackedVector2Array = outline.duplicate()
		closed.append(outline[0])
		draw_polyline(closed, Color(0.08, 0.06, 0.05), 1.5, true)
		if bleeding.get(part, false):
			draw_circle(centre + Vector2(half.x * 0.3, half.y * 0.2), maxf(scale_by * 0.018, 2.5), Color(0.75, 0.05, 0.03))


func _capsule(centre: Vector2, half: Vector2, turn: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var radius: float = minf(half.x, half.y)
	var reach: Vector2 = Vector2(maxf(half.x - radius, 0.0), maxf(half.y - radius, 0.0))
	var basis: Transform2D = Transform2D(turn, Vector2.ZERO)
	# Two half circles joined: one at each end of the long axis.
	var upright: bool = half.y >= half.x
	for end: int in range(2):
		var sign: float = -1.0 if end == 0 else 1.0
		var middle: Vector2 = Vector2(0.0, reach.y * sign) if upright else Vector2(reach.x * sign, 0.0)
		var start: float = (PI if end == 0 else 0.0) if upright else (PI * 0.5 if end == 0 else -PI * 0.5)
		for i: int in range(9):
			var a: float = start + PI * float(i) / 8.0
			var p: Vector2 = middle + Vector2(cos(a), sin(a)) * radius
			out.append(centre + basis * p)
	return out
