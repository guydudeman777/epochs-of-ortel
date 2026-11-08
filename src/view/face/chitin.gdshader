shader_type spatial;
// Chitin. The kheth build writes into each vertex's colour how open the shell is there (red: 0 deep in a seam,
// 1 on a plate's face), how far round to the belly (green) and the people's markings (blue). The shell is
// lacquered, faintly pitted and mottled, and shows a thin sheen of another colour at grazing angles.
// compound draws the many facets of an insect's eye instead.

uniform vec3 dorsal : source_color = vec3(0.24, 0.13, 0.05);
uniform vec3 ventral : source_color = vec3(0.55, 0.38, 0.18);
uniform vec3 accent : source_color = vec3(0.08, 0.05, 0.03);
uniform vec3 sheen : source_color = vec3(0.3, 0.5, 0.2);
uniform float compound = 0.0;
uniform float facets = 70.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Distance to the edge of the nearest hexagonal facet, and that facet's own random number.
vec2 hex_cell(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = p - g;
	vec2 q = abs(g);
	float edge = 0.5 - max(dot(q, normalize(r)), q.x);
	return vec2(edge, hash(floor(id * 10.0)));
}

void fragment() {
	float open_ = COLOR.r;
	float belly = COLOR.g;
	float mark = COLOR.b;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	if (compound > 0.5) {
		vec2 cell = hex_cell(UV * facets);
		float wall = 1.0 - smoothstep(0.0, 0.09, cell.x);
		vec3 eye = mix(accent * 0.6, dorsal * 0.5 + vec3(0.06, 0.02, 0.01), cell.y * 0.5);
		ALBEDO = mix(eye, vec3(0.01), wall * 0.8);
		ROUGHNESS = 0.08 + wall * 0.5;
		SPECULAR = 0.8;
		ALBEDO += sheen * rim * 0.5;
	} else {
		float mottle = noise(UV * 9.0) * 0.6 + noise(UV * 31.0) * 0.4;
		float pits = noise(UV * 140.0);
		vec3 base = mix(dorsal, ventral, smoothstep(0.25, 0.85, belly));
		base = mix(base, accent, clamp(mark, 0.0, 1.0));
		base *= 0.72 + 0.5 * mottle;
		// Darker where the shell is thickest, across the back.
		base *= mix(0.75, 1.0, smoothstep(0.0, 0.6, belly));
		base *= mix(0.18, 1.0, smoothstep(0.3, 1.0, open_));
		ALBEDO = base + sheen * rim * 0.22 * open_;
		ROUGHNESS = clamp(0.42 + 0.3 * pits + 0.3 * (1.0 - open_), 0.0, 1.0);
		SPECULAR = 0.45;
		CLEARCOAT = 0.35 * open_;
		CLEARCOAT_ROUGHNESS = 0.35;
	}
}
