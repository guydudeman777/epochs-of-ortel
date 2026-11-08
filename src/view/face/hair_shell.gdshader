shader_type spatial;
render_mode cull_back;
// Hair in layers. The mesh is drawn once per layer, each further out and keeping fewer hairs from the tile, so
// hairlines thin out and silhouettes are made of hair tips. The second UV holds the hair's height in metres, and in
// its V how much hair grows here, flipped by glTF on export.

uniform sampler2D tile : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color : source_color = vec3(0.1, 0.07, 0.05);
uniform float layer = 0.0; // 0 at the skin, 1 at the tips.
uniform float sag = 0.0; // How far the tips hang, for each metre of height.
uniform float comb = 0.0; // How far along the strands the tile slides from root to tip, so hairs lean.
uniform float curly = 0.0;
uniform float lump = 0.2; // How much hairs bunch together.
uniform float root = 0.4; // Brightness at the skin. Tips are 1.
uniform float sheen = 0.03;
uniform float bump = 3.5;
uniform float far_lod = 1.8;

varying float grows;
varying vec3 strand_dir;

void vertex() {
	float height = UV2.x;
	// Curly hair bunches into soft lumps, which show in its outline.
	height *= 1.0 + curly * (textureLod(tile, UV * 0.27 + vec2(0.31, 0.77), 2.0).b - 0.5) * lump * 1.6;
	VERTEX += NORMAL * height * layer;
	VERTEX.y -= sag * height * layer * layer;
	grows = 1.0 - UV2.y;
}

void fragment() {
	// Curls differ from layer to layer, where straight hairs carry on through them.
	vec2 uv = UV + vec2(curly * fract(layer * 7.31), comb * layer + curly * fract(layer * 3.17));
	// Hairs stay crisp at a distance: the blurrier mip levels would lose them.
	float sharpest = min(textureQueryLod(tile, uv).y, far_lod);
	vec4 here = textureLod(tile, uv, sharpest);
	float slow = texture(tile, UV * 0.27 + vec2(0.31, 0.77)).b;
	float hairs = here.r;
	float reach = mix(hairs, slow, lump * layer);
	// Where little grows the hairs are short and few. Which hairs survive is settled once, not layer by layer, or
	// many layers together would fill the gaps in again.
	reach += (grows - 1.0) * 0.6;
	vec2 root_uv = UV * mix(1.0, 4.5, curly);
	float rooted = textureLod(tile, root_uv, min(textureQueryLod(tile, root_uv).y, far_lod)).r;
	float wanted = layer * mix(0.97, 0.62, curly) + 0.015;
	float keep = (reach - wanted) / max(fwidth(reach), 0.002) + 0.5;
	// The innermost layer is solid wherever hair grows thickly, so skin never shows through.
	if (layer <= 0.0) {
		keep = max(keep, (grows - 0.93) * 20.0);
	}
	keep = min(keep, (grows - rooted) / max(fwidth(rooted), 0.002) + 0.5 + step(0.93, grows) * 100.0);
	ALPHA = clamp(keep, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(tile, 0));

	float depth = mix(root, 1.0, pow(layer, 0.7));
	ALBEDO = color * depth * (0.7 + 1.0 * here.g);
	ROUGHNESS = 0.55;
	SPECULAR = 0.25;
	float step_size = 2.0 / float(textureSize(tile, 0).x);
	float rise_u = here.r - texture(tile, uv + vec2(step_size, 0.0)).r;
	float rise_v = here.r - texture(tile, uv + vec2(0.0, step_size)).r;
	NORMAL_MAP = vec3(rise_u * bump + 0.5, rise_v * bump + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	strand_dir = normalize(BINORMAL);
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.4) / 1.4, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * ATTENUATION * LIGHT_COLOR / PI;
	vec3 half_way = normalize(LIGHT + VIEW);
	float along = dot(strand_dir, half_way);
	float band = pow(sqrt(max(1.0 - along * along, 0.0)), 90.0);
	float round_shine = pow(max(dot(NORMAL, half_way), 0.0), 18.0);
	float shine = mix(band, round_shine, curly) * sheen;
	float tone = clamp(dot(color, vec3(0.3, 0.59, 0.11)) * 5.0 + 0.3, 0.3, 1.0);
	vec3 tint = mix(vec3(1.0), normalize(color + vec3(0.02)) * 1.7, 0.7);
	SPECULAR_LIGHT += shine * tone * tint * wrap * ATTENUATION * LIGHT_COLOR;
}
