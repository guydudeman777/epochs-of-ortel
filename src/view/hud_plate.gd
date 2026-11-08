class_name HudPlate
extends PanelContainer
## Text on a smoked plate, pinned to a corner of the screen. The plate fits what it says and hides when it says nothing.
##
## pin() takes the corner the plate hangs from: anchor x 0 puts its left edge at at.x, 1 its right edge, 0.5 its middle,
## and the same for y. A width of 0 fits the text; otherwise the text wraps at that width.

var label: RichTextLabel
var text: String = "":
	set(value):
		if value == text:
			return
		text = value
		label.text = value
		visible = not value.is_empty()
		_refit.call_deferred()

var _anchor: Vector2 = Vector2.ZERO
var _at: Vector2 = Vector2.ZERO


func _init(variation: StringName = &"HudPanel", width: float = 0.0, font_size: int = 0) -> void:
	theme_type_variation = variation
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	label = RichTextLabel.new()
	label.theme_type_variation = &"HudText"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size > 0:
		for kind: StringName in [&"normal_font_size", &"bold_font_size", &"italics_font_size"]:
			label.add_theme_font_size_override(kind, font_size)
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = width
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(label)
	minimum_size_changed.connect(_refit)


func pin(anchor: Vector2, at: Vector2) -> void:
	_anchor = anchor
	_at = at
	anchor_left = anchor.x
	anchor_right = anchor.x
	anchor_top = anchor.y
	anchor_bottom = anchor.y
	_refit()


## Sets the text in the middle, as a banner does.
func center_text(on: bool) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if on else HORIZONTAL_ALIGNMENT_LEFT


func _refit() -> void:
	var want: Vector2 = get_combined_minimum_size()
	var left: float = _at.x - want.x * _anchor.x
	var top: float = _at.y - want.y * _anchor.y
	offset_left = left
	offset_right = left + want.x
	offset_top = top
	offset_bottom = top + want.y
