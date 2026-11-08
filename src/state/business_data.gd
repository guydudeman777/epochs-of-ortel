class_name BusinessData
extends Resource

## A working building. Every building is a business with an owner; a character
## and a faction own one in exactly the same way.
@export var id: int = -1
@export var building_id: StringName = &""
@export var settlement_id: int = -1
@export var owner_kind: SimEnums.OwnerKind = SimEnums.OwnerKind.FACTION
@export var owner_id: int = -1
@export var employee_ids: Array[int] = []
@export var free_workers: int = 0
@export var forced_workers: int = 0
