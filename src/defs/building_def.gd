class_name BuildingDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var build_cost: int = 300
@export var required_tech: StringName = &""
@export var labor_kind: StringName = &"craft"
@export var labor_demand: int = 50
## Whether unfree workers may be assigned, where the owner's law allows it.
@export var allows_forced: bool = false
## Monthly units at full staffing.
@export var inputs: Dictionary[StringName, int] = {}
@export var outputs: Dictionary[StringName, int] = {}
## What must lie near a town for this to work: &"water", &"woods", &"hills", or nothing.
@export var needs_land: StringName = &""
