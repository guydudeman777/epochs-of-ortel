class_name TownEntry
extends RefCounted
## The door from the map into a town you can walk about in. Lane C owns this file.
##
## enter() returns true when it has taken over the screen. When the walk is done, the town scene hands the map scene
## back and calls OverworldScene.returned(summary). Returning false makes the map open the town's text menu instead.


static func enter(_scene: OverworldScene, _site: int) -> bool:
	return false
