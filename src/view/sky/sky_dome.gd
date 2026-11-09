class_name SkyDome
extends RefCounted
## The open sky over a place on the ground: a walk in town now, a battle later. It knows the hour and the weather,
## and makes from them the sky (sky.gdshader over the textures of tools/art/build_sky.py), the light of the sun or
## moon, and the ambient light and fog that go with them. Only the view reads it; the world has no weather yet, so
## the weather is picked from the place, the day and the land's biome, the same every time for the same day.
##
## var dome: SkyDome = SkyDome.of_place(hour, seed, biome)
## dome.apply(environment)
## add_child(dome.make_light())

const SHADER: Shader = preload("res://src/view/sky/sky.gdshader")
const CLOUDS_PATH: String = "res://assets/textures/sky/sky_clouds.png"
const STARS_PATH: String = "res://assets/textures/sky/sky_stars.png"
const MOON_PATH: String = "res://assets/textures/sky/sky_moon.png"
## The sun stands this high at noon, in degrees, and the moon's light comes from here.
const NOON_HEIGHT: float = 58.0
const MOON_POSE: Vector3 = Vector3(-38.0, 35.0, 0.0)
## The sun rises and sets at these hours, so the sky is red as town goes dark (night_of).
const SUNRISE: float = 5.5
const SUNSET: float = 19.5
## The light never comes from lower than this, so a low sun does not throw shadows across the whole town.
const LOWEST_LIGHT: float = 8.0

var hour: float = 12.0
## Heaped cloud, the overcast and thin high cloud, each from 0 to 1.
var cover: float = 0.35
var overcast: float = 0.0
var cirrus: float = 0.4
var cloud_tint: Color = Color(1.0, 1.0, 1.0)
## Dust or damp low over the land: its colour, and in alpha how thick.
var haze: Color = Color(0.7, 0.68, 0.64, 0.0)
var wind: Vector2 = Vector2(0.004, 0.0015)

var _material: ShaderMaterial


## The sky over a place at an hour. weather_seed picks the weather: pass something of the place and the day.
static func of_place(at_hour: float, weather_seed: int, biome: LandDef.Biome) -> SkyDome:
	var dome: SkyDome = SkyDome.new()
	dome.hour = fposmod(at_hour, 24.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(weather_seed) ^ 0x5ca1ab1e
	var roll: float = rng.randf()
	var wind_angle: float = rng.randf() * TAU
	dome.wind = Vector2.from_angle(wind_angle) * rng.randf_range(0.002, 0.006)
	dome.cirrus = rng.randf_range(0.1, 0.8)
	match biome:
		LandDef.Biome.DESERT:
			dome.cover = rng.randf_range(0.0, 0.2)
			dome.overcast = 0.0
			dome.haze = Color(0.82, 0.66, 0.46, 0.45)
		LandDef.Biome.STEPPE:
			dome.cover = rng.randf_range(0.1, 0.45)
			dome.overcast = 0.5 if roll < 0.12 else 0.0
			dome.haze = Color(0.75, 0.7, 0.6, 0.2)
		LandDef.Biome.ASH:
			dome.cover = rng.randf_range(0.2, 0.5)
			dome.overcast = rng.randf_range(0.35, 0.8)
			dome.cloud_tint = Color(0.78, 0.66, 0.58)
			dome.haze = Color(0.5, 0.33, 0.24, 0.65)
		LandDef.Biome.TROPICAL:
			dome.cover = rng.randf_range(0.4, 0.8)
			dome.overcast = rng.randf_range(0.3, 0.75) if roll < 0.35 else 0.0
			dome.haze = Color(0.68, 0.74, 0.7, 0.35)
		LandDef.Biome.NORTH:
			dome.cover = rng.randf_range(0.3, 0.7)
			dome.overcast = rng.randf_range(0.4, 0.9) if roll < 0.5 else 0.0
			dome.cloud_tint = Color(0.92, 0.95, 1.0)
			dome.haze = Color(0.66, 0.7, 0.76, 0.2)
		LandDef.Biome.SNOW:
			dome.cover = rng.randf_range(0.3, 0.6)
			dome.overcast = rng.randf_range(0.5, 0.95) if roll < 0.6 else 0.0
			dome.cloud_tint = Color(0.9, 0.94, 1.0)
			dome.haze = Color(0.8, 0.84, 0.9, 0.3)
		LandDef.Biome.ALPINE:
			dome.cover = rng.randf_range(0.2, 0.65)
			dome.overcast = rng.randf_range(0.3, 0.8) if roll < 0.3 else 0.0
		_:
			dome.cover = rng.randf_range(0.2, 0.65)
			dome.overcast = rng.randf_range(0.3, 0.9) if roll < 0.3 else 0.0
			dome.haze = Color(0.7, 0.7, 0.68, 0.15)
	return dome


## From 0 by day to 1 in the dead of night, through dusk and dawn.
static func night_of(at_hour: float) -> float:
	if at_hour >= 12.0:
		return smoothstep(18.0, 21.0, at_hour)
	return 1.0 - smoothstep(4.5, 7.0, at_hour)


func night() -> float:
	return night_of(hour)


## Where the sun truly is, rising in the east at SUNRISE and setting in the west at SUNSET, under the land at night.
func sun_direction() -> Vector3:
	var share: float = _day_share(hour)
	var height: float = sin(share * PI) * NOON_HEIGHT
	var yaw: float = -70.0 + 140.0 * share
	return _toward(Vector3(-height, yaw, 0.0))


func moon_direction() -> Vector3:
	return _toward(MOON_POSE)


## The light's turn in degrees: the sun by day, never lower than LOWEST_LIGHT, and the moon by night.
func light_rotation() -> Vector3:
	var share: float = clampf(_day_share(hour), 0.0, 1.0)
	var height: float = maxf(sin(share * PI) * NOON_HEIGHT, LOWEST_LIGHT)
	var dark: float = night()
	return Vector3(-lerpf(height, -MOON_POSE.x, dark), lerpf(-70.0 + 140.0 * share, MOON_POSE.y, dark), 0.0)


func light_energy() -> float:
	return lerpf(1.3, 0.12, night()) * lerpf(1.0, 0.45, overcast)


func light_color() -> Color:
	var share: float = clampf(_day_share(hour), 0.0, 1.0)
	var height: float = maxf(sin(share * PI) * NOON_HEIGHT, LOWEST_LIGHT)
	var low_sun: float = 1.0 - clampf(height / 30.0, 0.0, 1.0)
	var dark: float = night()
	var sun: Color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.7, 0.45), low_sun * (1.0 - dark)).lerp(Color(0.6, 0.7, 1.0), dark)
	return sun.lerp(Color(0.85, 0.87, 0.9), overcast * 0.6)


## The sun or moon as a light with shadows, posed for the hour.
func make_light() -> DirectionalLight3D:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "SkyLight"
	light.rotation_degrees = light_rotation()
	light.light_energy = light_energy()
	light.light_color = light_color()
	light.shadow_enabled = true
	return light


## The sky's material, made once.
func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"clouds", load(CLOUDS_PATH) as Texture2D)
	_material.set_shader_parameter(&"stars", load(STARS_PATH) as Texture2D)
	_material.set_shader_parameter(&"moon", load(MOON_PATH) as Texture2D)
	_material.set_shader_parameter(&"sun_direction", sun_direction())
	_material.set_shader_parameter(&"moon_direction", moon_direction())
	_material.set_shader_parameter(&"cover", cover)
	_material.set_shader_parameter(&"overcast", overcast)
	_material.set_shader_parameter(&"cirrus", cirrus)
	_material.set_shader_parameter(&"cloud_tint", Vector3(cloud_tint.r, cloud_tint.g, cloud_tint.b))
	_material.set_shader_parameter(&"haze_color", Vector3(haze.r, haze.g, haze.b))
	_material.set_shader_parameter(&"haze", haze.a)
	_material.set_shader_parameter(&"wind", wind)
	# The stars turn a full round in a day.
	_material.set_shader_parameter(&"star_turn", hour / 24.0 * TAU)
	return _material


func make_sky() -> Sky:
	var sky: Sky = Sky.new()
	sky.sky_material = material()
	# The clouds drift, so the light the sky casts is worked out a little each frame rather than all at once.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky


## Puts the sky behind an environment and lets it light the scene and colour the fog. The caller keeps its own
## fog density, glow and the rest.
func apply(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = make_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = lerpf(0.65, 0.35, night()) * lerpf(1.0, 1.1, overcast)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_light_color = fog_color()
	# Far things take the sky's colour behind them, and the sky itself is left clear of the fog.
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0


## The colour of the air low down, near what the shader draws at the horizon.
func fog_color() -> Color:
	var dark: float = night()
	var day: Color = Color(0.6, 0.62, 0.62).lerp(Color(haze.r, haze.g, haze.b), haze.a * 0.7)
	day = day.lerp(Color(0.4, 0.41, 0.43), overcast * 0.7)
	var dusk: float = clampf(1.0 - absf(sun_direction().y) / 0.25, 0.0, 1.0) * (1.0 - dark)
	day = day.lerp(Color(0.62, 0.45, 0.38), dusk * 0.6)
	return day.lerp(Color(0.04, 0.045, 0.07), dark)


## How far the sun is through the day, 0 at sunrise and 1 at sunset, below 0 or past 1 by night, when the sun is under the land.
static func _day_share(at_hour: float) -> float:
	return (at_hour - SUNRISE) / (SUNSET - SUNRISE)


static func _toward(pose: Vector3) -> Vector3:
	var turn: Vector3 = Vector3(deg_to_rad(pose.x), deg_to_rad(pose.y), 0.0)
	return Basis.from_euler(turn) * Vector3.BACK
