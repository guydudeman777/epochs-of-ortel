// A realm's banner, in its arms (Heraldry): the field, and the charge on it in the realm's metal, with a darker border
// and the weave of the cloth, stirring in the air. The cloth's own extent in its model sets where the charge falls, so
// any banner model can wear it.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 field_color : source_color = vec3(0.48, 0.09, 0.08);
uniform vec3 charge_color : source_color = vec3(0.86, 0.72, 0.32);
// Heraldry.Charge: 0 cross, 1 saltire, 2 chevron, 3 pale, 4 fess, 5 bend, 6 quarterly, 7 roundel.
uniform int charge = 0;
// The cloth's left and right in the model's x, and its top and foot in y.
uniform vec4 cloth_box = vec4(-0.5, 0.5, 4.62, 2.0);
uniform float stir = 0.07;

varying vec2 card;

void vertex() {
	card = vec2((VERTEX.x - cloth_box.x) / (cloth_box.y - cloth_box.x), (cloth_box.z - VERTEX.y) / (cloth_box.z - cloth_box.w));
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.37 + origin.z * 0.23;
	float hang = clamp(card.y, 0.0, 1.0);
	VERTEX.z += sin(TIME * 1.6 + phase + card.y * 3.0) * stir * hang + sin(TIME * 2.7 + phase * 2.0 + card.x * 4.0) * stir * 0.4 * hang;
	VERTEX.x += sin(TIME * 1.1 + phase) * stir * 0.4 * hang * hang;
}

float band(float d, float width) {
	return 1.0 - smoothstep(width - 0.01, width + 0.01, abs(d));
}

void fragment() {
	vec2 uv = card;
	// The arms sit in the upper part; the tails below are field.
	vec2 p = vec2(uv.x - 0.5, (uv.y - 0.42) * 1.6);
	float mask = 0.0;
	if (charge == 0) {
		mask = max(band(p.x, 0.1), band(p.y, 0.1));
	} else if (charge == 1) {
		mask = max(band(p.x - p.y * 0.6, 0.1), band(p.x + p.y * 0.6, 0.1));
	} else if (charge == 2) {
		mask = band(p.y + abs(p.x) * 1.1 - 0.05, 0.11);
	} else if (charge == 3) {
		mask = band(p.x, 0.17);
	} else if (charge == 4) {
		mask = band(p.y, 0.14);
	} else if (charge == 5) {
		mask = band(p.x + p.y * 0.55, 0.13);
	} else if (charge == 6) {
		mask = step(0.0, p.x * p.y);
	} else {
		mask = 1.0 - smoothstep(0.21, 0.23, length(p));
	}
	mask *= step(uv.y, 0.92);
	vec3 color = mix(field_color, charge_color, mask);
	// A border a shade darker, and the weave.
	float border = max(1.0 - smoothstep(0.03, 0.05, min(uv.x, 1.0 - uv.x)), 1.0 - smoothstep(0.02, 0.04, uv.y));
	color *= 1.0 - border * 0.35;
	float weave = 0.94 + 0.06 * sin(uv.x * 420.0) * sin(uv.y * 900.0);
	ALBEDO = color * weave;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = color * 0.3;
}
