extends SceneTree
## Writes only the wardrobe: every GarmentDef in content/defs/armours, and the troops' armour lists.
## Run after the garment build: godot --headless --path . --script res://tools/generate_garments.gd


func _init() -> void:
	GarmentContent.write_all()
	print("garments generated")
	quit(0)
