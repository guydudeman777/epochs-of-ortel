class_name CharacterData
extends Resource

@export var id: int = -1
@export var given_name: String = ""
@export var sex: SimEnums.Sex = SimEnums.Sex.FEMALE
@export var birth_day: int = 0
@export var death_day: int = -1
@export var death_cause: StringName = &""
@export var dynasty_id: int = -1
@export var father_id: int = -1
@export var mother_id: int = -1
@export var spouse_id: int = -1
@export var children_ids: Array[int] = []
@export var owned_character_ids: Array[int] = []
@export var traits: Array[StringName] = []
@export var occupation: StringName = &"commoner"
@export var faction_id: int = -1
## -1 while travelling with a warband between settlements.
@export var settlement_id: int = -1
@export var warband_id: int = -1
@export var employer_business_id: int = -1
@export var pregnant_due_day: int = -1
@export var pregnancy_father_id: int = -1
@export var debt: int = 0
@export var attributes: AttributesData = AttributesData.new()
@export var skills: SkillsData = SkillsData.new()
@export var genetics: GeneticsData = GeneticsData.new()
@export var inventory: InventoryData = InventoryData.new()
@export var relationships: RelationshipsData = RelationshipsData.new()
@export var legal: LegalStatusData = LegalStatusData.new()
@export var body: BodyData = BodyData.new()
@export var equipment: EquipmentData = EquipmentData.new()
