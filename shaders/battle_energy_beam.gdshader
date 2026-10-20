/*
 * Project Card 的曲线攻击尾迹。
 *
 * 普通尾迹外形取自静态灰度遮罩；水流与灵魂光带由数学轮廓生成。
 * 流动由程序噪声生成；水流读取可暂停的 effect_time，其他样式沿用 TIME。
 * 这种职责分工对应 Unity Trail Renderer 教程中的主纹理与 Gradient Noise。
 * 世界坐标像素锁定仍改编自 Godot Shaders 的 2D pixel-perfect 示例。
 */
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D trail_mask : filter_linear, repeat_disable;
uniform bool flip_mask_x = false;
uniform bool soul_ribbon = false;
uniform bool water_flow = false;
uniform float wave_opacity = 0.0; // 短水波出现与命中后消散的透明度
uniform float wave_width = 112.0; // 波面横向宽度，供三层厚度保持统一像素比例
uniform float wave_depth = 53.76; // 包含两端后拖的当前绘制深度
uniform float wave_stretch = 0.0; // 两端随实际行进距离向后拉长的距离
uniform float effect_time = 0.0; // 由飞行Tween提供，水流随暂停与战斗倍速变化
uniform float soul_taper : hint_range(0.2, 3.0) = 0.75; // 细尾到宽头的收尾指数
uniform float soul_core_width : hint_range(0.0, 0.8) = 0.30; // 白色亮芯的宽度比例
uniform float impact_progress = 1.0; // 目标在实际路径上的位置，光带不越过此点
uniform vec4 head_color : source_color = vec4(1.0);
uniform vec4 tail_color : source_color = vec4(1.0);
uniform float noise_seed = 0.0;

uniform float travel_progress : hint_range(0.0, 1.5) = 0.0;
uniform float trail_length : hint_range(0.05, 1.0) = 0.28;
uniform float trail_softness : hint_range(0.001, 0.2) = 0.035;
uniform float flow_speed : hint_range(0.0, 8.0) = 2.4;
uniform float flow_frequency : hint_range(1.0, 16.0) = 6.0;
uniform float flow_strength : hint_range(0.0, 0.9) = 0.48;
uniform float warp_speed : hint_range(-8.0, 8.0) = -1.0;
uniform float warp_frequency : hint_range(0.1, 24.0) = 6.0;
uniform float twirl_frequency : hint_range(0.1, 24.0) = 4.0;
uniform float warp_strength : hint_range(0.0, 0.45) = 0.12;
uniform float mask_cutoff : hint_range(0.0, 0.4) = 0.018;
uniform float mask_power : hint_range(0.2, 4.0) = 1.0;
uniform float edge_threshold : hint_range(0.0, 0.8) = 0.12;
uniform float edge_softness : hint_range(0.001, 0.25) = 0.025;

uniform float pixel_size : hint_range(1.0, 16.0) = 4.0;
uniform bool handle_edges = true;

const float WATER_FRONT_WIDTH = 0.054; // 亮色前缘厚度，相对波面宽度；比原默认增加约25%
const float WATER_MIDDLE_WIDTH = 0.097; // 正蓝中层厚度，相对波面宽度；比原默认增加约25%
const float WATER_REAR_WIDTH = 0.16; // 半透明尾波的基础厚度，相对波面宽度

varying vec2 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


float random_value(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233)) + noise_seed) * 43758.5453);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	vec2 blend = local * local * (3.0 - 2.0 * local);
	float bottom_left = random_value(cell);
	float bottom_right = random_value(cell + vec2(1.0, 0.0));
	float top_left = random_value(cell + vec2(0.0, 1.0));
	float top_right = random_value(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, blend.x),
		mix(top_left, top_right, blend.x),
		blend.y
	);
}


vec2 pixel_perfect_uv(vec2 source_uv) {
	vec2 snapped_world = floor(world_position / pixel_size) * pixel_size + vec2(pixel_size * 0.5);
	vec2 world_delta = snapped_world - world_position;
	mat2 world_derivatives = mat2(dFdx(world_position), dFdy(world_position));
	mat2 uv_derivatives = mat2(dFdx(source_uv), dFdy(source_uv));
	mat2 world_to_uv = uv_derivatives * inverse(world_derivatives);
	return source_uv + world_to_uv * world_delta;
}


void fragment() {
	vec2 uv = pixel_perfect_uv(UV);
	float motion_time = water_flow ? effect_time : TIME;
	float trail_start = travel_progress - trail_length;
	float trail_position = (uv.x - trail_start) / max(trail_length, 0.001);
	vec2 mask_uv = water_flow ? uv : vec2(clamp(trail_position, 0.0, 1.0), clamp(uv.y, 0.0, 1.0));
	float warp_noise = value_noise(vec2(
		mask_uv.x * warp_frequency - motion_time * warp_speed,
		noise_seed + motion_time * warp_speed * 0.17
	));
	float warp_envelope = (
		smoothstep(0.0, 0.08, mask_uv.x)
		* smoothstep(0.0, 0.08, 1.0 - mask_uv.x)
	);
	float twirl_wave = sin(
		(mask_uv.x * twirl_frequency + warp_noise * 0.85 - motion_time * warp_speed)
		* 6.2831853
	);
	float warp_shape = mix(warp_noise * 2.0 - 1.0, twirl_wave, 0.72);
	mask_uv.y = clamp(
		mask_uv.y + (water_flow ? 0.0 : warp_shape * warp_strength * warp_envelope),
		0.0,
		1.0
	);
	vec2 texture_uv = mask_uv;
	if (flip_mask_x) {
		texture_uv.x = 1.0 - texture_uv.x;
	}
	float painted_mask;
	float soul_core = 0.0;
	float water_layer = 0.0;
	if (water_flow) {
		// 前两条弧带保持平顺；噪声只塑造第三层尾缘，不切碎纯色色块。
		float across = (uv.y - 0.5) / 0.45;
		float side = min(abs(across), 1.0);
		float arc = sqrt(max(1.0 - side * side, 0.0));
		float front = -wave_width * 0.28 * (1.0 - arc) - wave_stretch * pow(side, 1.8);
		float behind = front - ((uv.x - 1.0) * (wave_depth + wave_width * 0.04) + wave_width * 0.04);
		float taper = pow(max(1.0 - side * side, 0.0), 0.35);
		vec2 tail_uv = vec2(across * flow_frequency - motion_time * flow_speed, 2.7 + motion_time * flow_speed * 0.35);
		float tail_noise = mix(value_noise(tail_uv), value_noise(tail_uv * vec2(2.3, 1.7) + vec2(8.4, -3.1)), 0.32) * 2.0 - 1.0;
		float rear_width = WATER_REAR_WIDTH * (1.0 + tail_noise * min(warp_strength * 4.0, 0.75));
		float thickness = wave_width * (WATER_FRONT_WIDTH + WATER_MIDDLE_WIDTH + rear_width) * taper;
		water_layer = behind / max(wave_width * taper, 0.001);
		painted_mask = step(side, 0.999) * step(0.0, behind) * step(behind, thickness);
	} else if (soul_ribbon) {
		// 外形由数学轮廓生成，无需借用参考视频的纹理或素材。
		float along = clamp(trail_position, 0.0, 1.0);
		float rounded_head = sqrt(max(1.0 - pow(max((along - 0.90) / 0.10, 0.0), 2.0), 0.0));
		float absorption = clamp((impact_progress - trail_start) / max(trail_length, 0.001), 0.0, 1.0);
		float half_width = 0.44 * pow(along, soul_taper) * rounded_head * sqrt(absorption);
		float cross_distance = abs(mask_uv.y - 0.5);
		float feather = max(edge_softness, 0.002);
		painted_mask = (1.0 - smoothstep(max(half_width - feather, 0.0), half_width + feather, cross_distance));
		painted_mask *= smoothstep(0.0, 0.07, along) * step(uv.x, impact_progress);
		float core_width = half_width * soul_core_width;
		soul_core = (1.0 - smoothstep(core_width * 0.45, max(core_width, 0.001), cross_distance));
		soul_core *= step(0.001, soul_core_width);
	} else {
		vec3 mask_sample = texture(trail_mask, texture_uv).rgb;
		painted_mask = dot(mask_sample, vec3(0.299, 0.587, 0.114));
	}
	painted_mask = max(painted_mask - mask_cutoff, 0.0) / max(1.0 - mask_cutoff, 0.001);
	painted_mask = pow(clamp(painted_mask, 0.0, 1.0), mask_power);
	// 只收紧低透明度轮廓；主体仍保留原图内部的灰度层次和动态流动。
	float crisp_boundary = smoothstep(
		max(edge_threshold - edge_softness, 0.0),
		min(edge_threshold + edge_softness, 1.0),
		painted_mask
	);
	painted_mask *= crisp_boundary;

	float trailing_edge = smoothstep(
		trail_start - trail_softness,
		trail_start + trail_softness,
		uv.x
	);
	float leading_edge = 1.0 - smoothstep(
		travel_progress - trail_softness,
		travel_progress + trail_softness,
		uv.x
	);
	float travel_window = trailing_edge * leading_edge;
	if (water_flow) {
		travel_window = wave_opacity;
	}

	vec2 noise_uv = vec2(
		uv.x * flow_frequency - motion_time * flow_speed,
		uv.y * 3.0 + noise_seed
	);
	float first_noise = value_noise(noise_uv);
	float second_noise = value_noise(noise_uv * vec2(1.85, 1.35) + vec2(7.1, -3.4));
	float flow_noise = mix(first_noise, second_noise, 0.42);
	float flow_wave = 0.5 + 0.5 * sin(
		(uv.x * flow_frequency - motion_time * flow_speed + uv.y + flow_noise * 0.75)
		* 6.2831853
	);
	float flow_band = smoothstep(0.42, 0.88, mix(flow_wave, flow_noise, 0.40));
	float flow_alpha = mix(1.0 - flow_strength * 0.62, 1.0, flow_band);

	vec4 result = mix(
		tail_color,
		head_color,
		clamp(trail_position, 0.0, 1.0)
	);
	if (soul_ribbon) {
		result.rgb = mix(result.rgb, vec3(1.0), soul_core * 0.68);
	}
	if (water_flow) {
		vec3 light = mix(head_color.rgb, vec3(1.0), 0.64);
		result.rgb = water_layer < WATER_FRONT_WIDTH ? light : (water_layer < WATER_FRONT_WIDTH + WATER_MIDDLE_WIDTH ? head_color.rgb : tail_color.rgb);
		result.a = (water_layer < WATER_FRONT_WIDTH + WATER_MIDDLE_WIDTH ? 1.0 : 0.42) * painted_mask * travel_window;
	} else {
		result.a *= painted_mask * travel_window * flow_alpha;
	}

	if (handle_edges) {
		mat2 world_derivatives = mat2(dFdx(world_position), dFdy(world_position));
		mat2 uv_derivatives = mat2(dFdx(UV), dFdy(UV));
		mat2 world_to_uv = uv_derivatives * inverse(world_derivatives);
		float margin_x = (abs(world_to_uv[0].x) + abs(world_to_uv[1].x)) * pixel_size * 0.5;
		float margin_y = (abs(world_to_uv[0].y) + abs(world_to_uv[1].y)) * pixel_size * 0.5;
		if (uv.x < margin_x || uv.x > 1.0 - margin_x || uv.y < margin_y || uv.y > 1.0 - margin_y) {
			result.a = 0.0;
		}
	}

	COLOR = result * COLOR;
}
