// 实验薄膜工艺；纹理固定在卡面坐标，反光随鼠标运动，不依赖时间或游戏随机数。
uniform int film_kind = 0; // 0停用、1磨砂闪、2指纹闪
uniform float film_strength = 0.8; // 膜层反射幅度
uniform float film_density = 140.0; // 颗粒或刻纹的重复密度
uniform float film_detail = 0.65; // 颗粒起伏或曲纹弯曲程度
uniform float film_iridescence = 0.55; // 指纹闪的彩色反射比例
uniform float film_angle = 0.0; // 固定刻纹方向的整体旋转角度
uniform float frosted_shadow_visibility = 0.20; // 磨砂闪在未受光处保留的颗粒强度比例

float frosted_grain_mask(vec2 point) {
	float footprint = max(length(dFdx(point)), length(dFdy(point)));
	if (footprint >= 1.05) { return 0.0; }
	const float SITE_JITTER = 0.65; // 颗粒中心的最大偏移跨度，打散边界而不露出方格
	const float GRAIN_CUTOFF = 0.60; // 亮颗粒约占四成，相邻亮区自然连片
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 winner = cell;
	float nearest = 8.0;
	for (int row = -1; row <= 1; row++) {
		for (int column = -1; column <= 1; column++) {
			vec2 step_cell = vec2(float(column), float(row));
			vec2 candidate = cell + step_cell;
			vec2 site = step_cell + vec2(0.5) + SITE_JITTER *
				(vec2(finish_hash(candidate + vec2(17.0, 0.0)), finish_hash(candidate + vec2(0.0, 41.0))) - vec2(0.5));
			vec2 delta = local - site;
			float distance_squared = dot(delta, delta);
			if (distance_squared < nearest) {
				nearest = distance_squared;
				winner = candidate;
			}
		}
	}
	float resolved = 1.0 - smoothstep(0.50, 1.05, footprint);
	return step(GRAIN_CUTOFF, finish_hash(winner)) * resolved;
}

// 抗锯齿细纹：缩回收藏中的小卡时，逐渐取平均，避免细线变成闪烁摩尔纹。
float film_ridge(float phase) {
	float footprint = max(fwidth(phase), 0.001);
	float ridge = smoothstep(0.38 - footprint, 0.38 + footprint, abs(fract(phase) - 0.5));
	return mix(ridge, 0.24, smoothstep(0.3, 0.9, footprint));
}

vec3 card_film_finish(vec3 base, vec2 uv, vec2 region_uv, vec2 force, int layer) {
	if (film_kind == 1 && layer == 0) { return base; }
	vec2 point = (uv - vec2(0.5)) * vec2(1.0, 1.3);
	float angle = radians(film_angle);
	mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 p = rotation * point;
	// 反光方向使用闪卡的真实像素梯度，刻纹旋转只影响固定纹理。
	float rest_angle = radians(flash_angle_degrees);
	vec2 rest_direction = vec2(cos(rest_angle), sin(rest_angle));
	vec2 gradient = card_flash_gradient(force, flash_direction_force, card_size + foil_padding * 2.0, rest_direction);
	float phase = dot((uv - vec2(0.5)) * card_size, gradient) - dot(force, vec2(0.38, -0.26));
	float beam = pow(0.5 + 0.5 * cos(phase * 6.283185), 4.0);
	vec2 light_delta = point - force * vec2(0.48, 0.62);
	float glare = exp(-dot(light_delta, light_delta) * 5.0);
	float tilt = min(length(force), 1.0);
	vec3 tint = vec3(1.0);
	float relief;
	float reflection;
	if (film_kind == 1) {
		const float GRAIN_REFLECTION = 0.16; // 分辨得出的亮颗粒使用同一白色反射强度
		float illumination = smoothstep(0.20, 0.70, max(beam, glare * 0.65));
		float grain_visibility = mix(frosted_shadow_visibility, 1.0, illumination);
		float grain = frosted_grain_mask(p * film_density) * GRAIN_REFLECTION * film_detail * grain_visibility;
		relief = 1.0;
		reflection = beam * 0.3 + glare * 0.18 + 0.02 + grain;

	} else {
		float grooves;
		float orientation;
		if (layer == 0) {
			// 整个人物只使用同一套连续弧纹，不再按上／左／右切换纹理中心。
			vec2 center = vec2(0.44, 0.12);
			vec2 local = rotation * ((region_uv - center) * vec2(1.0, 1.2));
			float bend = local.x + film_detail * (local.y * local.y * 0.7 + sin(local.y * 2.8) * 0.14);
			grooves = film_ridge(bend * film_density);
			orientation = atan(local.y * film_detail, 0.65);
		} else {
			// 背景与外框共用整卡坐标下的放射交织纹。
			vec2 radial = p - vec2(-0.12, 0.2);
			float radius = length(radial);
			float polar = atan(radial.y, radial.x);
			grooves = film_ridge((polar * 0.13 + radius * film_detail * 0.35) * film_density);
			grooves = max(grooves, film_ridge(radius * film_density * 0.7) * 0.4);
			orientation = polar;
		}
		float directional = 0.45 + 0.55 * pow(0.5 + 0.5 * cos(orientation * 2.0 - force.x * 2.4 + force.y * 1.6), 2.0);
		relief = 1.0 - (1.0 - grooves) * 0.1 * film_strength;
		reflection = (0.04 + beam * 0.3 + glare * 0.1) * (0.2 + grooves * 1.1) * directional;
		tint = mix(vec3(1.0), finish_spectrum(phase * 1.8 + orientation * 0.12), film_iridescence);
	}
	return base * relief + tint * reflection * film_strength * (0.65 + tilt * 0.35);
}
