class_name PlayerSpec
extends RefCounted
## Who the player chose to be, from the character screen. Not saved: once placed, the person is ordinary world state.

var given_name: String = ""
## Name of the new line. Empty gives "<name>'s line".
var family_name: String = ""
var sex: SimEnums.Sex = SimEnums.Sex.MALE
var race_id: StringName = &"human"
var settlement_id: int = -1
var age_years: float = 20.0
var background: StringName = &"tiller"
var traits: Array[StringName] = []
## Null rolls one for the race.
var face: FaceData = null
## The people they were born among: a human culture, or with realm_id the one realm of an old race. Empty and -1
## let them start anywhere their race lives.
var culture_id: StringName = &""
var realm_id: int = -1
