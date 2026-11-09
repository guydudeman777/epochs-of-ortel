// The ground of a town you walk in. TownGround paints a mask of the town's layout, half a metre to a texel: r for
// trodden earth (streets and lanes), g for cobbles, b for flagstones, a for mud. Over the open ground of the people's
// land it lays the overworld's dirt and mud tiles (tools/art/build_ground.py) and the town's cobbles and flags
// (tools/art/build_surfaces.py), breaking each edge up with the tiles' own noise so no path has a ruled line. Near
// the middle the open ground is worn bare by feet.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

const int DIRT = 2;
const int MUD = 7;
const int ROAD = 9;
const int COBBLE = 7;
const int FLAGS = 8;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform float mask_size = 200.0;
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform int open_layer = 0;
uniform vec3 open_color : source_color = vec3(0.3, 0.36, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.4, 0.33, 0.25);
uniform vec3 stone_color : source_color = vec3(0.45, 0.43, 0.4);
uniform vec3 mud_color : source_color = vec3(0.27, 0.22, 0.17);
uniform float town_radius = 60.0;
uniform float ground_tile = 4.0;
uniform float cobble_tile = 2.6;
uniform float flags_tile = 3.2;
uniform float bump = 0.9;

varying vec3 world_pos;

float lightness(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 layer(vec3 tile, vec3 color) {
	vec3 factor = tile / 0.214;
	factor = mix(vec3(lightness(factor)), factor, 0.5);
	return color * max((factor - 1.0) * 1.15 + 1.0, vec3(0.0));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec4 m = texture(mask, p / mask_size + 0.5);
	vec2 uv = p / ground_tile;
	vec2 uv_big = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / 23.0;
	float noise = lightness(texture(ground_albedo, vec3(uv_big, float(DIRT))).rgb) / 0.214 - 1.0;
	float fine = lightness(texture(ground_albedo, vec3(uv * 1.7, float(ROAD))).rgb) / 0.214 - 1.0;
	vec3 open_t = texture(ground_albedo, vec3(uv, float(open_layer))).rgb;
	vec3 open_n = texture(ground_normal, vec3(uv, float(open_layer))).rgb;
	vec3 road_t = texture(ground_albedo, vec3(uv, float(ROAD))).rgb;
	vec3 road_n = texture(ground_normal, vec3(uv, float(ROAD))).rgb;
	vec3 mud_t = texture(ground_albedo, vec3(uv * 0.8, float(MUD))).rgb;
	vec3 mud_n = texture(ground_normal, vec3(uv * 0.8, float(MUD))).rgb;
	vec3 cob_t = texture(surface_albedo, vec3(p / cobble_tile, float(COBBLE))).rgb;
	vec3 cob_n = texture(surface_normal, vec3(p / cobble_tile, float(COBBLE))).rgb;
	vec3 flag_t = texture(surface_albedo, vec3(p / flags_tile, float(FLAGS))).rgb;
	vec3 flag_n = texture(surface_normal, vec3(p / flags_tile, float(FLAGS))).rgb;
	float worn = (1.0 - smoothstep(town_radius - 8.0, town_radius + 14.0, length(p))) * 0.55;
	float trod = clamp(max(m.r, worn) + noise * 0.35 + fine * 0.15, 0.0, 1.0);
	trod = smoothstep(0.35, 0.65, trod);
	// Cobbles break up at their edges, where stones are missing and earth shows.
	float cob = smoothstep(0.45, 0.7, m.g + noise * 0.25 + (cob_n.b - 0.5) * 0.4);
	float flag = smoothstep(0.45, 0.6, m.b + noise * 0.15);
	float mud = smoothstep(0.3, 0.7, m.a + noise * 0.4 + fine * 0.2);
	vec3 color = layer(open_t, open_color);
	vec3 n = open_n;
	color = mix(color, layer(road_t, dirt_color), trod);
	n = mix(n, road_n, trod);
	color = mix(color, layer(cob_t, stone_color), cob);
	n = mix(n, cob_n, cob);
	color = mix(color, layer(flag_t, stone_color * 1.05), flag);
	n = mix(n, flag_n, flag);
	color = mix(color, layer(mud_t, mud_color), mud);
	n = mix(n, mud_n, mud);
	vec2 tilt = n.rg * 2.0 - 1.0;
	vec3 world_n = normalize(vec3(tilt.x * bump, 1.0, tilt.y * bump));
	ALBEDO = color;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	// Wet in the mud and between stones.
	ROUGHNESS = 1.0 - mud * 0.25 * (1.0 - mud_n.b) - cob * 0.08 * (1.0 - cob_n.b);
	SPECULAR = 0.3;
}
