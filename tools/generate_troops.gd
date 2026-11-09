extends SceneTree
## Writes only the soldiers: every people's troop tree in content/defs/troops, and every weapon in content/defs/weapons.
## Run after the garments, so the troops' kits name garments that are there:
## godot --headless --path . --script res://tools/generate_troops.gd


func _init() -> void:
	TroopContent.write_all()
	print("troops generated")
	quit(0)
