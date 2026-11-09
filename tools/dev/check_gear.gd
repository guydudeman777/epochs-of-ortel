extends SceneTree
## Prints each mesh in the kheth gear model and whether it is skinned. Dev tool.


func _init() -> void:
	var source: Node3D = (load("res://assets/models/kheth_gear.glb") as PackedScene).instantiate() as Node3D
	for part: Node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		print(mesh.name, " skin=", mesh.skin != null, " binds=", mesh.skin.get_bind_count() if mesh.skin != null else 0, " parent=", mesh.get_parent().get_class())
	source.free()
	quit(0)
