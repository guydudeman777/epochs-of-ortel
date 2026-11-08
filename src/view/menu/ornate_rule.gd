class_name OrnateRule
extends Control
## A gilt line that fades out at both ends, with a stud at its middle and a smaller one either side.

@export var color: Color = Color(0.66, 0.54, 0.33)


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 14.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var mid: Vector2 = Vector2(size.x * 0.5, size.y * 0.5)
	var steps: int = 24
	for i: int in range(steps):
		var a: float = float(i) / float(steps)
		var b: float = float(i + 1) / float(steps)
		# Brightest at the middle, gone at the ends.
		var fade: float = 1.0 - absf((a + b) - 1.0)
		draw_line(Vector2(size.x * a, mid.y), Vector2(size.x * b, mid.y), Color(color, fade * 0.85), 1.0, true)
	_stud(mid, 5.0, Color(1.0, 0.93, 0.74))
	for side: float in [-1.0, 1.0]:
		_stud(mid + Vector2(side * 16.0, 0.0), 2.5, color)


func _stud(at: Vector2, r: float, fill: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([at + Vector2(0.0, -r - 1.0), at + Vector2(r + 1.0, 0.0), at + Vector2(0.0, r + 1.0), at + Vector2(-r - 1.0, 0.0)])
	draw_colored_polygon(points, Color(0.03, 0.025, 0.02))
	points = PackedVector2Array([at + Vector2(0.0, -r), at + Vector2(r, 0.0), at + Vector2(0.0, r), at + Vector2(-r, 0.0)])
	draw_colored_polygon(points, fill)
