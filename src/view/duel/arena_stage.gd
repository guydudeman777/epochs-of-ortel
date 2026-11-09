class_name ArenaStage
extends RefCounted
## The ground, the fence, the light and the sky of a place to fight with no land under it: the duel's ring, and battles
## in a world with no land. Battles on the land stand on a BattleGround that FieldStage draws.


static func build(scene: Node3D, wall_radius: float, wall_pieces: int) -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(wall_radius * 6.0, wall_radius * 6.0)
	mesh.mesh = quad
	var earth: StandardMaterial3D = StandardMaterial3D.new()
	earth.albedo_color = Color(0.21, 0.17, 0.12)
	earth.roughness = 1.0
	mesh.material_override = earth
	ground.add_child(mesh)
	scene.add_child(ground)
	var palisade: PackedScene = load("res://assets/models/palisade.glb") as PackedScene if wall_pieces > 0 else null
	for i: int in range(wall_pieces):
		var angle: float = float(i) / float(wall_pieces) * TAU
		var piece: Node3D = palisade.instantiate() as Node3D
		scene.add_child(piece)
		piece.position = Vector3(cos(angle), 0.0, sin(angle)) * wall_radius
		piece.rotation.y = -angle + PI * 0.5
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.84)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = wall_radius * 2.5
	scene.add_child(sun)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.36)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.32, 0.34, 0.36)
	environment.fog_density = 0.012
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	scene.add_child(holder)
