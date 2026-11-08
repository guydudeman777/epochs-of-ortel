class_name TownFigure
extends Node3D
## One person's body walking about a town: their own face and gear, at ease, standing, walking or running by how fast
## they go. The clips are the at-ease ones, in the kit of what they hold.

const LOOPED: Array[StringName] = [&"idle", &"walk", &"run"]
const WALKING_ABOVE: float = 0.15
const RUNNING_ABOVE: float = 2.4
const BLEND: float = 0.2
const LABEL_LIFT: float = 2.15

var character_id: int = -1
var body: Node3D
var _player: AnimationPlayer
var _kit: String = ""
var _clip: StringName = &""


## A body for a real person. near gives them a face; a crowd body has none.
func setup_person(ctx: SimContext, c: CharacterData, near: bool) -> void:
	character_id = c.id
	var worn: Array[String] = BodyView.worn_for(c.equipment)
	_make(c.genetics.face, c.sex == SimEnums.Sex.MALE, age_share(ctx, c), worn, near)


## A body for one of the many, with a face of their people that nobody in the world has.
func setup_crowd(face: FaceData, male: bool, age: float, worn: Array[String]) -> void:
	_make(face, male, age, worn, false)


func _make(face: FaceData, male: bool, age: float, worn: Array[String], near: bool) -> void:
	body = BodyView.make(face, male, age, worn, not near)
	add_child(body)
	if near:
		var head: Node3D = FaceView.attach(body, face, male, age)
		if worn.has("helmet"):
			FaceView.hide_hair(head)
	_player = ViewUtil.find_player(body)
	_kit = BodyView.kit_suffix(worn)
	var armed: bool = false
	for part: String in BodyView.WEAPON_PARTS.values():
		armed = armed or worn.has(part)
	if not armed and not worn.has("shield"):
		_kit = "_unarmed"
	for clip: StringName in LOOPED:
		var own: StringName = _in_kit(clip)
		if _player.has_animation(own):
			_player.get_animation(own).loop_mode = Animation.LOOP_LINEAR
	show_motion(0.0)


## How far through their life a person is, as the body's age slider takes it.
static func age_share(ctx: SimContext, c: CharacterData) -> float:
	var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(c)]
	return clampf((ctx.age_years(c) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)


func add_label(words: String, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = words
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 28
	label.outline_size = 8
	label.modulate = color
	MenuStyle.style_label_3d(label)
	label.position = Vector3(0.0, LABEL_LIFT, 0.0)
	add_child(label)
	return label


## Plays standing, walking or running for a speed in metres a second, at the pace the ground goes by.
func show_motion(speed: float) -> void:
	if _player == null:
		return
	var clip: StringName = &"idle"
	if speed > RUNNING_ABOVE:
		clip = &"run"
	elif speed > WALKING_ABOVE:
		clip = &"walk"
	var own: StringName = _in_kit(clip)
	if own != _clip:
		_clip = own
		_player.play(own, BLEND)
	_player.speed_scale = 1.0 if clip == &"idle" else speed / maxf(BodyView.clip_speed(own), 0.1)


func _in_kit(clip: StringName) -> StringName:
	var own: StringName = StringName(String(clip) + _kit)
	return own if _player.has_animation(own) else clip


## Turns the body to face a way on the ground, easing round.
func face_towards(way: Vector2, delta: float, rate: float = 10.0) -> void:
	if way.length_squared() < 0.0001:
		return
	var want: float = atan2(way.x, way.y)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * rate, 0.0, 1.0))
