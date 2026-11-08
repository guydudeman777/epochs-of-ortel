class_name CultureDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var primary_race: StringName = &""
## Race id -> SimEnums.RaceStanding
@export var race_standing: Dictionary[StringName, int] = {}
@export var bondage_law: SimEnums.BondageLaw = SimEnums.BondageLaw.BANNED
@export var hereditary_bondage: bool = false
@export var mixed_heritage_rule: SimEnums.MixedHeritageRule = SimEnums.MixedHeritageRule.DOMINANT
@export var tax_rate: float = 0.1
## 0..1 tendency to start wars.
@export var aggression: float = 0.5
@export var dynasty_names: Array[String] = []
@export var settlement_names: Array[String] = []
@export var faction_names: Array[String] = []
## Given names of this people. Empty means the race's own names.
@export var names_male: Array[String] = []
@export var names_female: Array[String] = []
## How often each face population is seen among this people, by FaceService population. Empty means the race's own.
@export var face_lines: Dictionary[StringName, float] = {}
