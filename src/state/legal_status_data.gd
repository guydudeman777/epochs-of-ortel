class_name LegalStatusData
extends Resource

@export var status: SimEnums.LegalStatus = SimEnums.LegalStatus.FREE
@export var owner_kind: SimEnums.OwnerKind = SimEnums.OwnerKind.NONE
@export var owner_id: int = -1
## Day the term ends. -1 means no term.
@export var term_end_day: int = -1
@export var origin: SimEnums.BondageOrigin = SimEnums.BondageOrigin.NONE
