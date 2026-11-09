class_name PortraitShots
extends Node
## Small painted likenesses of people, head and shoulders, for lists and family trees where a live figure each would
## cost too much. Each is drawn once in a hidden stage, a few frames after it is asked for, and kept.

const SIZE: Vector2i = Vector2i(176, 208)
const FRAMES_TO_SETTLE: int = 3

var ctx: SimContext
var _stage: SubViewport
var _root: Node3D
var _camera: Camera3D
var _queue: Array[Array] = []
var _cache: Dictionary[String, Texture2D] = {}
var _figure: Node3D = null
var _waiting: int = -1
var _current: Array = []


func _ready() -> void:
	_stage = SubViewport.new()
	_stage.size = SIZE
	_stage.own_world_3d = true
	_stage.transparent_bg = true
	_stage.msaa_3d = Viewport.MSAA_4X
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage)
	_root = Node3D.new()
	_stage.add_child(_root)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-20.0, 35.0, 0.0)
	key.light_color = Color(1.0, 0.88, 0.74)
	key.light_energy = 1.0
	_stage.add_child(key)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-8.0, 205.0, 0.0)
	rim.light_color = Color(0.6, 0.68, 0.95)
	rim.light_energy = 0.7
	_stage.add_child(rim)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.57, 0.52)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.sky = PortraitView.studio_sky()
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	_stage.add_child(holder)
	_camera = Camera3D.new()
	_camera.fov = 22.0
	_stage.add_child(_camera)


## Shows this person's likeness in target as soon as it is drawn. A person drawn before shows at once.
func show_in(c: CharacterData, target: TextureRect) -> void:
	if c == null or c.genetics == null or c.genetics.face == null:
		return
	var key: String = _key_of(c)
	if _cache.has(key):
		target.texture = _cache[key]
		return
	_queue.append([c, target, key])


func _give(job: Array, texture: Texture2D) -> void:
	var target: Variant = job[1]
	if is_instance_valid(target):
		(target as TextureRect).texture = texture


func _key_of(c: CharacterData) -> String:
	return "%d|%d|%s" % [c.id, floori(ctx.age_years(c)), hash(c.equipment.armour_ids)]


func _process(_delta: float) -> void:
	if _waiting > 0:
		_waiting -= 1
		return
	if _waiting == 0:
		_waiting = -1
		var texture: ImageTexture = ImageTexture.create_from_image(_stage.get_texture().get_image())
		var key: String = _current[2] as String
		_cache[key] = texture
		_give(_current, texture)
		# Anyone else waiting on the same likeness has it too.
		var left: Array[Array] = []
		for job: Array in _queue:
			if (job[2] as String) == key:
				_give(job, texture)
			else:
				left.append(job)
		_queue = left
		_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_root.remove_child(_figure)
		_figure.queue_free()
		_figure = null
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	var c: CharacterData = _current[0] as CharacterData
	if _cache.has(_current[2] as String):
		_give(_current, _cache[_current[2] as String])
		return
	var race: RaceDef = ctx.defs.races.get(GeneticsService.dominant_race(c), null)
	var share: float = 0.3
	if race != null:
		share = clampf((ctx.age_years(c) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)
	var male: bool = c.sex == SimEnums.Sex.MALE
	var worn: Array[String] = BodyView.worn_for(c.equipment, c.id, null, Outfits.tier_of(ctx, c))
	_figure = BodyView.make(c.genetics.face, male, share, worn)
	_root.add_child(_figure)
	var head: Node3D = FaceView.attach(_figure, c.genetics.face, male, share)
	if BodyView.hides_hair(worn) and head != null and not BodyView.has_own_body(c.genetics.face):
		FaceView.hide_hair(head)
	ViewUtil.play(_figure, &"idle_unarmed", true)
	_figure.rotation.y = 0.35
	var eyes: float = BodyView.eye_height(ViewUtil.find_skeleton(_figure))
	_camera.look_at_from_position(Vector3(0.12, eyes - 0.02, 1.05), Vector3(0.0, eyes - 0.1, 0.0), Vector3.UP)
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_waiting = FRAMES_TO_SETTLE
