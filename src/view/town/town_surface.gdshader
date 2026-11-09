// What the town's buildings are made of, up close. Every walk_* model takes its colour from one palette texture, a row
// per swatch (tools/art/common.py), so the row a face reads tells what it is: plaster, boards, stone, brick, thatch,
// shingle or cloth. TownSurfaces bakes that into the kinds texture, and this lays the matching tile from
// tools/art/build_surfaces.py over the colour, in the model's own space so it stays put on the building. It also
// darkens and dirties the foot of every wall, streaks the walls under the eaves, tints each house a little its own way,
// and lights windows from inside at night. INSTANCE_CUSTOM (or `variety` on a lone model) holds, per building: x its
// own tint, y how worn, z the share of its windows lit at night.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

const float ROWS = 64.0;
const float NONE = 255.0;

uniform sampler2D palette : source_color, filter_nearest;
// One texel per palette row: r the surface (index / 255, 255 for none), g metal, b metres a tile covers / 8,
// a 0 for plain, 0.5 for a window, 0.75 for a lamp's glass, 1 for an ember that glows.
uniform sampler2D kinds : filter_nearest;
uniform sampler2DArray surface_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float night = 0.0;
uniform float detail_far = 70.0;
uniform float hue_keep = 0.45;
uniform float contrast = 1.25;
uniform float bump = 0.8;
uniform vec3 window_light : source_color = vec3(1.0, 0.62, 0.28);
uniform vec3 lamp_light : source_color = vec3(1.0, 0.72, 0.4);
// From 0 by day to 1 once the lamps are lit at dusk (TownSurfaces.set_night).
uniform float lamps = 0.0;
instance uniform vec4 variety = vec4(0.0);

varying vec3 own_pos;
varying vec3 own_normal;
varying vec3 world_pos;
varying vec4 custom;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float lightness(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	own_pos = VERTEX;
	own_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	custom = INSTANCE_CUSTOM + variety;
}

void fragment() {
	float row = floor(UV.y * ROWS);
	vec4 kind = texelFetch(kinds, ivec2(int(clamp(row, 0.0, ROWS - 1.0)), 0), 0);
	vec3 base = texture(palette, UV).rgb;
	float surface = floor(kind.r * 255.0 + 0.5);
	float metal = kind.g;
	float glow = kind.a;
	vec3 n_own = normalize(own_normal);
	vec3 bent = n_own;
	float tint = custom.x;
	float worn = custom.y;
	// Each building a little lighter or darker, and plaster washed one of a few colours.
	base *= 0.9 + fract(tint * 7.31) * 0.2;
	if (surface == 0.0) {
		vec3 wash = mix(vec3(1.06, 1.0, 0.88), vec3(0.98, 0.92, 0.78), step(0.35, tint));
		wash = mix(wash, vec3(1.02, 0.9, 0.84), step(0.7, tint));
		wash = mix(wash, vec3(0.92, 0.96, 0.9), step(0.88, tint));
		base *= wash;
	}
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(detail_far * 0.5, detail_far, dist);
	float height = 0.5;
	if (surface < NONE && detail > 0.01) {
		float metres = max(kind.b * 8.0, 0.25);
		vec3 tri = pow(abs(n_own), vec3(4.0));
		tri /= tri.x + tri.y + tri.z;
		// Up a wall is down the tile, so boards, courses and thatch stand the right way.
		vec2 uv_x = vec2(own_pos.z, -own_pos.y) / metres;
		vec2 uv_y = own_pos.xz / metres;
		vec2 uv_z = vec2(own_pos.x, -own_pos.y) / metres;
		vec3 c = texture(surface_albedo, vec3(uv_x, surface)).rgb * tri.x
			+ texture(surface_albedo, vec3(uv_y, surface)).rgb * tri.y
			+ texture(surface_albedo, vec3(uv_z, surface)).rgb * tri.z;
		vec3 nx = texture(surface_normal, vec3(uv_x, surface)).rgb;
		vec3 ny = texture(surface_normal, vec3(uv_y, surface)).rgb;
		vec3 nz = texture(surface_normal, vec3(uv_z, surface)).rgb;
		height = nx.b * tri.x + ny.b * tri.y + nz.b * tri.z;
		vec2 tx = nx.rg * 2.0 - 1.0;
		vec2 ty = ny.rg * 2.0 - 1.0;
		vec2 tz = nz.rg * 2.0 - 1.0;
		// Each face's tilt, on the two axes its tile is laid along.
		vec3 tilt = vec3(0.0, -tx.y, tx.x) * tri.x * sign(n_own.x)
			+ vec3(ty.x, 0.0, ty.y) * tri.y
			+ vec3(tz.x, -tz.y, 0.0) * tri.z;
		bent = normalize(n_own + tilt * bump * detail);
		vec3 factor = c / 0.214;
		factor = mix(vec3(lightness(factor)), factor, hue_keep);
		factor = max((factor - 1.0) * contrast + 1.0, vec3(0.0));
		base *= mix(vec3(1.0), factor, detail);
	}
	// Grime: the foot of every wall, splashed from the street, worse on a worn house.
	float foot = 1.0 - smoothstep(0.0, 1.1 + worn * 0.8, world_pos.y);
	float blotch = hash(floor(world_pos * 2.0)) * 0.3 + 0.7;
	base = mix(base, base * vec3(0.55, 0.5, 0.45), foot * (0.45 + worn * 0.35) * blotch * (1.0 - metal));
	// Rain streaks down the walls.
	float wall = 1.0 - abs(n_own.y);
	float streak = smoothstep(0.55, 1.0, fract(sin(floor((own_pos.x + own_pos.z) * 3.0) * 43.1) * 917.3));
	base *= 1.0 - wall * streak * (0.06 + worn * 0.1);
	// Hollows (mortar, gaps between boards) hold dirt.
	base *= mix(1.0, 0.75 + height * 0.35, detail);
	ALBEDO = base;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bent, 0.0)).xyz);
	METALLIC = metal;
	ROUGHNESS = mix(0.92, 0.5, metal);
	SPECULAR = 0.35;
	if (glow > 0.875) {
		EMISSION = base * (1.6 + night * 2.0);
	} else if (glow > 0.625) {
		// A lamp's glass: dull and a little glassy by day, lit after dusk with a flame's unsteady light.
		float flicker = 0.9 + 0.1 * sin(TIME * 7.0 + hash(floor(world_pos * 2.0)) * 40.0);
		ALBEDO = mix(base * 0.7, base * 0.25, lamps);
		EMISSION = lamp_light * lamps * 5.0 * flicker * (0.8 + 0.2 * smoothstep(-0.2, 0.2, own_pos.y - floor(own_pos.y)));
		ROUGHNESS = 0.2;
		SPECULAR = 0.6;
	} else if (glow > 0.25) {
		// A window: dark glass by day, lit from inside at night if anyone is home. Each lit one its own warmth, a
		// candle's yellow to a hearth's red, uneven across its panes where someone or something stands inside.
		vec3 cell = floor(world_pos * 0.6) + vec3(tint * 13.0);
		float lit = step(hash(cell), custom.z) * night;
		float warmth = hash(cell + vec3(5.3));
		float flicker = 0.85 + 0.15 * sin(TIME * (2.0 + warmth * 3.0) + hash(floor(world_pos)) * 40.0);
		vec3 inside = floor(own_pos * 3.0);
		float shade = 0.55 + 0.45 * hash(inside + cell);
		vec3 light = mix(window_light, vec3(1.0, 0.42, 0.16), warmth * warmth);
		ALBEDO = mix(base, base * 0.3, lit);
		EMISSION = light * lit * 3.4 * flicker * shade;
		ROUGHNESS = mix(0.25, 0.9, lit);
		SPECULAR = 0.55;
	}
}
