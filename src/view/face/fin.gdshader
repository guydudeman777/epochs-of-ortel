shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Fins and gill flaps. UV.x runs from where the part grows out of the skin (0) to its free edge (1), and a
// UV.y outside 0..1 marks a bony ray, drawn solid. (glTF flips V, so a ray's 2 arrives as -1.) The web between rays fades towards the rim and lets light through.

uniform vec4 root_color : source_color = vec4(0.4, 0.55, 0.6, 1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.85, 0.95, 0.55);
uniform vec3 ray_color : source_color = vec3(0.3, 0.42, 0.48);
// How many faint streaks run out across the web, following the rays.
uniform float streaks = 6.0;

void fragment() {
	if (UV.y > 1.5 || UV.y < -0.5) {
		ALBEDO = ray_color;
		ROUGHNESS = 0.35;
	} else {
		float f = smoothstep(0.0, 1.0, UV.x);
		vec4 colour = mix(root_color, rim_color, f);
		float streak = 0.5 + 0.5 * cos(UV.y * streaks * 6.2832);
		colour.rgb *= 1.0 - 0.12 * streak * f;
		// A thin bright lip at the very edge.
		colour.rgb += vec3(0.08) * smoothstep(0.9, 1.0, UV.x);
		ALBEDO = colour.rgb;
		ALPHA = colour.a;
		ROUGHNESS = 0.3;
		BACKLIGHT = rim_color.rgb * 0.5 * f;
	}
	SPECULAR = 0.55;
}
