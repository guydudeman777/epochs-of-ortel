class_name BodyPartDef
extends Resource
## One part of a body. Wounds land on parts, and what a part is for says what its wounds cost.

@export var id: StringName
@export var display_name: String = ""
## Losing the parent loses this part too.
@export var parent: StringName = &""
## This part being destroyed kills.
@export var vital: bool = false
## How much damage takes this part from whole to destroyed.
@export var toughness: float = 50.0
## How likely a blow in the confusion of a battle is to land here, against the other parts.
@export var hit_weight: float = 1.0
## How bad one cut must be, as a share of toughness, to take the part off. 0 means it cannot be cut off.
@export var sever_at: float = 0.0
## Share of the body's blood lost per minute by a wound at full severity.
@export var bleed_rate: float = 0.05
## Share lost per minute by the stump when this part comes off.
@export var stump_bleed: float = 0.0
## Capacity id -> how much of it this part carries. Ids: right_arm, left_arm, left_leg, right_leg, wind, mind.
@export var capacities: Dictionary[StringName, float] = {}
