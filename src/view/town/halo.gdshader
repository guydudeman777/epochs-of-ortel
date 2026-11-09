// The soft glow round a lamp or a fire in night air: a card facing the camera, brightest at its middle, fading where it
// meets a wall or the ground so it never shows a hard edge. All halos in a town are one MultiMesh (TownLights).
// INSTANCE_CUSTOM: rgb the light's colour, a how strong.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float strength = 0.7;
// Metres over which a halo fades out against what stands behind it.
uniform float soft = 0.6;

varying vec4 custom;
varying vec2 card;

void vertex() {
	custom = INSTANCE_CUSTOM;
	card = UV;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 view = (VIEW_MATRIX * vec4(origin, 1.0)).xyz;
	// Pulled a little towards the camera, so the lamp's own glass does not cut it.
	view += normalize(-view) * min(size * 0.3, 0.6);
	VERTEX = view + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = card * 2.0 - 1.0;
	float r = length(p);
	float glow = exp(-r * r * 5.0) * 0.8 + exp(-r * 9.0) * 0.6;
	glow *= 1.0 - smoothstep(0.85, 1.0, r);
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	float gap = VERTEX.z - behind.z;
	glow *= clamp(gap / soft, 0.0, 1.0);
	ALBEDO = custom.rgb * glow * strength * custom.a;
	ALPHA = 1.0;
}
