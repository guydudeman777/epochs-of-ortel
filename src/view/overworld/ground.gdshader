// The overworld ground. The vertex colour is the land as seen from afar, and stays its colour at every distance. Up
// close, tiles of grass, field, dirt, sand, rock, snow, ash, mud, shore and road lie over it as detail, mixed by the
// share of each that OverworldLand worked out per vertex (CUSTOM0, CUSTOM1, CUSTOM2.xy, in OverworldLand.Layer order).
// Where two meet, the taller of them shows through, so stones stand out of sand. Steep slopes turn to rock.
// The tiles come from tools/art/build_ground.py and are centred on mid grey, so they shade the colour, not replace it.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

const int LAYERS = 10;
const int ROCK = 4;
const int MUD = 7;

uniform sampler2DArray albedo_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tiles : filter_linear_mipmap_anisotropic, repeat_enable;
// Map units one tile covers, and the larger tile that breaks up the repeat.
uniform float tile_size = 9.0;
uniform float macro_size = 61.0;
// Detail shows fully nearer than detail_near and is gone past detail_far, where only the vertex colour is left.
uniform float detail_near = 90.0;
uniform float detail_far = 380.0;
// How much of a tile's own hue it adds over the vertex colour, from none to all.
uniform float hue_keep = 0.6;
uniform float contrast = 1.1;
uniform float bump = 0.9;
// How far a taller layer pushes through its neighbour.
uniform float blend_depth = 0.3;
uniform vec3 rock_color : source_color = vec3(0.33, 0.31, 0.28);
// Ground this steep (one less the normal's height) starts to turn to rock, and is all rock at slope_to.
uniform float slope_from = 0.28;
uniform float slope_to = 0.5;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 share_a;
varying vec4 share_b;
varying vec2 share_c;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float lightness(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	share_a = CUSTOM0;
	share_b = CUSTOM1;
	share_c = CUSTOM2.xy;
}

void fragment() {
	float share[LAYERS] = float[](share_a.x, share_a.y, share_a.z, share_a.w, share_b.x, share_b.y, share_b.z, share_b.w, share_c.x, share_c.y);
	vec3 n_geo = normalize(world_normal);
	float slope = smoothstep(slope_from, slope_to, 1.0 - n_geo.y);
	float total = 0.0;
	for (int i = 0; i < LAYERS; i++) {
		share[i] *= 1.0 - slope;
		total += share[i];
	}
	share[ROCK] += slope;
	total += slope;
	vec3 base = to_linear(COLOR.rgb);
	// Bare rock keeps a little of the country's colour, so ash rock stays dark and desert rock warm.
	vec3 rock_base = rock_color * clamp(lightness(base) / 0.05, 0.45, 1.5);
	base = mix(base, mix(rock_base, base, 0.3), slope);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(detail_near, detail_far, dist);
	vec3 n_world = n_geo;
	float wet = 0.0;
	if (detail > 0.005 && total > 0.001) {
		vec2 uv = world_pos.xz / tile_size;
		// Turned against the small tile, so the two repeats never line up.
		vec2 uv_macro = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * world_pos.xz / macro_size;
		vec3 tri = pow(abs(n_geo), vec3(4.0));
		tri /= tri.x + tri.y + tri.z;
		vec3 color[LAYERS];
		vec3 bumps[LAYERS];
		float score[LAYERS];
		float top = -10.0;
		for (int i = 0; i < LAYERS; i++) {
			score[i] = -10.0;
			if (share[i] < 0.02) {
				continue;
			}
			vec3 c;
			vec3 n;
			if (i == ROCK && tri.y < 0.95) {
				// Cliffs: the tile is laid from the side as well as from above, so it does not stretch down the slope.
				c = texture(albedo_tiles, vec3(world_pos.zy / tile_size, float(i))).rgb * tri.x
					+ texture(albedo_tiles, vec3(uv, float(i))).rgb * tri.y
					+ texture(albedo_tiles, vec3(world_pos.xy / tile_size, float(i))).rgb * tri.z;
				n = texture(normal_tiles, vec3(uv, float(i))).rgb;
			} else {
				c = texture(albedo_tiles, vec3(uv, float(i))).rgb;
				n = texture(normal_tiles, vec3(uv, float(i))).rgb;
			}
			float macro = lightness(texture(albedo_tiles, vec3(uv_macro, float(i))).rgb);
			color[i] = c * (0.7 + macro * 0.6);
			bumps[i] = n;
			score[i] = share[i] / total + n.b * blend_depth;
			top = max(top, score[i]);
		}
		vec3 tile = vec3(0.0);
		vec2 tilt = vec2(0.0);
		float weight = 0.0;
		for (int i = 0; i < LAYERS; i++) {
			float w = max(score[i] - top + blend_depth, 0.0);
			if (w <= 0.0) {
				continue;
			}
			tile += color[i] * w;
			tilt += (bumps[i].rg * 2.0 - 1.0) * w;
			if (i == MUD) {
				wet += (1.0 - bumps[i].b) * w;
			}
			weight += w;
		}
		tile /= max(weight, 0.0001);
		tilt /= max(weight, 0.0001);
		wet /= max(weight, 0.0001);
		// Tiles are made around mid grey (linear about 0.21), so dividing by that leaves the colour as it was on average.
		vec3 factor = tile / 0.214;
		factor = mix(vec3(lightness(factor)), factor, hue_keep);
		factor = max((factor - 1.0) * contrast + 1.0, vec3(0.0));
		base *= mix(vec3(1.0), factor, detail);
		n_world = normalize(n_geo + vec3(tilt.x, 0.0, tilt.y) * bump * detail);
	}
	ALBEDO = base;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ROUGHNESS = 1.0 - wet * 0.45;
	SPECULAR = 0.3;
}
