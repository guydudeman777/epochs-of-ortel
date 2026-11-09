class_name EquipmentData
extends Resource

## Empty means bare hands.
@export var weapon_id: StringName = &""
@export var has_shield: bool = false
@export var armour_ids: Array[StringName] = []
## The standing (Outfits tier) their people's ways last dressed them for, or -1 if they chose their own clothes or wear
## a kit. Lets the wardrobe see at a glance whether anything has changed.
@export var dressed_tier: int = -1
