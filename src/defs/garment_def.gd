class_name GarmentDef
extends ArmourDef
## Anything worn, from underwear to plate. It is an ArmourDef, so what it stops counts on every blow the same way;
## underwear and plain clothes simply stop little or nothing. Lane D owns the content and the art behind it.
##
## Worn garments are listed in EquipmentData.armour_ids, at most one per slot. Put things on and take them off only
## through Actions.wear and Actions.take_off.

const SLOTS: Array[StringName] = [
	&"underwear_top", &"underwear_bottom", &"shirt", &"trousers", &"body_armour", &"over",
	&"head", &"head_armour", &"hands", &"feet", &"cloak", &"belt",
]

## One of SLOTS.
@export var slot: StringName = &""
## Inner to outer, so the view draws and hides layers in order. Underwear 0, clothes 1, armour 2, over and cloak 3.
@export var layer: int = 1
@export var warmth: float = 0.0
@export var weight: float = 0.0
## Base price in coin, before the market.
@export var value: int = 0
## The garment mesh the body view grows or hangs for it. Empty draws nothing.
@export var model: String = ""
## Skin and inner layers it hides from view, as bits the body build agrees on.
@export var hides: int = 0
## Peoples who make and wear it. Empty means anyone.
@export var culture_ids: Array[StringName] = []
## Craft a realm must know before its smiths and weavers make it. Empty means none.
@export var tech_id: StringName = &""
## Colours it may be dyed in.
@export var colors: PackedColorArray = PackedColorArray()
## Races whose bodies it fits. Empty means every race with the shared human skeleton and look.
@export var race_ids: Array[StringName] = []


## The slot a worn thing takes. Old plain ArmourDefs have none, so each counts as its own slot.
static func slot_of(def: ArmourDef) -> StringName:
	if def is GarmentDef and (def as GarmentDef).slot != &"":
		return (def as GarmentDef).slot
	return StringName("armour:" + String(def.id))
