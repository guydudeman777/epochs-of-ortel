class_name ViewUtil
extends RefCounted
## Small helpers shared by view scenes. Nothing here touches the simulation.


static func find_player(root: Node) -> AnimationPlayer:
	var found: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


static func find_skeleton(root: Node) -> Skeleton3D:
	var found: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


## Starts an animation, with its time offset so that a crowd does not move in step.
static func play(root: Node, anim_name: StringName, looped: bool, offset: float = 0.0) -> void:
	var player: AnimationPlayer = find_player(root)
	var animation: Animation = player.get_animation(anim_name)
	animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	player.play(anim_name)
	player.seek(fmod(offset, animation.length), true)


## Value of a --name=value command line argument, or the fallback.
static func arg(arg_name: String, fallback: String) -> String:
	var prefix: String = "--%s=" % arg_name
	for item: String in OS.get_cmdline_user_args():
		if item.begins_with(prefix):
			return item.trim_prefix(prefix)
	return fallback


## Waits for the pose and lighting to settle, saves the frame, and quits.
static func save_shot_and_quit(node: Node, path: String) -> void:
	for _i: int in range(12):
		await node.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = node.get_viewport().get_texture().get_image()
	var error: Error = image.save_png(path)
	print("SHOT %s (%s)" % [path, error_string(error)])
	node.get_tree().quit(0 if error == OK else 1)
