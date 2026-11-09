extends SceneTree
## Writes only the wardrobe: every GarmentDef in content/defs/armours. Troop kits are written with the troops.
## Run after the garment build: godot --headless --path . --script res://tools/generate_garments.gd


func _init() -> void:
	GarmentContent.write_garments()
	print("garments generated")
	quit(0)
