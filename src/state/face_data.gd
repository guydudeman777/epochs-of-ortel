class_name FaceData
extends Resource
## One person's face. Sliders are values on the shared head mesh, so a face is plain data that
## can be inherited, saved and hashed. Only named characters have one; commoners stay generic.

## Slider id -> value. Zero is the average for the slider.
@export var sliders: Dictionary[StringName, float] = {}
## Blend of the head's population shapes. Population id -> share. Always sums to 1.
@export var heritage: Dictionary[StringName, float] = {}
## Multiplied over the skin, for races whose skin no human texture covers.
@export var skin_tint: Color = Color.WHITE
## Which of the skins matching this person's age, sex and heritage they wear.
@export var skin_variant: int = 0
## 0 is near black and 1 fair. Greying with age is added when drawn.
@export var hair_tone: float = 0.5
@export var eye_color: StringName = &"brown"
## How likely a man of this line is to wear a beard, 0 to 1.
@export var beard_growth: float = 0.6
## How far this face leans towards what people find beautiful, 0 to 1.
@export var beauty: float = 0.0
@export var brow_style: StringName = &""
## Personal choices rather than inheritance. Empty means none.
@export var hair_style: StringName = &""
@export var beard_style: StringName = &""
## Parts of the race drawn on top of the shared head, such as gills or feelers. A face with any grows no hair.
@export var features: Array[StringName] = []
## The build of body and head the face is drawn on, from RaceDef.form. Empty is the human one.
@export var form: StringName = &""
