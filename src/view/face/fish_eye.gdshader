shader_type spatial;
// A fish's eye: dark all over, no white, with a deep tint of the sea in it and two bright glints that
// always face the viewer, one big and one small, which make it soft rather than empty.

// The human eye texture, read only for where its cornea shell is see-through.
uniform sampler2D map : source_color, filter_linear_mipmap;
uniform vec3 dark : source_color = vec3(0.01, 0.018, 0.03);
// Lighter low in the eye, as light comes through it.
uniform vec3 deep : source_color = vec3(0.05, 0.11, 0.16);
// Where each glint sits, as the view-space direction the eye's surface faces there, and how wide it is.
uniform vec2 glint_big = vec2(-0.3, 0.32);
uniform float glint_big_size = 0.25;
uniform vec2 glint_small = vec2(0.28, -0.26);
uniform float glint_small_size = 0.11;

float glint(vec2 facing, vec2 at, float size) {
	return 1.0 - smoothstep(size * 0.75, size, distance(facing, at));
}

void fragment() {
	// The eye's surface facing straight at the viewer has a normal of (0, 0, 1) in view space.
	vec2 facing = NORMAL.xy;
	vec3 colour = mix(dark, deep, smoothstep(0.1, -0.6, facing.y) * smoothstep(0.9, 0.3, length(facing)));
	float shine = max(glint(facing, glint_big, glint_big_size), glint(facing, glint_small, glint_small_size));
	ALBEDO = mix(colour, vec3(1.0), shine);
	EMISSION = vec3(0.9) * shine;
	ALPHA = texture(map, UV).a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
