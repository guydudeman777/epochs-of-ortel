class_name DuelFighterView
extends Node3D
## One fighter's body in the arena. It follows the rules' state and picks the clip that shows it.
## The clip says what the upper body does, in the fighter's own kit (see BodyView.kit_suffix). Stepping is a LegLayer
## under it, so a guard, a flinch or plain waiting on guard all go on while the feet step any way.

const ATTACK_CLIPS: Dictionary[DuelFighter.Move, StringName] = {
	DuelFighter.Move.OVERHEAD: &"attack", DuelFighter.Move.LEFT: &"attack_left", DuelFighter.Move.RIGHT: &"attack_right",
	DuelFighter.Move.THRUST: &"attack_thrust", DuelFighter.Move.LOW: &"attack_low",
}
const GUARD_CLIPS: Dictionary[DuelFighter.Guard, StringName] = {
	DuelFighter.Guard.UP: &"block_up", DuelFighter.Guard.LEFT: &"block_left",
	DuelFighter.Guard.RIGHT: &"block_right", DuelFighter.Guard.LOW: &"block_low",
}
## Every blow clip lands at this time, and lasts twice as long.
const CLIP_STRIKE_TIME: float = 0.75
const GUARD_HOLD_TIME: float = 0.3
const BLEND: float = 0.1
const MOVING: float = 0.15
const RUNNING_ABOVE: float = 1.9
## Stepping on guard, a clip for every eighth of a turn, going round to the left from straight ahead.
const STEP_CLIPS: Array[StringName] = [&"step_f", &"step_fl", &"step_l", &"step_bl", &"step_b", &"step_br", &"step_r", &"step_fr"]
## Clips whose names start so loop.
const LOOPED_PREFIXES: Array[String] = ["ready", "run", "step_"]

var fighter: DuelFighter
var character_id: int = -1
var face: FaceData
var male: bool = true
var age: float = 0.2
var worn: Array[String] = []
var tint: Color = BodyView.NO_TINT
var body: Node3D
var _player: AnimationPlayer
var _layer: LegLayer
var _step_speeds: Array[float] = []
var _kit: String = ""
var _clip: StringName = &""
var _last_move: DuelFighter.Move = DuelFighter.Move.NONE
var _simulator: PhysicalBoneSimulator3D = null
var _limp: bool = false
var _near: bool = true
var _head: Node3D = null
var _parting: Array[PackedStringArray] = []


## near starts the body in full detail, with its face. Otherwise it is one of a crowd until set_near says different.
func setup(the_fighter: DuelFighter, c: CharacterData, age_share: float, side_color: Color = BodyView.NO_TINT, near: bool = true) -> void:
	fighter = the_fighter
	character_id = c.id
	face = c.genetics.face
	male = c.sex == SimEnums.Sex.MALE
	age = age_share
	tint = side_color
	worn = BodyView.worn_for(c.equipment)
	_near = near
	body = BodyView.make(face, male, age, worn, not near, tint)
	add_child(body)
	if near:
		_show_head()
	_player = ViewUtil.find_player(body)
	for clip: StringName in _player.get_animation_list():
		for prefix: String in LOOPED_PREFIXES:
			if String(clip).begins_with(prefix):
				_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_kit = BodyView.kit_suffix(worn)
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(body)
	_layer = LegLayer.new()
	skeleton.add_child(_layer)
	_layer.use(_player, skeleton, STEP_CLIPS)
	for clip: StringName in STEP_CLIPS:
		_step_speeds.append(BodyView.clip_speed(clip))
	show_body(c)
	_follow()
	_play(&"ready", 1.0)


func is_near() -> bool:
	return _near


## Swaps between full detail with a face and a crowd body with none. Nothing else about the person changes.
func set_near(near: bool) -> void:
	if near == _near:
		return
	_near = near
	BodyView.show_detail(body, face, male, age, worn, not near, tint)
	if near:
		_show_head()
	elif _head != null:
		_head.visible = false


func _show_head() -> void:
	if _head == null:
		_head = FaceView.attach(body, face, male, age)
		if worn.has("helmet"):
			FaceView.hide_hair(_head)
	_head.visible = true


func show_body(c: CharacterData) -> void:
	LimbView.show_losses(body, c.body.lost_parts)


## The body stops holding itself up. From here on physics moves it, and nothing else does.
func go_limp(scene: Node3D, push: Vector3, struck_bone: String) -> void:
	if _limp:
		return
	_limp = true
	_player.speed_scale = 1.0
	_layer.active = false
	_simulator = Ragdoll.prepare(body)
	_parting = Ragdoll.go_limp(scene, body, _simulator, push, struck_bone)


func _physics_process(_delta: float) -> void:
	if not _parting.is_empty():
		_parting = Ragdoll.collide_again_once_parted(_simulator, _parting)


func _process(delta: float) -> void:
	if _limp or fighter == null:
		return
	_layer.ease_towards(delta)
	if _layer.weight <= 0.0:
		return
	var along: float = fighter.velocity.dot(fighter.facing)
	var right: Vector2 = Vector2(-fighter.facing.y, fighter.facing.x)
	var left: float = -fighter.velocity.dot(right)
	_layer.step(atan2(left, along), delta, fighter.velocity.length(), _step_speeds)


func update_view() -> void:
	if _limp:
		return
	_follow()
	# Whether the feet may step under what the upper body does. Blows bring their own step in.
	var stepping: bool = false
	match fighter.state:
		DuelFighter.State.WINDUP, DuelFighter.State.RECOVER:
			if fighter.state == DuelFighter.State.WINDUP:
				_last_move = fighter.move
			var attack_clip: StringName = ATTACK_CLIPS.get(_last_move, &"attack")
			_play(attack_clip, 1.0)
			_player.speed_scale = CLIP_STRIKE_TIME / maxf(fighter.state_length, 0.05)
		DuelFighter.State.GUARD:
			_play(GUARD_CLIPS[fighter.guard], 1.0)
			_player.speed_scale = 0.0 if _player.current_animation_position >= GUARD_HOLD_TIME else 1.0
			stepping = true
		DuelFighter.State.STAGGER:
			_play(&"hit_front", 1.0)
			stepping = true
		DuelFighter.State.DOWN, DuelFighter.State.DEAD:
			# The scene makes the body go limp when it hears of it. Nothing to play until then.
			pass
		DuelFighter.State.YIELDED:
			_play(&"yield", 1.0)
		_:
			stepping = _show_moving()
	_layer.wanted = 1.0 if stepping and fighter.velocity.length() >= MOVING else 0.0


func _follow() -> void:
	position = Vector3(fighter.position.x, 0.0, fighter.position.y)
	basis = Basis.looking_at(Vector3(fighter.facing.x, 0.0, fighter.facing.y), Vector3.UP, true)


## Waits on guard, with the legs left to the layer, or runs. Says whether the legs step.
func _show_moving() -> bool:
	var speed: float = fighter.velocity.length()
	if speed > RUNNING_ABOVE:
		_play(&"run", speed / BodyView.clip_speed(_in_kit(&"run")))
		return false
	_play(&"ready", 1.0)
	return true


## Plays the fighter's own kit's version of a clip, where there is one.
func _play(clip: StringName, speed: float) -> void:
	var own: StringName = _in_kit(clip)
	if own != _clip:
		_clip = own
		_player.play(own, BLEND)
	_player.speed_scale = speed


func _in_kit(clip: StringName) -> StringName:
	var own: StringName = StringName(String(clip) + _kit)
	return own if _player.has_animation(own) else clip


## Starts a clip over when the same blow follows itself.
func restart_clip() -> void:
	_clip = &""
