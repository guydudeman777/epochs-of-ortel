class_name PopGroupData
extends Resource

## Commoners of one race and one legal status in one settlement.
@export var race_id: StringName = &""
@export var status: SimEnums.LegalStatus = SimEnums.LegalStatus.FREE
@export var count: int = 0
## 0..100
@export var unrest: float = 0.0
