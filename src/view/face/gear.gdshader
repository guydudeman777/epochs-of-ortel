shader_type spatial;
render_mode cull_disabled;
// Everything worn: cloth, leather, fur, straw, mail, scale and plate, iron and gold. UV is the body's shared
// layout in metres, so one tile covers the same size everywhere. The garment build writes into each vertex's
// colour: red how open it is to the sky (ambient occlusion against the body and itself), green how far it lies
// from an open edge such as a hem or cuff (0 on the edge, 1 at 12 cm or more), blue its height above the ground
// standing (0 to 2 m), and alpha a line it crosses at 0.5 (side seams on cloth, a ridge or hinge on plate).
//
// What it is made of comes as a family; how it has been kept comes as wear (fraying, patches, stains, rust),
// grime (dirt rising from the ground) and trim (an embroidered band along every edge, for dear clothes).
//
// UV2.x holds bits saying which garments further out cover the face, as on the skin, so an inner layer never
// pokes through an outer one. With arms set, UV2 instead holds the wearer's chest coordinates, and the realm's
// charge is painted there in its metal.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color : source_color = vec3(0.5);
uniform float tile = 10.0;
uniform float metal = 0.0;
uniform float rough = 0.85;
uniform float normal_strength = 1.0;
uniform int hidden_bits = 0;
// 0 cloth, 1 leather, 2 plate and plain metal, 3 mail, scale and lamellar, 4 fur, 5 straw, 6 cloth over plates.
uniform int family = 0;
uniform float wear : hint_range(0.0, 1.0) = 0.2;
uniform float grime : hint_range(0.0, 1.0) = 0.2;
uniform float trim : hint_range(0.0, 1.0) = 0.0;
uniform vec3 trim_color : source_color = vec3(0.78, 0.6, 0.24);
// Soft light caught at grazing angles, as wool and velvet do.
uniform float sheen = 0.3;
// Folds hanging down the cloth, 0 for none, 1 for a full skirt's.
uniform float folds = 0.3;
// Plate on a limb is bands lapping each other this long, in metres. 0 for one piece.
uniform float lames = 0.0;
// Whether the line in the vertex alpha shows: stitches on cloth, a ridge on plate.
uniform float seam_line = 1.0;
// A realm's arms on the chest and back.
uniform bool arms = false;
uniform vec3 charge_color : source_color = vec3(0.86, 0.72, 0.32);
// Heraldry.Charge: cross, saltire, chevron, pale, fess, bend, quarterly, roundel.
uniform int charge = 0;
uniform vec2 charge_centre = vec2(0.0, 0.34);
uniform float charge_reach = 0.2;

varying float worn_height;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.13 + 7.1) * 0.28 + noise(p * 4.37 + 3.3) * 0.17;
}

// Whether a point on the chest, in metres, lies on the charge.
bool on_charge(vec2 p) {
	vec2 d = p - charge_centre;
	float r = charge_reach;
	float w = 0.045;
	if (abs(d.x) > r * 1.15 || d.y > r * 1.2 || d.y < -r * 2.2) {
		return charge == 0 && abs(d.x) < w && d.y > -r * 2.6 && d.y < r * 1.2;
	}
	if (charge == 0) {
		return abs(d.x) < w || (abs(d.y) < w && d.y > -r);
	} else if (charge == 1) {
		return (abs(d.x - d.y * 0.8) < w * 1.2 || abs(d.x + d.y * 0.8) < w * 1.2) && d.y > -r * 1.3 && d.y < r;
	} else if (charge == 2) {
		float v = d.y + abs(d.x) * 0.9;
		return abs(v - 0.02) < w * 1.3 && d.y > -r * 1.3;
	} else if (charge == 3) {
		return abs(d.x) < r * 0.36;
	} else if (charge == 4) {
		return abs(d.y) < r * 0.3;
	} else if (charge == 5) {
		return abs(d.x + d.y * 0.85) < w * 1.4 && d.y > -r * 1.4 && d.y < r;
	} else if (charge == 6) {
		return (d.x > 0.0) != (d.y > 0.0) && d.y > -r * 1.6;
	}
	return length(d) < r * 0.48;
}

void vertex() {
	worn_height = COLOR.b * 2.0;
}

void fragment() {
	if (!arms && (int(UV2.x) & hidden_bits) != 0) {
		discard;
	}
	float ao = clamp(COLOR.r, 0.0, 1.0);
	// Metres from the nearest open edge, and across the line the build drew.
	float edge = COLOR.g * 0.12;
	float line = (COLOR.a - 0.5) * 0.2;
	vec2 m = UV;
	bool cloth = family == 0 || family == 4 || family == 5 || family == 6 || family == 7;
	bool soft = family == 0 || family == 6;

	// Netting: knotted cords on the diagonal, and nothing between.
	if (family == 7) {
		vec2 g = abs(fract(vec2(m.x + m.y, m.x - m.y) * 34.0) - 0.5);
		if (min(g.x, g.y) > 0.085 && edge > 0.012) {
			discard;
		}
	}

	// Frayed and ragged hems on worn cloth, low down where a hem drags.
	if (soft && wear > 0.35 && worn_height < 1.05) {
		float rag = fbm(m * vec2(140.0, 140.0)) * (wear - 0.35) * 0.022;
		if (edge < rag) {
			discard;
		}
	}

	vec2 tuv = m * tile;
	vec3 base = texture(albedo_map, tuv).rgb;
	vec3 tex_n = texture(normal_map, tuv).xyz * 2.0 - 1.0;
	tex_n.xy *= normal_strength;
	vec3 tint = color;
	float roughness = rough;
	float metallic = metal;
	float bump_u = 0.0;
	float bump_v = 0.0;

	// Uneven fading and stains, the more the older.
	float blotch = fbm(m * 6.0 + 11.0);
	if (cloth || family == 1) {
		float fade = smoothstep(0.35, 0.85, blotch) * wear * 0.35;
		tint = mix(tint, vec3(dot(tint, vec3(0.33))) * 1.15 + 0.04, fade);
		float stain = smoothstep(0.68, 0.8, fbm(m * 3.1 + 40.0)) * smoothstep(0.25, 0.7, wear);
		tint *= 1.0 - stain * 0.32;
	}

	// Cloth folds: long valleys hanging down, uneven in width, wandering a little, deeper towards the hem. Two
	// waves of different lengths so no two folds match.
	if (soft && folds > 0.0) {
		float wander = fbm(vec2(m.x * 5.0, m.y * 1.6)) * 4.0;
		float phase_a = m.x * 38.0 + wander;
		float phase_b = m.x * 23.0 - wander * 0.6 + 1.7;
		float depth = folds * (0.35 + 0.65 * smoothstep(1.25, 0.35, worn_height)) * (0.6 + 0.4 * noise(vec2(m.x * 6.0, 3.0)));
		bump_u += (cos(phase_a) * 0.6 + cos(phase_b) * 0.4) * depth * 0.32;
		float valley = (0.5 - 0.5 * sin(phase_a)) * (0.5 - 0.5 * sin(phase_b) * 0.6) * depth;
		tint *= 1.0 - valley * 0.16;
		ao *= 1.0 - valley * 0.2;
	}

	// Patches sewn over holes in cheap cloth.
	if (soft && wear > 0.55) {
		vec2 cell = floor(m / 0.24);
		float pick = hash(cell + 3.7);
		if (pick < (wear - 0.55) * 0.5) {
			vec2 local = fract(m / 0.24);
			vec2 size = vec2(0.22, 0.18) + vec2(hash(cell + 1.3), hash(cell + 9.1)) * 0.22;
			vec2 corner = vec2(0.15) + vec2(hash(cell + 5.5), hash(cell + 2.2)) * (0.7 - size);
			vec2 inside = (local - corner) / size;
			if (inside.x > 0.0 && inside.x < 1.0 && inside.y > 0.0 && inside.y < 1.0) {
				float shade = hash(cell + 8.8);
				// Another scrap of cloth, near the same darkness but not the same dye.
				float dark = dot(tint, vec3(0.33));
				vec3 scrap = mix(vec3(0.45, 0.38, 0.28), vec3(0.3, 0.32, 0.3), shade) * (0.45 + dark * 1.1);
				tint = mix(tint, scrap, 0.75);
				vec2 rim = min(inside, 1.0 - inside) * size * 0.24;
				float rim_m = min(rim.x, rim.y);
				if (rim_m < 0.004 && fract((m.x + m.y) * 160.0) < 0.5) {
					tint *= 0.45;
				}
				bump_v += 0.25;
			}
		}
	}

	if (soft) {
		// A turned and stitched hem a finger from every edge.
		float hem = abs(edge - 0.011);
		if (hem < 0.0012 && fract((m.x + m.y) * 150.0) < 0.55) {
			tint *= 0.7;
		}
		if (edge < 0.016) {
			bump_v += 0.2 * smoothstep(0.016, 0.002, edge);
		}
	}

	// Seams down the sides and limbs: a fine groove with stitches either side.
	if (seam_line > 0.0 && (soft || family == 1)) {
		float s = abs(line);
		tint *= 1.0 - (1.0 - smoothstep(0.0006, 0.0018, s)) * 0.35 * seam_line;
		if (abs(s - 0.0035) < 0.0007 && fract(m.y * 140.0 + m.x * 20.0) < 0.5) {
			tint *= 0.78;
		}
	}

	// Leather: darker burnished edges, stitching, scuffs and cracks.
	if (family == 1) {
		tint *= mix(0.7, 1.0, smoothstep(0.0, 0.02, edge));
		if (abs(edge - 0.006) < 0.0009 && fract((m.x + m.y) * 110.0) < 0.6) {
			tint = mix(tint, vec3(0.55, 0.48, 0.36), 0.6);
		}
		float scuff = smoothstep(0.62, 0.78, fbm(m * 22.0 + 3.0)) * wear;
		tint = mix(tint, tint * 1.45 + 0.03, scuff * 0.6);
		roughness = mix(roughness, 0.9, scuff);
		float crack = 1.0 - smoothstep(0.0, 0.05, abs(fbm(m * 30.0) - 0.5));
		tint *= 1.0 - crack * wear * 0.35;
		roughness = mix(roughness - 0.1, roughness, wear);
	}

	// Embroidered bands along every edge of dear clothes: a gilt line each side and a lattice of small lozenges.
	if (trim > 0.0 && (soft || family == 1)) {
		float inner = 0.034;
		if (edge > 0.004 && edge < inner) {
			vec2 lattice = abs(fract(m * vec2(55.0, 55.0)) - 0.5);
			float lozenge = step(lattice.x + lattice.y, 0.28);
			vec3 band = mix(trim_color * 0.55 + tint * 0.25, trim_color * 1.15, lozenge);
			float rim = min(abs(edge - 0.0055), abs(edge - (inner - 0.0015)));
			if (rim < 0.0012) {
				band = trim_color * 1.25;
			}
			tint = mix(tint, band, trim);
			roughness = mix(roughness, 0.45, lozenge * trim);
			metallic = mix(metallic, 0.35, lozenge * trim);
			bump_v += 0.15 * trim;
		}
	}

	// Plate and plain metal: struck and filed, bright on rolled edges, dark in hollows, rusting when let go.
	if (family == 2) {
		float dents = fbm(m * 18.0);
		bump_u += (dents - 0.5) * 0.25;
		bump_v += (fbm(m * 18.0 + 5.0) - 0.5) * 0.25;
		if (lames > 0.0) {
			float along = fract(m.y / lames);
			// Each lame laps over the next: a slope and a dark gap where they meet.
			bump_v += (along - 0.5) * 0.9;
			float gap = 1.0 - smoothstep(0.0, 0.05, min(along, 1.0 - along));
			tint *= 1.0 - gap * 0.55;
			ao *= 1.0 - gap * 0.4;
			if (abs(line) < 0.012 && min(along, 1.0 - along) < 0.18 && min(along, 1.0 - along) > 0.08) {
				tint *= 0.6;
			}
		}
		if (seam_line > 0.0) {
			float ridge = 1.0 - smoothstep(0.0, 0.01, abs(line));
			bump_u += sign(line) * ridge * 0.8 * seam_line;
		}
		float rolled = 1.0 - smoothstep(0.0, 0.012, edge);
		tint *= 1.0 + rolled * 0.35;
		roughness = mix(roughness, roughness * 0.55, rolled);
		float polish = 1.0 - wear;
		roughness = mix(roughness + 0.18, roughness, polish);
		// Fine filing marks run round the piece.
		roughness += (noise(vec2(m.x * 4.0, m.y * 900.0)) - 0.5) * 0.08;
		float rust = smoothstep(0.55, 0.85, fbm(m * 7.0 + 2.0) + (1.0 - ao) * 0.6) * smoothstep(0.3, 0.9, wear);
		tint = mix(tint, vec3(0.3, 0.15, 0.07), rust);
		metallic = mix(metallic, 0.15, rust);
		roughness = mix(roughness, 0.92, rust);
	}

	// Mail, scale and lamellar: dark between the rings, greasy and rusting when let go.
	if (family == 3) {
		float rust = smoothstep(0.5, 0.85, fbm(m * 9.0 + 2.0) + (1.0 - ao) * 0.5) * smoothstep(0.25, 0.9, wear);
		tint = mix(tint, vec3(0.32, 0.16, 0.08), rust * 0.75);
		metallic = mix(metallic, 0.2, rust);
		roughness = mix(roughness, 0.85, rust);
		roughness = mix(roughness, roughness + 0.12, wear);
	}

	// Fur: lighter tips catching the light.
	if (family == 4) {
		tint *= 0.85 + base.r * 0.3;
	}

	// Dirt splashed up from the road, thickest at the feet.
	float splash = fbm(m * 11.0 + 5.0);
	float dirt_line = 0.08 + grime * 0.42 + (splash - 0.5) * 0.25;
	float dirt = smoothstep(dirt_line, dirt_line - 0.3, worn_height) * grime * (0.55 + splash * 0.6);
	dirt += smoothstep(0.74, 0.92, fbm(m * 13.0 + 21.0)) * grime * 0.2;
	dirt = clamp(dirt, 0.0, 0.8);

	vec3 albedo = base * tint;
	// Mud darkens light cloth and dulls dark cloth towards the colour of the road.
	vec3 mud = vec3(0.17, 0.135, 0.095) * (0.75 + base * 0.3);
	albedo = mix(albedo, min(albedo, mud * 1.4) * 0.6 + mud * 0.4, dirt);
	roughness = mix(roughness, 0.95, dirt);
	metallic = mix(metallic, 0.0, dirt * 0.8);

	// The realm's colours on a surcoat: the charge in its metal on the chest and back.
	if (arms) {
		vec2 chest = vec2(UV2.x, 1.0 - UV2.y);
		if (on_charge(chest)) {
			albedo = mix(base * charge_color, vec3(0.2, 0.165, 0.12), dirt);
		}
	}

	albedo *= mix(0.45, 1.0, ao);
	ALBEDO = albedo;
	METALLIC = clamp(metallic, 0.0, 1.0);
	ROUGHNESS = clamp(roughness, 0.05, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	if (cloth) {
		RIM = sheen * (1.0 - dirt);
		RIM_TINT = 0.65;
	}
	vec3 own_n = normalize(vec3(-bump_u, -bump_v, 1.0));
	vec3 n = normalize(vec3(tex_n.xy + own_n.xy, tex_n.z * own_n.z));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
