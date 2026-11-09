// The leaves and needles of the battle field's trees: cards from tools/art/build_field.py, each a cluster of leaves or
// a spray of needles in its texture (red the leaf's shade, green how far out in the cluster, alpha the cut-out). The
// colour is the country's and the season's. Crowns sway in the wind, more the higher they stand, each tree in its own
// time, and light shines through them from behind.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 dark_color : source_color = vec3(0.06, 0.09, 0.04);
uniform vec3 light_color : source_color = vec3(0.24, 0.3, 0.11);
uniform float sway = 0.06;
uniform vec2 wind = vec2(0.35, 0.15);

varying float pick;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	pick = hash(root.xz);
	float up = max(VERTEX.y, 0.0);
	float gust = sin(TIME * 0.9 + pick * 6.28) * 0.7 + sin(TIME * 2.3 + root.x * 0.2 + VERTEX.x) * 0.3;
	vec3 push = inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	VERTEX += push * gust * sway * up * up * 0.04;
}

void fragment() {
	vec4 t = texture(leaves, UV);
	vec3 c = mix(dark_color, light_color, clamp(t.r * (0.6 + 0.5 * t.g), 0.0, 1.0));
	ALBEDO = c * (0.85 + pick * 0.3);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = light_color * 0.5;
}
