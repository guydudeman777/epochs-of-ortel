class_name FaceService
extends RefCounted
## Generates and inherits faces. Callers pass the &"faces" stream, so faces never change the
## random numbers the rest of the simulation sees.

const POPULATIONS: Array[StringName] = [&"african", &"asian", &"caucasian"]
const SLIDER_IDS: Array[StringName] = [
	&"head_fat", &"head_width", &"head_height", &"head_depth", &"forehead_height", &"forehead_slope",
	&"temples", &"brow_angle", &"brow_height", &"brow_ridge", &"eye_size", &"eye_open", &"eye_spacing",
	&"eye_level", &"eye_tilt", &"eye_fold", &"eye_bag", &"cheekbones", &"cheek_full", &"cheek_inner",
	&"nose_size", &"nose_width", &"nose_length", &"nose_depth", &"nose_hump", &"nose_curve", &"nose_tip",
	&"nose_tip_width", &"nostrils", &"mouth_width", &"mouth_height", &"mouth_depth", &"upper_lip",
	&"lower_lip", &"cupids_bow", &"mouth_corners", &"chin_width", &"chin_height", &"chin_forward",
	&"jaw_bones", &"jaw_drop", &"ear_size", &"ear_wing", &"ear_point", &"neck_width",
]
## These read as caricature well before the others do, so they vary less.
const GENTLE_SLIDERS: Array[StringName] = [
	&"upper_lip", &"lower_lip", &"mouth_depth", &"mouth_corners", &"head_fat", &"cheek_full",
	&"eye_level", &"eye_bag", &"nose_depth", &"cheek_inner",
]
## Set only by race, never by chance: nobody grows pointed ears at random.
const RACE_ONLY_SLIDERS: Array[StringName] = [&"ear_point", &"neck_width"]
const SPREAD: float = 0.25
const CHILD_NOISE: float = 0.09
const SLIDER_LIMIT: float = 1.6
const AVERAGE_BEAUTY: float = 0.2
const BEAUTY_SPREAD: float = 0.22
## How much of a person's difference from the average a fully beautiful face keeps.
const BEAUTY_KEEP: float = 0.45
## What a beautiful face leans towards, on top of being close to the average.
const BEAUTY_WOMAN: Dictionary[StringName, float] = {
	&"eye_size": 0.3, &"eye_tilt": 0.2, &"cheekbones": 0.45, &"cheek_full": -0.3, &"cheek_inner": -0.25,
	&"nose_size": -0.4, &"nose_width": -0.35, &"nose_tip": 0.3, &"nose_hump": -0.35, &"upper_lip": 0.35,
	&"lower_lip": 0.35, &"cupids_bow": 0.3, &"mouth_width": -0.12, &"mouth_corners": 0.2, &"chin_width": -0.35,
	&"jaw_bones": -0.35, &"head_fat": -0.35, &"forehead_slope": -0.15,
}
const BEAUTY_MAN: Dictionary[StringName, float] = {
	&"brow_ridge": 0.3, &"cheekbones": 0.4, &"cheek_full": -0.35, &"jaw_bones": 0.5, &"chin_forward": 0.3,
	&"chin_width": 0.15, &"nose_hump": -0.25, &"nose_width": -0.15, &"head_fat": -0.4, &"forehead_slope": 0.1,
}
const MALE_HAIR: Array[StringName] = [
	&"short01", &"short02", &"short04", &"balding", &"long01", &"ponytail01", &"shoulder_back",
]
const FEMALE_HAIR: Array[StringName] = [
	&"long01", &"ponytail01", &"braid01", &"bob02", &"elvs_50s_updo", &"elvs_braid_bun", &"elvs_lara_hair",
	&"elvs_hazel_hair", &"elvs_adrienne_hair", &"elvs_katherine_hair",
]
const AFRO_LINE_HAIR: Array[StringName] = [&"coils", &"coils_short", &"elvs_braided_rows"]
const SHAVED_CHANCE: float = 0.08
const MALE_BROWS: Array[StringName] = [&"eyebrow001", &"eyebrow003", &"eyebrow008"]
const FEMALE_BROWS: Array[StringName] = [&"eyebrow004", &"eyebrow005", &"eyebrow012"]
const BEARDS: Array[StringName] = [
	&"rehmanpolanski_moustache_viking", &"rehmanpolanski_beard_viking", &"grinsegold_beard_sigmund_wip", &"wdg_scruffy_beard",
	&"culturalibre_faun_beard", &"full_beard", &"long_beard", &"goatee",
]
const DARK_EYES: Array[StringName] = [&"brown", &"brown", &"brownlight"]
const LIGHT_EYES: Array[StringName] = [&"brown", &"brownlight", &"green", &"bluegreen", &"blue", &"grey", &"lightblue"]
const MAIN_LINE_SHARE: float = 0.85
const SKIN_VARIANTS: int = 64


## A person with no parents in the world. A beauty below zero is rolled; a line of &"" is rolled.
static func random_face(rng: RandomNumberGenerator, race: RaceDef, male: bool, beauty: float = -1.0, line: StringName = &"") -> FaceData:
	var out: FaceData = FaceData.new()
	out.beauty = beauty if beauty >= 0.0 else clampf(rng.randfn(AVERAGE_BEAUTY, BEAUTY_SPREAD), 0.0, 1.0)
	var keep: float = lerpf(1.0, BEAUTY_KEEP, out.beauty)
	var lean: Dictionary[StringName, float] = BEAUTY_MAN if male else BEAUTY_WOMAN
	for key: StringName in SLIDER_IDS:
		var bias: float = race.face_bias.get(key, 0.0)
		var pull: float = lean.get(key, 0.0)
		var chance: float = 0.0
		if not RACE_ONLY_SLIDERS.has(key):
			chance = rng.randfn(0.0, SPREAD * (0.5 if GENTLE_SLIDERS.has(key) else 1.0)) * keep
		out.sliders[key] = clampf(bias + chance + pull * out.beauty, -SLIDER_LIMIT, SLIDER_LIMIT)
	var chosen: StringName = line if line != &"" else _pick_line(rng, race)
	for population: StringName in POPULATIONS:
		out.heritage[population] = MAIN_LINE_SHARE if population == chosen else (1.0 - MAIN_LINE_SHARE) * 0.5
	out.skin_tint = race.face_skin_tint
	out.beard_growth = race.face_beard_chance
	out.skin_variant = rng.randi_range(0, SKIN_VARIANTS - 1)
	var fair_line: bool = chosen == &"caucasian"
	out.hair_tone = rng.randf() if fair_line else rng.randf_range(0.0, 0.3)
	var eyes: Array[StringName] = LIGHT_EYES if fair_line else DARK_EYES
	if not race.face_eye_colors.is_empty():
		eyes = race.face_eye_colors
	out.eye_color = eyes[rng.randi_range(0, eyes.size() - 1)]
	out.features = race.face_features.duplicate()
	out.form = race.form
	_choose_styles(rng, out, male)
	return out


## A child takes each part of the face from somewhere between the parents, plus a little of its own.
static func child_face(rng: RandomNumberGenerator, mother: FaceData, father: FaceData, male: bool) -> FaceData:
	var out: FaceData = FaceData.new()
	for key: StringName in SLIDER_IDS:
		var from_mother: float = mother.sliders.get(key, 0.0)
		var from_father: float = father.sliders.get(key, 0.0)
		var mixed: float = lerpf(from_mother, from_father, rng.randf_range(0.15, 0.85))
		var noise: float = 0.0 if RACE_ONLY_SLIDERS.has(key) else rng.randfn(0.0, CHILD_NOISE)
		out.sliders[key] = clampf(mixed + noise, -SLIDER_LIMIT, SLIDER_LIMIT)
	for population: StringName in POPULATIONS:
		var mother_share: float = mother.heritage.get(population, 0.0)
		var father_share: float = father.heritage.get(population, 0.0)
		out.heritage[population] = (mother_share + father_share) * 0.5
	out.skin_tint = mother.skin_tint.lerp(father.skin_tint, 0.5)
	out.beard_growth = lerpf(mother.beard_growth, father.beard_growth, 0.5)
	out.skin_variant = mother.skin_variant if rng.randf() < 0.5 else father.skin_variant
	out.hair_tone = clampf(lerpf(mother.hair_tone, father.hair_tone, rng.randf_range(0.2, 0.8)) + rng.randfn(0.0, 0.05), 0.0, 1.0)
	out.eye_color = mother.eye_color if rng.randf() < 0.5 else father.eye_color
	out.beauty = clampf(lerpf(mother.beauty, father.beauty, 0.5) + rng.randfn(0.0, 0.08), 0.0, 1.0)
	out.features = mother.features.duplicate()
	out.form = mother.form if mother.form == father.form else &""
	for feature: StringName in father.features:
		if not out.features.has(feature):
			out.features.append(feature)
	_choose_styles(rng, out, male)
	return out


## How old a character looks, from 0 for a young adult of their race to 1 at the end of its lifespan.
static func apparent_age(ctx: SimContext, c: CharacterData) -> float:
	var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(c)]
	return clampf((ctx.age_years(c) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)


static func _pick_line(rng: RandomNumberGenerator, race: RaceDef) -> StringName:
	var total: float = 0.0
	for population: StringName in POPULATIONS:
		var weight: float = race.face_heritage.get(population, 0.0)
		total += weight
	var roll: float = rng.randf() * total
	for population: StringName in POPULATIONS:
		var weight: float = race.face_heritage.get(population, 0.0)
		roll -= weight
		if roll <= 0.0 and weight > 0.0:
			return population
	return &"caucasian"


static func _choose_styles(rng: RandomNumberGenerator, face: FaceData, male: bool) -> void:
	var hair: Array[StringName] = (MALE_HAIR if male else FEMALE_HAIR).duplicate()
	var african_share: float = face.heritage.get(&"african", 0.0)
	if african_share > 0.5:
		hair.append_array(AFRO_LINE_HAIR)
	face.hair_style = hair[rng.randi_range(0, hair.size() - 1)]
	if male and rng.randf() < SHAVED_CHANCE:
		face.hair_style = &""
	var brows: Array[StringName] = MALE_BROWS if male else FEMALE_BROWS
	face.brow_style = brows[rng.randi_range(0, brows.size() - 1)]
	face.beard_style = &""
	if male and rng.randf() < face.beard_growth:
		face.beard_style = BEARDS[rng.randi_range(0, BEARDS.size() - 1)]
	if not face.features.is_empty():
		face.hair_style = &""
		face.brow_style = &""
		face.beard_style = &""
