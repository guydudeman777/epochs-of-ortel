class_name WorldState
extends Resource

## The root of all mutable state. Saving the game means saving this one object.
## 2: the Empires map, round the Drowned Sea, with cities and the towns bound to them.
const CURRENT_SAVE_VERSION: int = 2

@export var save_version: int = CURRENT_SAVE_VERSION
@export var world_seed: int = 0
## Named population the fertility regulator aims for.
@export var named_target: int = 5000
## How many settlements the map has room for.
@export var max_settlements: int = 0
@export var calendar: CalendarData = CalendarData.new()
@export var next_id: int = 1
## Stream name -> saved RNG state.
@export var rng_states: Dictionary[StringName, int] = {}
@export var player_character_id: int = -1
## The band the player's band has met and must answer, or -1. The world waits on this.
@export var encounter_band_id: int = -1
@export var encounter_can_flee: bool = true
@export var characters: Dictionary[int, CharacterData] = {}
## Dead characters. Kept for lineage and history, never ticked.
@export var archived_characters: Dictionary[int, CharacterData] = {}
@export var dynasties: Dictionary[int, DynastyData] = {}
@export var factions: Dictionary[int, FactionData] = {}
@export var settlements: Dictionary[int, SettlementData] = {}
@export var warbands: Dictionary[int, WarbandData] = {}
@export var businesses: Dictionary[int, BusinessData] = {}
@export var quests: Dictionary[int, QuestData] = {}
@export var map: MapData = MapData.new()
@export var chronicle: Array[ChronicleEntry] = []
## Running totals of world events, used for reports and soak checks.
@export var stats: Dictionary[StringName, int] = {}
