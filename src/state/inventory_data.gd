class_name InventoryData
extends Resource

@export var gold: int = 0
@export var goods: Dictionary[StringName, int] = {}
## Things carried but not worn: garment and weapon ids, with how many.
@export var items: Dictionary[StringName, int] = {}
