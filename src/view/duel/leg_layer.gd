class_name LegLayer
extends SkeletonModifier3D
## Puts stepping legs under whatever the upper body is doing, so a fighter can keep a guard up, or wait on guard, while
## stepping any way at all. It runs after the body's AnimationPlayer has posed the whole skeleton, and turns the root,
## hips and legs towards two of the eight stepping clips, blended by how far the way lies between them.
## Every stepping clip is the same length and starts as the left foot lands, so blending two keeps the feet together.

## The bones it takes over. The root carries the body's rise and fall with each step.
const LOWER: Array[String] = ["Root", "pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
## Shares of the way a second the layer comes on or goes off.
const FADE_RATE: float = 5.0

## How much of the stepping shows, from 0 to 1. It eases towards wanted.
var weight: float = 0.0
var wanted: float = 0.0
var _clips: Array[Animation] = []
## For each clip: [track, bone, is_position] for each track that moves a lower bone.
var _tracks: Array[Array] = []
var _first: int = 0
var _second: int = 0
var _mix: float = 0.0
var _time: float = 0.0


## The stepping clips, going round to the left from straight ahead, in even shares of a turn.
func use(player: AnimationPlayer, skeleton: Skeleton3D, clip_names: Array[StringName]) -> void:
	_clips.clear()
	_tracks.clear()
	for clip: StringName in clip_names:
		var animation: Animation = player.get_animation(clip)
		_clips.append(animation)
		var found: Array = []
		for track: int in range(animation.get_track_count()):
			var kind: Animation.TrackType = animation.track_get_type(track)
			if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
				continue
			var bone_name: String = String(animation.track_get_path(track).get_concatenated_subnames())
			if not LOWER.has(bone_name):
				continue
			found.append([track, skeleton.find_bone(bone_name), kind == Animation.TYPE_POSITION_3D])
		_tracks.append(found)


## Which way the body steps, as an angle to the left of straight ahead in radians, and how far through a stride it goes
## this frame at that clip's own pace. The caller works out the pace from the ground covered.
func step(way: float, seconds: float, ground_speed: float, clip_speeds: Array[float]) -> void:
	if _clips.is_empty():
		return
	var count: int = _clips.size()
	var place: float = fposmod(way / TAU * float(count), float(count))
	_first = floori(place) % count
	_second = (_first + 1) % count
	_mix = place - floorf(place)
	var own_speed: float = lerpf(clip_speeds[_first], clip_speeds[_second], _mix)
	var length: float = _clips[_first].length
	_time = fposmod(_time + seconds * ground_speed / maxf(own_speed, 0.05), length)


func ease_towards(seconds: float) -> void:
	weight = move_toward(weight, wanted, seconds * FADE_RATE)


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or weight <= 0.0 or _clips.is_empty():
		return
	var poses: Dictionary[int, Array] = {}
	for which: int in [_first, _second]:
		var share: float = 1.0 - _mix if which == _first else _mix
		var animation: Animation = _clips[which]
		for entry: Array in _tracks[which]:
			var track: int = entry[0]
			var bone: int = entry[1]
			var is_position: bool = entry[2]
			if bone < 0:
				continue
			var key: int = bone * 2 + (1 if is_position else 0)
			if is_position:
				var at: Vector3 = animation.position_track_interpolate(track, _time)
				if poses.has(key):
					poses[key] = [(poses[key][0] as Vector3).lerp(at, share)]
				else:
					poses[key] = [at]
			else:
				var turn: Quaternion = animation.rotation_track_interpolate(track, _time)
				if poses.has(key):
					poses[key] = [(poses[key][0] as Quaternion).slerp(turn, share)]
				else:
					poses[key] = [turn]
	for key: int in poses:
		var bone: int = key / 2
		if key % 2 == 1:
			var at: Vector3 = poses[key][0]
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(at, weight))
		else:
			var turn: Quaternion = poses[key][0]
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(turn, weight))
