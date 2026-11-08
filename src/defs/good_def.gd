class_name GoodDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var base_price: float = 1.0
@export var is_food: bool = false
## Units consumed per month per 100 people. Also drives the target stock for pricing.
@export var demand_per_100: float = 0.0
