// Rivers, lakes and the sea on a battle field: one sheet at the water's level. How deep it is comes from the ground
// behind it, so a ford shows its stones and the sea goes dark, and foam breaks along every shore and round every leg.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.26, 0.33, 0.28);
uniform vec3 deep_color : source_color = vec3(0.04, 0.09, 0.11);
uniform vec3 foam_color : source_color = vec3(0.84, 0.86, 0.82);
uniform float depth_scale = 1.2;
uniform float clear_alpha = 0.5;
uniform float deep_alpha = 0.94;
uniform float foam_reach = 0.22;
uniform float wave_size = 0.07;
// The way the water flows, in metres a second. Still water is zero.
uniform vec2 flow = vec2(0.0, 0.0);

varying vec3 world_pos;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 ripples(vec2 at, float t) {
	vec2 slope = vec2(0.0);
	vec2 dirs[4] = vec2[](vec2(0.96, 0.28), vec2(-0.37, 0.93), vec2(0.66, -0.75), vec2(-0.98, -0.2));
	float freqs[4] = float[](2.1, 3.7, 6.1, 9.3);
	float speeds[4] = float[](1.1, 1.5, 2.1, 2.9);
	for (int i = 0; i < 4; i++) {
		float amp = 1.0 / (1.0 + float(i) * 1.4);
		slope += dirs[i] * amp * cos(dot(dirs[i], at) * freqs[i] + t * speeds[i]);
	}
	return slope;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	vec3 bed = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - bed.y, 0.0);
	float deep = 1.0 - exp(-depth / depth_scale);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 drift = world_pos.xz - flow * TIME;
	float ripple = noise(drift * 0.8 + vec2(TIME * 0.11, TIME * 0.05)) * 0.6 + noise(drift * 2.3 - TIME * 0.17) * 0.4;
	float reach = foam_reach * (0.5 + ripple);
	float edge = 1.0 - smoothstep(0.0, reach, depth);
	float pulse = 0.5 + 0.5 * sin(depth * 22.0 - TIME * 2.2 + ripple * 4.0);
	float foam = edge * smoothstep(0.3, 0.75, ripple * 0.6 + pulse * 0.5) * (1.0 - smoothstep(60.0, 260.0, dist));
	foam = max(foam, (1.0 - smoothstep(0.0, 0.04, depth)) * 0.7);
	// Streaks where the river runs fast.
	float streak = smoothstep(0.62, 0.9, noise(vec2(drift.x * 0.6, drift.y * 3.0) + ripple)) * length(flow) * 0.25;
	vec3 water = mix(shallow_color, deep_color, deep);
	ALBEDO = mix(water, foam_color, clamp(foam + streak, 0.0, 1.0));
	ALPHA = clamp(mix(clear_alpha, deep_alpha, deep) + foam * 0.6, 0.0, 1.0);
	ROUGHNESS = mix(0.14, 0.8, foam);
	SPECULAR = 0.35;
	vec2 slope = ripples(world_pos.xz - flow * TIME * 0.5, TIME) * wave_size;
	slope *= 1.0 - smoothstep(40.0, 400.0, dist);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
