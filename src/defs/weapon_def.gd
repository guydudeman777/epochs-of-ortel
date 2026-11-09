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
## The look it is drawn as: a weapon part of body_mh.glb, as BodyView.WEAPON_PARTS also says.
@export var model: String = ""
## Held in both hands on a long shaft, as a spear is. Nobody carries a shield with one.
@export var polearm: bool = false
