shader_type spatial;
render_mode cull_disabled;
// MakeHuman and grown hair, brows and lashes. The texture's detail is kept and its colour replaced,
// so hair colour can be inherited rather than tied to the texture it was painted in. Light follows the
// strands: a bright band across them and a softer, tinted one below it, instead of a surface's shine.

uniform sampler2D map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color : source_color = vec3(0.1, 0.07, 0.05);
uniform float average = 0.2;
uniform float specular_amount = 0.3;
uniform float cutoff = 0.4;
uniform sampler2D strand_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform int strand_axis = 1;
uniform float strand_tiles_across = 34.0;
uniform float strand_tiles_along = 3.0;
uniform float strand_strength = 0.55;
uniform float sheen = 0.035;

varying vec3 strand_dir;
varying float strand_shift;

void fragment() {
	vec4 tex = texture(map, UV);
	float brightness = dot(tex.rgb, vec3(0.3, 0.59, 0.11));
	float relative = brightness / average;
	// Fine strands the paint is too soft to show, running the way the paint's own strands do.
	vec2 strand_uv = strand_axis == 1 ? vec2(UV.x * strand_tiles_across, UV.y * strand_tiles_along) : vec2(UV.y * strand_tiles_across, UV.x * strand_tiles_along);
	float strand = texture(strand_map, strand_uv).r;
	ALBEDO = color * clamp(relative * relative, 0.3, 2.6) * mix(1.0, strand * 1.6, strand_strength);
	ROUGHNESS = 0.42 + strand * 0.25;
	SPECULAR = specular_amount;
	// The direction the strands run in. The mesh's own tangents are smooth across its faces.
	strand_dir = normalize(strand_axis == 1 ? BINORMAL : TANGENT);
	strand_shift = (strand - 0.6) * 0.5;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	ALPHA_ANTIALIASING_EDGE = 0.2;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(map, 0));
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.45) / 1.45, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_way = normalize(LIGHT + VIEW);
	vec3 first = normalize(strand_dir + NORMAL * (strand_shift + 0.08));
	vec3 second = normalize(strand_dir + NORMAL * (strand_shift - 0.12));
	float d1 = dot(first, half_way);
	float d2 = dot(second, half_way);
	float band = pow(sqrt(max(1.0 - d1 * d1, 0.0)), 220.0) * sheen;
	float glow = pow(sqrt(max(1.0 - d2 * d2, 0.0)), 60.0) * sheen * 0.25;
	// Dark hair has a smaller, duller shine, or it greys over.
	float tone = clamp(dot(color, vec3(0.3, 0.59, 0.11)) * 5.0 + 0.3, 0.3, 1.0);
	vec3 tint = mix(vec3(1.0), normalize(color + vec3(0.02)) * 1.7, 0.7);
	SPECULAR_LIGHT += (band + glow) * tone * tint * wrap * ATTENUATION * LIGHT_COLOR;
}
