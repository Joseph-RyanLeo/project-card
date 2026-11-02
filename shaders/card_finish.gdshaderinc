// 自行实现的角度驱动材质：纹理固定在卡面上，只有反光随检视方向变化。
vec3 card_flash_light(vec2 uv, vec2 force, int flash_type, float spacing, float width, float intensity, float angle_degrees) {
	float angle = radians(angle_degrees);
	vec2 direction = vec2(cos(angle), sin(angle));
	float position = force.x * 1.35 + force.y * 0.35;
	float stripe = sin(dot(uv, direction) * spacing + position * PI) * 0.5 + 0.5;
	float amount = pow(stripe, width) * intensity;
	if (flash_type == 0) { return vec3(amount); }
	if (flash_type == 1) { return vec3(1.0, 0.78, 0.24) * amount; }
	// 彩虹固定在卡牌空间，光带移动时自然经过不同颜色。
	float hue = fract(uv.x * 0.85 + uv.y * 0.55);
	return vec3(
		0.5 + 0.5 * sin(6.2831 * hue),
		0.5 + 0.5 * sin(6.2831 * (hue + 0.33)),
		0.5 + 0.5 * sin(6.2831 * (hue + 0.66))
	) * amount;
}

float finish_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 finish_spectrum(float phase) {
	return 0.55 + 0.45 * cos(6.283185 * (phase + vec3(0.0, 0.333, 0.667)));
}

vec3 holographic_finish(vec3 base, vec2 uv, vec2 force, float strength, float density) {
	float grooves = sin((uv.x + uv.y * 0.65) * density * 6.283185);
	float cross_grooves = sin((uv.x - uv.y * 0.8) * density * 4.1);
	float phase = uv.x * 0.8 + uv.y * 0.45 + dot(force, vec2(0.32, -0.22));
	vec3 rainbow = finish_spectrum(phase + grooves * 0.035);
	float beam = pow(0.5 + 0.5 * sin((phase + cross_grooves * 0.018) * 6.283185), 7.0);
	float texture_light = (grooves * cross_grooves * 0.5 + 0.5) * 0.12;
	return base * (1.0 - strength * 0.07) + rainbow * (beam * 0.4 + texture_light) * strength;
}

vec3 fractured_finish(vec3 base, vec2 uv, vec2 force, float strength, float density) {
	// Voronoi 每个晶片有固定中心和固定法线，不按时间重新抽取闪点。
	vec2 p = uv * vec2(density, density * 1.2);
	vec2 cell = floor(p);
	float nearest = 10.0;
	float second = 10.0;
	vec2 shard = cell;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 candidate = cell + vec2(float(x), float(y));
			vec2 center = candidate + vec2(finish_hash(candidate), finish_hash(candidate + 57.0));
			float distance_to_center = length(center - p);
			if (distance_to_center < nearest) {
				second = nearest;
				nearest = distance_to_center;
				shard = candidate;
			} else {
				second = min(second, distance_to_center);
			}
		}
	}
	vec2 slope = (vec2(finish_hash(shard + 13.0), finish_hash(shard + 91.0)) - 0.5) * 1.5;
	vec3 normal = normalize(vec3(slope, 1.0));
	vec3 light = normalize(vec3(force.x * 0.95, -force.y * 0.95, 1.0));
	float reflection = pow(max(dot(normal, light), 0.0), 36.0);
	float edge = smoothstep(0.0, 0.055, second - nearest);
	vec3 color = mix(vec3(1.0), finish_spectrum(finish_hash(shard + 7.0) + force.x * 0.15), 0.55);
	return base * (1.0 - strength * (0.04 + (1.0 - edge) * 0.06))
		+ color * reflection * edge * strength * 0.85;
}
