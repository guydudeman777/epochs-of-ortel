class_name TownEntry
extends RefCounted
## The door from the map into a town you can walk about in. Lane C owns this file.
##
## enter() returns true when it has taken over the screen. When the walk is done, the town scene hands the map scene
## back and calls OverworldScene.returned(summary). Returning false makes the map open the town's text menu instead.

const TOWN_SCENE: String = "res://src/view/town/town_scene.tscn"

## The map waiting while you walk, and the town being walked.
static var map: OverworldScene = null
static var site_id: int = -1
## The town just walked out of, and when, so the map does not send you straight back in before any time has passed.
static var _left_site: int = -1
static var _left_at: int = -1


static func enter(scene: OverworldScene, site: int) -> bool:
	if OS.get_cmdline_user_args().has("--no-walk"):
		return false
	var ctx: SimContext = scene.sim()
	if ctx.settlement(site) == null or not ResourceLoader.exists(TOWN_SCENE):
		return false
	if site == _left_site and _left_at == _now(ctx):
		_left_site = -1
		return true
	if map != null:
		return true
	map = scene
	site_id = site
	# Never in the middle of the map's own _ready or a button's signal: the swap waits for the frame to end.
	_swap_in.call_deferred()
	return true


static func _now(ctx: SimContext) -> int:
	return ctx.world.calendar.day_index * CalendarData.WATCHES_PER_DAY + ctx.world.calendar.watch


static func _swap_in() -> void:
	if map == null or not map.is_inside_tree():
		map = null
		return
	var tree: SceneTree = map.get_tree()
	var town: Node = (load(TOWN_SCENE) as PackedScene).instantiate()
	tree.root.remove_child(map)
	tree.root.add_child(town)
	tree.current_scene = town


## The town scene is done. The map comes back and hears what happened.
static func leave(town: Node, summary: String) -> void:
	var scene: OverworldScene = map
	var ctx: SimContext = scene.sim() if scene != null else null
	map = null
	if ctx != null:
		_left_site = site_id
		_left_at = _now(ctx)
	site_id = -1
	var tree: SceneTree = town.get_tree()
	tree.root.remove_child(town)
	town.queue_free()
	if scene == null:
		tree.change_scene_to_file(OverworldScene.MENU_SCENE)
		return
	tree.root.add_child(scene)
	tree.current_scene = scene
	scene.returned(summary)
