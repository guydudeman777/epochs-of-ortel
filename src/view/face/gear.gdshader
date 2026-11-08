shader_type spatial;
render_mode cull_disabled;
// Tiled cloth, leather or mail. UV is the body's shared layout, scaled so one tile covers the same
// size everywhere. With a badge set, it paints a cross from the wearer's chest coordinates in UV2,
// so a realm's colours need no separate texture. Without a badge, UV2.x holds bits saying which garments
// further out cover the face, as on the skin, so an inner layer never pokes through an outer one.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color : source_color = vec3(0.5);
uniform float tile = 10.0;
uniform float metal = 0.0;
uniform float rough = 0.85;
uniform float normal_strength = 1.0;
uniform int hidden_bits = 0;
uniform bool badge = false;
uniform vec3 badge_color : source_color = vec3(0.7, 0.65, 0.5);
uniform float badge_half_width = 0.028;
uniform vec2 badge_upright = vec2(0.13, 0.5);
uniform vec2 badge_across = vec2(0.33, 0.39);
uniform float badge_reach = 0.13;

void fragment() {
	if (!badge && (int(UV2.x) & hidden_bits) != 0) {
		discard;
	}
	vec2 uv = UV * tile;
	vec3 tint = color;
	if (badge) {
		// glTF stores V flipped, and this V is a height.
		float across_body = abs(UV2.x);
		float height = 1.0 - UV2.y;
		bool upright = across_body < badge_half_width && height > badge_upright.x && height < badge_upright.y;
		bool bar = across_body < badge_reach && height > badge_across.x && height < badge_across.y;
		if (upright || bar) {
			tint = badge_color;
		}
	}
	ALBEDO = texture(albedo_map, uv).rgb * tint;
	METALLIC = metal;
	ROUGHNESS = rough;
	NORMAL_MAP = texture(normal_map, uv).xyz;
	NORMAL_MAP_DEPTH = normal_strength;
}
