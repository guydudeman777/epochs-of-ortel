// An open flame: a card that always turns to the camera but stays upright, drawn as a tongue of fire that licks and
// sways. Every flame in a town is one instance of one MultiMesh (TownLights). INSTANCE_CUSTOM: x its own phase, y how
// lively it is, z how red (a forge is whiter, a torch redder).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform float brightness = 2.4;

varying vec4 custom;
varying vec2 card;

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

void vertex() {
	custom = INSTANCE_CUSTOM;
	card = UV;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 side = INV_VIEW_MATRIX[0].xyz;
	side = normalize(vec3(side.x, 0.0, side.z) + vec3(0.0001));
	// The quad's middle is at its foot, so a flame stands on its mark and grows up from it.
	vec3 world = origin + side * VERTEX.x * size + vec3(0.0, (VERTEX.y + 0.5) * size, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float t = TIME * (1.6 + custom.y) + custom.x * 17.0;
	// x from -1 to 1 across, y from 0 at the foot to 1 at the tip.
	vec2 p = vec2(card.x * 2.0 - 1.0, 1.0 - card.y);
	// The tongue sways more the higher it reaches, and is torn by noise rising through it.
	float sway = (noise(vec2(t * 0.9, custom.x * 9.0)) - 0.5) * 0.5 * p.y * p.y;
	float tear = noise(vec2(p.x * 3.0, p.y * 4.0 - t * 2.6)) * 0.55 + noise(vec2(p.x * 7.0, p.y * 9.0 - t * 4.1)) * 0.3;
	float x = p.x - sway;
	// Wide and round at the foot, drawn to a point at the tip.
	float width = 0.62 * pow(max(1.0 - p.y, 0.0), 0.75) * (0.75 + 0.25 * sin(p.y * 3.14));
	float body = 1.0 - smoothstep(width * 0.55, width, abs(x));
	body *= smoothstep(0.0, 0.12, p.y);
	body *= smoothstep(0.0, 0.25, tear - p.y * 0.62 + 0.18);
	float core = (1.0 - smoothstep(0.0, width * 0.55, abs(x))) * (1.0 - smoothstep(0.1, 0.55, p.y));
	vec3 red = mix(vec3(0.9, 0.22, 0.04), vec3(0.75, 0.1, 0.02), custom.z);
	vec3 orange = vec3(1.0, 0.5, 0.12);
	vec3 yellow = vec3(1.0, 0.85, 0.45);
	vec3 color = mix(red, orange, body);
	color = mix(color, yellow, core * (1.0 - custom.z * 0.5));
	float alpha = body * (0.75 + core * 0.25);
	ALBEDO = color * brightness;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
