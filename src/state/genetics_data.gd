class_name GeneticsData
extends Resource

## Attribute id -> inherited potential.
@export var genes: Dictionary[StringName, float] = {}
## Race id -> fraction of heritage. Always sums to 1.
@export var ancestry: Dictionary[StringName, float] = {}
## Named characters' faces, inherited like the rest of this.
@export var face: FaceData = FaceData.new()
