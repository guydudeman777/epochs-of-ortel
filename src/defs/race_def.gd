class_name RaceDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var lifespan: float = 65.0
@export var adult_age: int = 16
@export var fertility: float = 1.0
@export var food_need: float = 1.0
## Multiplies how much damage every body part can take.
@export var toughness: float = 1.0
@export var attribute_mods: Dictionary[StringName, int] = {}
@export var labor_aptitude: Dictionary[StringName, float] = {}
@export var compatible_races: Array[StringName] = []
@export var names_female: Array[String] = []
@export var names_male: Array[String] = []
## How often founders of this race come from each of the head's population shapes.
@export var face_heritage: Dictionary[StringName, float] = {}
## Slider id -> offset that makes a face read as this race.
@export var face_bias: Dictionary[StringName, float] = {}
@export var face_skin_tint: Color = Color.WHITE
@export var face_beard_chance: float = 0.6
## How fast this race crosses ground, as a multiplier on what anyone gets. Keys are kinds of ground
## (open, forest, hills, water, marsh) or biomes (temperate, north, steppe, ash, desert, tropical, alpine, snow). Missing is 1.
@export var ground_speed: Dictionary[StringName, float] = {}
## How much food this race finds or grows in each biome, as a multiplier on what anyone gets. Missing is 1.
@export var biome_food: Dictionary[StringName, float] = {}
## Parts drawn on top of the shared head, such as gills or feelers. Names only; the view decides how they look.
@export var face_features: Array[StringName] = []
## Eye colours of this race, by FaceService eye colour. Empty means those of the face's human line.
@export var face_eye_colors: Array[StringName] = []
## The build of body and head this race is drawn with. Empty is the human one, shaped by sliders as for any people.
## Names only; the view decides what each looks like.
@export var form: StringName = &""
