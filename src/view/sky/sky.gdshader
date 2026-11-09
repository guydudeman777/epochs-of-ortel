shader_type sky;
render_mode use_debanding;
// The open sky: its colour by the sun's height, the sun and moon, the stars and the drifting clouds.
// SkyDome sets every uniform; the textures come from tools/art/build_sky.py.

// The cloud kinds, one to a channel: heaped, thin streaks, fine detail, overcast. All wrap.
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
// The night sky laid flat: longitude across, from the zenith down.
uniform sampler2D stars : source_color, filter_linear, repeat_enable;
uniform sampler2D moon : source_color, filter_linear, repeat_disable;

// Toward the sun, which may be under the horizon, and toward the moon.
uniform vec3 sun_direction = vec3(0.0, 0.6, 0.8);
uniform vec3 moon_direction = vec3(0.3, 0.6, -0.7);
// The moon's half width, in radians. Larger than life, as a painter draws it.
uniform float moon_size = 0.035;
// How much of the sky heaped cloud covers, how far an overcast closes it and how much thin high cloud there is.
uniform float cover : hint_range(0.0, 1.0) = 0.4;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float cirrus : hint_range(0.0, 1.0) = 0.4;
// The cloud's own colour: grey-brown under ash, cold over snow.
uniform vec3 cloud_tint : source_color = vec3(1.0);
// Dust or damp hanging low over the land, and how thick.
uniform vec3 haze_color : source_color = vec3(0.7, 0.68, 0.64);
uniform float haze : hint_range(0.0, 1.0) = 0.0;
// Clouds drift by so much of a tile a second; the stars turn by star_turn radians.
uniform vec2 wind = vec2(0.004, 0.0015);
uniform float star_turn = 0.0;
// So many tiles of cloud from the zenith to where the clouds meet the horizon.
uniform float cloud_scale = 0.32;


// The sky's colour without clouds, sun or stars: day blue, a twilight belt toward the sun, near black by night.
vec3 sky_colour(vec3 dir, float sun_up, float toward) {
	float day = smoothstep(-0.08, 0.3, sun_up);
	float night = smoothstep(0.02, -0.25, sun_up);
	float gold = smoothstep(-0.22, 0.0, sun_up) * (1.0 - smoothstep(0.04, 0.32, sun_up));
	vec3 zenith = mix(vec3(0.13, 0.15, 0.27), vec3(0.17, 0.3, 0.52), day);
	zenith = mix(zenith, vec3(0.004, 0.007, 0.018), night);
	vec3 horizon = mix(vec3(0.4, 0.33, 0.38), vec3(0.6, 0.65, 0.7), day);
	horizon = mix(horizon, vec3(0.02, 0.026, 0.045), night);
	// The belt of fire round the sun as it sets, widest under it.
	float side = pow(toward * 0.5 + 0.5, 3.0);
	horizon = mix(horizon, vec3(0.95, 0.45, 0.18), gold * side * 0.85);
	zenith = mix(zenith, vec3(0.3, 0.2, 0.3), gold * side * 0.25);
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 colour = mix(horizon, zenith, pow(up, 0.42));
	// Under the horizon, the far land in shadow.
	vec3 below = horizon * mix(0.55, 0.85, night);
	return mix(below, colour, smoothstep(-0.06, 0.01, dir.y));
}

// The sun's light as it falls on a cloud: white by day, red low down, a cold moonlight after.
vec3 light_colour(float sun_up) {
	float low = 1.0 - smoothstep(0.0, 0.35, sun_up);
	vec3 sun = mix(vec3(1.0, 0.96, 0.9), vec3(1.0, 0.5, 0.25), low);
	float night = smoothstep(0.02, -0.2, sun_up);
	return mix(sun, vec3(0.07, 0.08, 0.11), night);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun = normalize(sun_direction);
	float sun_up = sun.y;
	float toward = dot(normalize(vec3(dir.x, 0.0, dir.z) + vec3(0.0001)), normalize(vec3(sun.x, 0.0, sun.z) + vec3(0.0001)));
	float night = smoothstep(0.02, -0.25, sun_up);
	vec3 colour = sky_colour(dir, sun_up, toward);
	float above = smoothstep(-0.02, 0.06, dir.y);

	// Stars, turned with the night and dimmed near the horizon, where the air is thick.
	vec3 lights = vec3(0.0);
	if (night > 0.001 && dir.y > -0.05) {
		float c = cos(star_turn);
		float s = sin(star_turn);
		vec3 d = vec3(dir.x * c - dir.z * s, dir.y, dir.x * s + dir.z * c);
		vec2 uv = vec2(atan(d.x, d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
		vec3 star = textureLod(stars, uv, 0.0).rgb;
		float twinkle = 1.0;
		if (!AT_CUBEMAP_PASS) {
			twinkle = 0.6 + 0.8 * texture(clouds, uv * vec2(24.0, 12.0) + vec2(TIME * 0.11, TIME * 0.07)).b;
		}
		lights += star * mix(vec3(1.0), vec3(twinkle), 0.6) * 1.6 * night * smoothstep(0.0, 0.3, dir.y);
	}

	// The moon: its face on a small disc, with a pale ring round it by night.
	vec3 m = normalize(moon_direction);
	float to_moon = dot(dir, m);
	float moon_glow = 0.0;
	if (to_moon > 0.9) {
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), m));
		vec3 up = cross(m, right);
		vec2 p = vec2(dot(dir, right), -dot(dir, up)) / moon_size * 0.5 + 0.5;
		vec4 face = texture(moon, clamp(p, 0.0, 1.0));
		face.a *= step(abs(p.x - 0.5), 0.5) * step(abs(p.y - 0.5), 0.5);
		float shown = mix(0.25, 1.0, night) * smoothstep(-0.02, 0.06, m.y);
		lights = mix(lights, face.rgb * mix(0.9, 2.2, night), face.a * shown);
		moon_glow = pow(max(to_moon, 0.0), 900.0) * 0.12 + pow(max(to_moon, 0.0), 60.0) * 0.03;
		moon_glow *= night * smoothstep(-0.02, 0.06, m.y);
	}

	// The sun: a bright disc and the glare round it, red and narrow low down.
	float to_sun = max(dot(dir, sun), 0.0);
	vec3 sun_light = light_colour(sun_up);
	float sun_shown = smoothstep(-0.06, 0.0, sun_up);
	float disc = smoothstep(0.99985, 0.99995, to_sun);
	vec3 glare = sun_light * (pow(to_sun, 300.0) * 1.2 + pow(to_sun, 24.0) * 0.25 + pow(to_sun, 4.0) * 0.08) * sun_shown;
	vec3 sun_disc = sun_light * disc * 30.0 * sun_shown;

	// Clouds on a dome: the lower one looks, the farther off and the more squeezed they are.
	float cloud = 0.0;
	vec3 cloud_colour = vec3(0.0);
	if (dir.y > 0.0) {
		vec2 base = dir.xz / (dir.y + 0.12) * cloud_scale;
		vec2 drift = wind * TIME;
		float detail = texture(clouds, base * 4.1 + drift * 1.7).b;
		// Heaped cloud: the cover sets where the shape breaks into sky, and the detail eats its edges.
		float threshold = mix(0.92, 0.2, cover);
		float shape = texture(clouds, base + drift).r - detail * 0.16;
		float heaped = smoothstep(threshold, threshold + 0.22, shape);
		// Toward the sun the heap is thicker: more of it lies between this point and the light.
		vec2 sunward = normalize(sun.xz + vec2(0.0001)) * 0.025;
		float shape_sun = texture(clouds, base + drift + sunward).r - detail * 0.16;
		float shadow = smoothstep(threshold, threshold + 0.45, shape_sun);
		// Thin streaks, high up and quicker.
		float streak = texture(clouds, base * vec2(0.55, 0.8) + drift * 2.2).g;
		float thin = smoothstep(0.55, 1.0, streak) * cirrus * 0.55 * (1.0 - heaped);
		// The overcast: a sheet that closes over all, darker where it is thick.
		float mass = texture(clouds, base * 0.3 + drift * 0.5).a;
		float sheet = smoothstep(1.0 - overcast * 1.15, 1.25 - overcast * 1.15, mass + detail * 0.1);
		// Under an overcast the heaps and streaks melt into the sheet.
		heaped *= 1.0 - overcast * 0.75;
		thin *= 1.0 - overcast;
		cloud = clamp(heaped + thin + sheet, 0.0, 1.0);

		vec3 lit = sun_light * mix(1.0, 0.25, night) * mix(1.0, 0.4, overcast) * cloud_tint;
		vec3 dim = mix(colour, vec3(dot(colour, vec3(0.33))), 0.5) * 0.7 * cloud_tint;
		vec3 heap_colour = mix(lit, dim, shadow * 0.75);
		// A silver edge where thin cloud lies before the sun.
		heap_colour += sun_light * pow(to_sun, 10.0) * (1.0 - heaped) * heaped * 3.0 * sun_shown;
		// Rain cloud is dull grey, darkest where it is thickest.
		vec3 sheet_colour = mix(vec3(0.2, 0.21, 0.22), vec3(0.075, 0.078, 0.085), smoothstep(0.45, 1.0, mass)) * cloud_tint;
		sheet_colour *= mix(sun_light, vec3(dot(sun_light, vec3(0.33))), 0.6) * mix(1.0, 0.2, night);
		vec3 streak_colour = mix(lit, colour, 0.35) * 1.05;
		float total = heaped + thin + sheet + 0.0001;
		cloud_colour = (heap_colour * heaped + streak_colour * thin + sheet_colour * sheet) / total;
		cloud *= smoothstep(0.0, 0.1, dir.y);
	}

	// The overcast greys the whole sky and hides the sun's glare.
	float grey = overcast * overcast;
	colour = mix(colour, vec3(dot(colour, vec3(0.3, 0.5, 0.2))) * 0.4, grey * 0.85);
	vec3 out_colour = colour + (lights + glare * (1.0 - grey * 0.7)) * above;
	out_colour += vec3(0.6, 0.65, 0.75) * moon_glow;
	out_colour += sun_disc * above;
	out_colour = mix(out_colour, cloud_colour, cloud);
	// Haze low down, lit as the sky is.
	float low = 1.0 - smoothstep(-0.05, 0.35, dir.y);
	vec3 haze_lit = haze_color * mix(1.0, 0.04, night) * mix(vec3(1.0), sun_light, 0.4);
	out_colour = mix(out_colour, haze_lit, haze * low * 0.85);
	COLOR = out_colour;
}
