// A bird on the wing: its wings beat, the further out the more, now and then held still to glide. Gulls pale, crows
// black. INSTANCE_CUSTOM: r its own phase, g 1 for a gull, b its size, a how wide it circles.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, shadows_disabled;

varying float gull;

void vertex() {
	gull = INSTANCE_CUSTOM.g;
	float phase = INSTANCE_CUSTOM.r * 31.0;
	float glide = smoothstep(0.2, 0.6, sin(TIME * 0.4 + phase));
	float beat = sin(TIME * (9.0 + INSTANCE_CUSTOM.r * 4.0) + phase) * (1.0 - glide * 0.85);
	VERTEX.y += beat * abs(VERTEX.x) * 0.9;
}

void fragment() {
	vec3 crow = vec3(0.04, 0.04, 0.05);
	vec3 white = vec3(0.86, 0.86, 0.84);
	ALBEDO = mix(crow, white, gull);
	ROUGHNESS = 0.9;
}
