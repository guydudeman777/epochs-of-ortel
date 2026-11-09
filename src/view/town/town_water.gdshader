// The sea, a lake or a river by a town you walk in, seen from a walker's height. One sheet at the water's level that
// heaves gently; how deep it is comes from the ground behind it, so the shallows show the bed, deep water goes dark,
// and foam breaks along the strand and against the quay. Bright where it faces the sky, as water does at a low angle,
// and it catches the town's lights at night.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.3, 0.29);
uniform vec3 deep_color : source_color = vec3(0.03, 0.08, 0.1);
uniform vec3 foam_color : source_color = vec3(0.85, 0.87, 0.84);
uniform vec3 sky_color : source_color = vec3(0.55, 0.62, 0.7);
// Depth over which the water goes from clear to dark.
uniform float depth_scale = 2.2;
uniform float foam_reach = 0.45;
uniform float wave_height = 0.08;
uniform float night = 0.0;

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

// Long swells running different ways: their height and their slope.
vec3 swell(vec2 at, float t) {
	vec3 out_v = vec3(0.0);
	vec2 dirs[4] = vec2[](vec2(0.96, 0.28), vec2(-0.37, 0.93), vec2(0.66, -0.75), vec2(-0.98, -0.2));
	float freqs[4] = float[](0.35, 0.6, 1.1, 2.3);
	float speeds[4] = float[](0.7, 0.9, 1.3, 1.9);
	for (int i = 0; i < 4; i++) {
		float amp = 1.0 / (1.0 + float(i) * 1.5);
		float phase = dot(dirs[i], at) * freqs[i] + t * speeds[i];
		out_v.x += amp * sin(phase);
		out_v.yz += dirs[i] * amp * freqs[i] * cos(phase);
	}
	return out_v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float near = 1.0 - smoothstep(60.0, 220.0, length(world_pos - CAMERA_POSITION_WORLD));
	VERTEX.y += swell(world_pos.xz, TIME).x * wave_height * near;
}

void fragment() {
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	vec3 bed = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - bed.y, 0.0);
	float deep = 1.0 - exp(-depth / depth_scale);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 flow = world_pos.xz * 0.5 + vec2(TIME * 0.12, TIME * 0.05);
	float ripple = noise(flow) * 0.6 + noise(flow * 2.9 - TIME * 0.25) * 0.4;
	// Foam: a broken band where the water meets the strand or the quay, washing in and out.
	float reach = foam_reach * (0.55 + ripple * 0.9);
	float edge = 1.0 - smoothstep(0.0, reach, depth);
	float pulse = 0.5 + 0.5 * sin(depth * 10.0 - TIME * 1.8 + ripple * 3.0);
	float foam = edge * smoothstep(0.35, 0.75, ripple * 0.6 + pulse * 0.5);
	foam = max(foam, (1.0 - smoothstep(0.0, 0.08, depth)) * 0.7);
	// The bed seen through the shallows, bent a little by the ripples.
	vec3 slope_v = swell(world_pos.xz, TIME);
	vec2 bend = slope_v.yz * 0.004 * (1.0 - deep);
	vec3 seen = textureLod(screen_texture, SCREEN_UV + bend, 0.0).rgb;
	vec3 water = mix(shallow_color, deep_color, deep);
	water = mix(seen * shallow_color * 2.2, water, smoothstep(0.0, 0.9, deep));
	// The sky in the water at a low angle, darker by night.
	vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec2 slope = slope_v.yz * wave_height + (vec2(ripple) - 0.5) * 0.08;
	slope *= 1.0 - smoothstep(80.0, 400.0, dist) * 0.7;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	float facing = pow(1.0 - max(dot(-view_dir, n), 0.0), 4.0);
	water = mix(water, sky_color * mix(1.0, 0.12, night), facing * 0.7);
	ALBEDO = mix(water, foam_color * mix(1.0, 0.3, night), foam);
	ALPHA = 1.0;
	ROUGHNESS = mix(0.06, 0.8, foam);
	SPECULAR = 0.6;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
