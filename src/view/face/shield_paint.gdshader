shader_type spatial;
render_mode cull_disabled;
// A realm's arms painted on the boards of a shield: the field, the charge in its metal, the grain of the wood
// showing through, and the knocks of use. UV runs from -1 to 1 across the face, up being up.

uniform vec3 field : source_color = vec3(0.48, 0.09, 0.08);
uniform vec3 metal : source_color = vec3(0.86, 0.72, 0.32);
// Heraldry.Charge: cross, saltire, chevron, pale, fess, bend, quarterly, roundel.
uniform int charge = 0;
uniform float wear : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

bool on_charge(vec2 d) {
	float w = 0.17;
	if (charge == 0) {
		return abs(d.x) < w || abs(d.y - 0.1) < w;
	} else if (charge == 1) {
		return abs(d.x - d.y) < w * 1.2 || abs(d.x + d.y) < w * 1.2;
	} else if (charge == 2) {
		float v = d.y + abs(d.x) * 0.9;
		return abs(v + 0.05) < w * 1.2;
	} else if (charge == 3) {
		return abs(d.x) < 0.3;
	} else if (charge == 4) {
		return abs(d.y) < 0.27;
	} else if (charge == 5) {
		return abs(d.x + d.y) < w * 1.35;
	} else if (charge == 6) {
		return (d.x > 0.0) != (d.y > 0.0);
	}
	return length(d) < 0.42;
}

void fragment() {
	vec2 d = UV;
	// Boards running up the shield, each a little different.
	float board = floor((d.x + 1.0) * 3.5);
	float grain = noise(vec2(d.x * 40.0 + board * 7.0, d.y * 3.0)) * 0.6 + noise(vec2(d.x * 120.0, d.y * 9.0)) * 0.4;
	vec3 colour = on_charge(d) ? metal : field;
	colour *= 0.82 + grain * 0.3 + hash(vec2(board, 1.0)) * 0.08;
	// Gaps between the boards.
	float join = abs(fract((d.x + 1.0) * 3.5) - 0.5);
	colour *= mix(0.6, 1.0, smoothstep(0.47, 0.44, join));
	// Paint knocked off at the rim and in nicks, showing the wood.
	float r = length(d);
	float chip = smoothstep(0.62, 0.8, noise(d * 9.0) + r * 0.35 * wear + wear * 0.15);
	vec3 wood = vec3(0.36, 0.25, 0.15) * (0.7 + grain * 0.5);
	colour = mix(colour, wood, chip * 0.9);
	float scratch = smoothstep(0.985, 1.0, noise(vec2(d.x * 4.0 + d.y * 30.0, d.y * 4.0 - d.x * 30.0)));
	colour = mix(colour, wood * 1.2, scratch * wear);
	ALBEDO = colour;
	ROUGHNESS = mix(0.62, 0.85, chip);
	SPECULAR = 0.35;
}
