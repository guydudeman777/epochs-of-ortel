// Grass, wheat and reeds on a battle field: crossed cards of many blades from tools/art/build_field.py, one MultiMesh
// each. The texture holds each blade's shade in red, how far up the blade a pixel is in green, a head of grain in blue
// and the blade's cut-out in alpha; the colours here are the country's. Blades bend with the wind from the root, are
// lit as the ground under them is, and shrink into the ground before the edge of where they are drawn.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D blades : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 root_color : source_color = vec3(0.1, 0.12, 0.05);
uniform vec3 tip_color : source_color = vec3(0.32, 0.36, 0.15);
uniform vec3 dry_color : source_color = vec3(0.46, 0.4, 0.22);
uniform vec3 head_color : source_color = vec3(0.62, 0.52, 0.28);
uniform float dry = 0.2;
uniform float reach = 75.0;
uniform vec2 wind = vec2(0.35, 0.15);
uniform float sway = 0.12;

varying float pick;
varying float dist;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	pick = hash(root.xz);
	dist = length(root - CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(reach * 0.65, reach, dist);
	VERTEX *= keep;
	float rise = 1.0 - UV.y;
	float gust = sin(TIME * 1.6 + root.x * 0.3 + root.z * 0.22) * 0.65 + sin(TIME * 2.9 + root.z * 0.45 + root.x * 0.1) * 0.35;
	vec3 push = (inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y)) * gust * sway * rise * rise;
	VERTEX += push;
	NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec4 t = texture(blades, UV);
	vec3 tip = mix(tip_color, dry_color, clamp(dry + (pick - 0.5) * 0.4, 0.0, 1.0));
	vec3 c = mix(root_color, tip, t.g) * (0.6 + 0.55 * t.r);
	c = mix(c, head_color * (0.7 + 0.4 * t.r), t.b);
	ALBEDO = c * (0.88 + pick * 0.24);
	// The foot of the card melts into the ground rather than standing on it in a line.
	ALPHA = t.a * smoothstep(0.0, 0.16, 1.0 - UV.y + (t.r - 0.5) * 0.12);
	// Far off, the thin blades thin out in the mip maps, so less is cut away there.
	ALPHA_SCISSOR_THRESHOLD = mix(0.5, 0.12, smoothstep(4.0, 45.0, dist));
	ROUGHNESS = 0.92;
	BACKLIGHT = tip * 0.35 * t.g;
}
