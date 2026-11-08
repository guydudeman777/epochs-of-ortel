extends Control
## The title screen. Go on with the saved life, make a new one, or be thrown in as somebody random.
##
## godot --path . (the game's main scene). Any of --demo, --seed=, --look= or --shots= skips it and goes straight to the map,
## as the overworld's own options always did. --out=path.png saves a picture of the title.

const OVERWORLD_SCENE: String = "res://src/view/overworld/overworld_scene.tscn"
const CHARACTER_SCENE: String = "res://src/view/menu/character_screen.tscn"
const SAVE_PATH: String = "user://ortel_save.res"
const SKIP_ARGS: Array[String] = ["--demo", "--seed=", "--look=", "--shots="]
const DRIFT_PIXELS: float = 30.0
const DRIFT_SECONDS: float = 40.0

var _map: TextureRect
var _status: Label
var _time: float = 0.0


func _ready() -> void:
	for item: String in OS.get_cmdline_user_args():
		for skip: String in SKIP_ARGS:
			if item.begins_with(skip):
				get_tree().change_scene_to_file.call_deferred(OVERWORLD_SCENE)
				return
	GameClock.paused = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuStyle.apply(self)
	_map = MenuStyle.backdrop(self)
	# Larger than the screen, so its drift never shows an edge.
	_map.offset_left = -DRIFT_PIXELS * 1.5
	_map.offset_top = -DRIFT_PIXELS * 1.5
	_map.offset_right = DRIFT_PIXELS * 1.5
	_map.offset_bottom = DRIFT_PIXELS * 1.5
	MenuStyle.embers(self)
	MenuStyle.vignette(self, 0.85)
	var column: VBoxContainer = VBoxContainer.new()
	column.anchor_left = 0.0
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = 110.0
	column.offset_right = 560.0
	column.offset_top = -250.0
	column.offset_bottom = 280.0
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	column.add_child(MenuStyle.title("Epochs of", 20, MenuStyle.DIM, 9))
	var name_plate: Label = MenuStyle.title("Ortel", 96, MenuStyle.GOLD, 14)
	name_plate.add_theme_constant_override(&"shadow_offset_y", 4)
	name_plate.add_theme_constant_override(&"shadow_outline_size", 12)
	name_plate.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	name_plate.add_theme_color_override(&"font_outline_color", Color(0.25, 0.17, 0.07))
	name_plate.add_theme_constant_override(&"outline_size", 2)
	column.add_child(name_plate)
	column.add_child(MenuStyle.rule(400.0))
	var line: Label = MenuStyle.label("The world does not wait for you.", 19, MenuStyle.DIM)
	line.add_theme_font_override(&"font", MenuStyle.font(false, true))
	column.add_child(line)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 30.0)
	column.add_child(gap)
	var has_save: bool = FileAccess.file_exists(SAVE_PATH)
	var first: Button = null
	if has_save:
		first = _button(column, "Continue", _continue)
	var made: Button = _button(column, "A new life", _new_life)
	if first == null:
		first = made
	_button(column, "Thrown in as somebody", _quick_start)
	_button(column, "Leave", func() -> void: get_tree().quit())
	_status = MenuStyle.label("", 16, MenuStyle.BAD)
	column.add_child(_status)
	first.grab_focus()
	var out_path: String = ViewUtil.arg("out", "")
	if not out_path.is_empty():
		await ViewUtil.save_shot_and_quit(self, out_path)


func _process(delta: float) -> void:
	_time += delta
	if _map != null:
		var phase: float = _time / DRIFT_SECONDS * TAU
		_map.position = Vector2(-DRIFT_PIXELS * 1.5, -DRIFT_PIXELS * 1.5) + Vector2(sin(phase) * DRIFT_PIXELS, cos(phase * 0.7) * DRIFT_PIXELS * 0.5)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(340.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override(&"font_size", 20)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _continue() -> void:
	if World.load_game(SAVE_PATH) != OK:
		_status.text = "The saved life could not be read."
		return
	get_tree().change_scene_to_file(OVERWORLD_SCENE)


func _new_life() -> void:
	get_tree().change_scene_to_file(CHARACTER_SCENE)


## The old way in: a random nobody in a random town of a new world.
func _quick_start() -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = randi() % 100000
	World.new_game(config)
	get_tree().change_scene_to_file(OVERWORLD_SCENE)
