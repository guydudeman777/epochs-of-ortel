shader_type spatial;
// Skin. A face's second UV holds bits saying which garments cover it, so skin under what a person
// is wearing is never drawn and can never poke through.

uniform sampler2D map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness_amount = 0.58;
uniform float specular_amount = 0.42;
uniform float scatter = 0.3;
uniform int hidden_bits = 0;
// 0 for smooth skin, 1 for a fish's overlapping scales. scale_map holds their rims in red, and in blue the
// slits where a nose would be. Green marks lips, which lose their colour.
uniform float scales = 0.0;
// Its alpha falls to a half over the scalp, where the skin textures paint stubble. A scaled skin is bald, so
// there it takes the colour of the texture at bare_uv, a clean patch of forehead.
uniform sampler2D scale_map : hint_default_black, filter_linear_mipmap_anisotropic;
uniform vec2 bare_uv = vec2(0.5);

void fragment() {
	if ((int(UV2.x) & hidden_bits) != 0) {
		discard;
	}
	ALBEDO = texture(map, UV).rgb * tint;
	if (scales > 0.0) {
		vec4 marks = texture(scale_map, UV);
		float scalp = clamp((1.0 - marks.a) * 2.0, 0.0, 1.0) * scales;
		ALBEDO = mix(ALBEDO, textureLod(map, bare_uv, 4.0).rgb * tint, scalp);
		ALBEDO *= mix(1.0, 0.8, marks.r * scales);
		ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.3, 0.59, 0.11))) * tint * 1.25, marks.g * scales);
		ALBEDO = mix(ALBEDO, tint * 0.1, marks.b * scales);
	}
	ROUGHNESS = roughness_amount - scales * 0.2;
	SPECULAR = specular_amount;
	SSS_STRENGTH = scatter;
}
