class_name WoundData
extends Resource

@export var part_id: StringName
## cut, pierce or crush.
@export var kind: StringName = &"cut"
## 0..1. How much of the part this wound takes away now.
@export var severity: float = 0.0
## What will never heal.
@export var lasting: float = 0.0
## Share of the body's blood lost per minute until it is staunched.
@export var bleed: float = 0.0
## 0..1. Kills at 1.
@export var infection: float = 0.0
@export var day: int = 0
