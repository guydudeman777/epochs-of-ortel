// The ground of a battle field, at the size of a person. The vertex colour is the field as BattleGround painted it, and
// tiles of grass, field, dirt, sand, rock, snow, ash, mud, shore and road from tools/art/build_ground.py lie over it,
// mixed by the shares BattleGround worked out per vertex (CUSTOM0, CUSTOM1, CUSTOM2.xy, in BattleGround.Layer order).
// Two sizes of each tile are laid at once, so the repeat does not show underfoot or across the field. Where two layers
// meet, the taller shows through. Steep ground turns to rock, laid from the side so it does not stretch down a slope.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

const int LAYERS = 10;
const int ROCK = 4;
const int MUD = 7;
const int SHORE = 8;

uniform sampler2DArray albedo_tiles : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tiles : filter_linear_mipmap_anisotropic, repeat_enable;
// Metres one small tile covers, and the larger one laid over it.
uniform float tile_size = 2.6;
uniform float macro_size = 17.0;
uniform float detail_near = 60.0;
uniform float detail_far = 420.0;
uniform float hue_keep = 0.75;
uniform float contrast = 1.15;
uniform float bump = 1.1;
uniform float blend_depth = 0.25;
uniform vec3 rock_color : source_color = vec3(0.33, 0.31, 0.28);
uniform float slope_from = 0.32;
uniform float slope_to = 0.55;
// The water's surface: ground just under it darkens and shines with wet.
uniform float water_level = -100.0;

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

vec3 tile_at(int i, vec2 uv) {
	return texture(albedo_tiles, vec3(uv, float(i))).rgb;
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
	vec3 rock_base = rock_color * clamp(lightness(base) / 0.05, 0.45, 1.5);
	base = mix(base, mix(rock_base, base, 0.3), slope);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(detail_near, detail_far, dist);
	vec3 n_world = n_geo;
	float wet = 0.0;
	if (detail > 0.005 && total > 0.001) {
		vec2 uv = world_pos.xz / tile_size;
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
				c = tile_at(i, world_pos.zy / tile_size) * tri.x + tile_at(i, uv) * tri.y + tile_at(i, world_pos.xy / tile_size) * tri.z;
			} else {
				// The small tile and the large one, mixed so neither repeat shows.
				c = mix(tile_at(i, uv), tile_at(i, uv_macro), 0.35);
			}
			n = texture(normal_tiles, vec3(uv, float(i))).rgb;
			float macro = lightness(tile_at(i, uv_macro * 0.31));
			color[i] = c * (0.72 + macro * 0.56);
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
			if (i == MUD || i == SHORE) {
				wet += (1.0 - bumps[i].b) * w * 0.7;
			}
			weight += w;
		}
		tile /= max(weight, 0.0001);
		tilt /= max(weight, 0.0001);
		wet /= max(weight, 0.0001);
		vec3 factor = tile / 0.214;
		factor = mix(vec3(lightness(factor)), factor, hue_keep);
		factor = max((factor - 1.0) * contrast + 1.0, vec3(0.0));
		base *= mix(vec3(1.0), factor, detail);
		n_world = normalize(n_geo + vec3(tilt.x, 0.0, tilt.y) * bump * detail);
	}
	// Ground at the water's edge is soaked.
	float soaked = 1.0 - smoothstep(0.0, 0.5, world_pos.y - water_level);
	wet = max(wet, soaked);
	base *= 1.0 - soaked * 0.35;
	ALBEDO = base;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ROUGHNESS = 1.0 - wet * 0.55;
	SPECULAR = 0.3 + wet * 0.2;
}
