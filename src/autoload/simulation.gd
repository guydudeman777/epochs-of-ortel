extends Node
## Thin wrapper that runs a SimKernel for the current world.

var kernel: SimKernel = null
## The battle being fought, handed from the overworld to the battle scene, and the overworld kept waiting meanwhile.
var field_battle: FieldBattle = null
var overworld: Node = null


func _ready() -> void:
	World.world_changed.connect(_on_world_changed)


func _on_world_changed(state: WorldState) -> void:
	kernel = SimKernel.new(state, DefRegistry.catalog, EventBus)


func advance_day() -> void:
	if kernel != null:
		kernel.advance_day()
