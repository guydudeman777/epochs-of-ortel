class_name KillFeed
extends VBoxContainer
## Who fell, top left, with nothing behind it. Each line fades out after a while, unless the fight is over.

const MAX_LINES: int = 6
const STAY_SECONDS: float = 7.0
const FADE_SECONDS: float = 1.5
const FONT_SIZE: int = 17

## While true, nothing fades: the fight is over and the last lines are the story of it.
var hold: bool = false
var _ages: Array[float] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 1)


func add(line: String) -> void:
	var row: RichTextLabel = RichTextLabel.new()
	row.theme_type_variation = &"HudText"
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind: StringName in [&"normal_font_size", &"bold_font_size", &"italics_font_size"]:
		row.add_theme_font_size_override(kind, FONT_SIZE)
	row.text = line
	add_child(row)
	_ages.append(0.0)
	while _ages.size() > MAX_LINES:
		_drop_oldest()


func wipe() -> void:
	while not _ages.is_empty():
		_drop_oldest()
	hold = false


func _process(delta: float) -> void:
	if _ages.is_empty():
		return
	for i: int in range(_ages.size()):
		if not hold:
			_ages[i] += delta
		var row: Control = get_child(i) as Control
		row.modulate.a = 1.0 if hold else clampf((STAY_SECONDS + FADE_SECONDS - _ages[i]) / FADE_SECONDS, 0.0, 1.0)
	while not _ages.is_empty() and _ages[0] > STAY_SECONDS + FADE_SECONDS:
		_drop_oldest()


func _drop_oldest() -> void:
	var row: Node = get_child(0)
	remove_child(row)
	row.queue_free()
	_ages.remove_at(0)
