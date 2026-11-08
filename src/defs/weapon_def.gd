class_name WeaponDef
extends Resource
## What a held weapon does. Damage kinds: cut, pierce, crush.

@export var id: StringName
@export var display_name: String = ""
@export var swing_kind: StringName = &"cut"
@export var swing_power: float = 30.0
@export var thrust_kind: StringName = &"pierce"
@export var thrust_power: float = 25.0
## Metres from the wielder's centre.
@export var reach: float = 1.35
## Above 1 swings faster.
@export var speed: float = 1.0
