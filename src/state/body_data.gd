class_name BodyData
extends Resource
## What has happened to a person's body. A whole body has nothing in it but full blood.

@export var wounds: Array[WoundData] = []
## Parts cut off, each named once. Their children are gone too and are not listed.
@export var lost_parts: Array[StringName] = []
## 1 is all of it.
@export var blood: float = 1.0
