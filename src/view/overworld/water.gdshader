// The sea, lakes and rivers of the overworld: one sheet at the water level. How deep the water is comes from the depth
// of the ground behind it, so shallows show the bed, deep water goes dark, and foam breaks along every shore.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.2, 0.34, 0.33);
uniform vec3 deep_color : source_color = vec3(0.045, 0.1, 0.13);
uniform vec3 foam_color : source_color = vec3(0.82, 0.84, 0.8);
// Depth over which the water goes from clear to dark.
uniform float depth_scale = 3.0;
uniform float clear_alpha = 0.35;
uniform float deep_alpha = 0.93;
// Depth the foam reaches out to from the shore.
uniform float foam_reach = 0.7;
uniform float wave_size = 0.12;

varying vec3 world_pos;

// A hash with no sine in it, so it holds up far from the origin.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The slope of a few long swells running different ways, which is smooth everywhere.
vec2 swell(vec2 at, float t) {
	vec2 slope = vec2(0.0);
	vec2 dirs[4] = vec2[](vec2(0.96, 0.28), vec2(-0.37, 0.93), vec2(0.66, -0.75), vec2(-0.98, -0.2));
	float freqs[4] = float[](0.55, 0.9, 1.6, 2.7);
	float speeds[4] = float[](0.9, 1.1, 1.5, 2.0);
	for (int i = 0; i < 4; i++) {
		float amp = 1.0 / (1.0 + float(i));
		slope += dirs[i] * amp * cos(dot(dirs[i], at) * freqs[i] + t * speeds[i]);
	}
	return slope;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
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
	vec2 flow = world_pos.xz * 0.35 + vec2(TIME * 0.15, TIME * 0.07);
	float ripple = noise(flow) * 0.6 + noise(flow * 2.7 - TIME * 0.2) * 0.4;
	// Foam: a broken band along the shore that pulses in and out.
	float reach = foam_reach * (0.55 + ripple * 0.9);
	float edge = 1.0 - smoothstep(0.0, reach, depth);
	float pulse = 0.5 + 0.5 * sin(depth * 9.0 - TIME * 1.6 + ripple * 3.0);
	float foam = edge * smoothstep(0.35, 0.75, ripple * 0.6 + pulse * 0.5) * (1.0 - smoothstep(250.0, 700.0, dist));
	foam = max(foam, (1.0 - smoothstep(0.0, 0.12, depth)) * 0.8);
	vec3 water = mix(shallow_color, deep_color, deep);
	ALBEDO = mix(water, foam_color, foam);
	ALPHA = clamp(mix(clear_alpha, deep_alpha, deep) + foam * 0.6, 0.0, 1.0);
	ROUGHNESS = mix(0.1, 0.85, foam);
	SPECULAR = 0.55;
	// Small slopes for the light to catch, fading with distance so the open sea does not shimmer from high up.
	vec2 slope = swell(world_pos.xz, TIME) * wave_size;
	slope *= 1.0 - smoothstep(120.0, 600.0, dist);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
