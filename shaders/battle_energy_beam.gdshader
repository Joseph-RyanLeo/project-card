/*
 * Project Card 的曲线攻击尾迹。
 *
 * 尾迹外形取自静态灰度遮罩，流动则由 Shader 内的 TIME 与程序噪声生成；
 * 这种职责分工对应 Unity Trail Renderer 教程中的主纹理与 Gradient Noise。
 * 世界坐标像素锁定仍改编自 Godot Shaders 的 2D pixel-perfect 示例。
 */
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D trail_mask : filter_linear, repeat_disable;
uniform bool flip_mask_x = false;
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
	float trail_start = travel_progress - trail_length;
	float trail_position = (uv.x - trail_start) / max(trail_length, 0.001);
	vec2 mask_uv = vec2(clamp(trail_position, 0.0, 1.0), clamp(uv.y, 0.0, 1.0));
	float warp_noise = value_noise(vec2(
		mask_uv.x * warp_frequency - TIME * warp_speed,
		noise_seed + TIME * warp_speed * 0.17
	));
	float warp_envelope = (
		smoothstep(0.0, 0.08, mask_uv.x)
		* smoothstep(0.0, 0.08, 1.0 - mask_uv.x)
	);
	float twirl_wave = sin(
		(mask_uv.x * twirl_frequency + warp_noise * 0.85 - TIME * warp_speed)
		* 6.2831853
	);
	float warp_shape = mix(warp_noise * 2.0 - 1.0, twirl_wave, 0.72);
	mask_uv.y = clamp(
		mask_uv.y + warp_shape * warp_strength * warp_envelope,
		0.0,
		1.0
	);
	vec2 texture_uv = mask_uv;
	if (flip_mask_x) {
		texture_uv.x = 1.0 - texture_uv.x;
	}
	vec3 mask_sample = texture(trail_mask, texture_uv).rgb;
	float painted_mask = dot(mask_sample, vec3(0.299, 0.587, 0.114));
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

	vec2 noise_uv = vec2(
		uv.x * flow_frequency - TIME * flow_speed,
		uv.y * 3.0 + noise_seed
	);
	float first_noise = value_noise(noise_uv);
	float second_noise = value_noise(noise_uv * vec2(1.85, 1.35) + vec2(7.1, -3.4));
	float flow_noise = mix(first_noise, second_noise, 0.42);
	float flow_wave = 0.5 + 0.5 * sin(
		(uv.x * flow_frequency - TIME * flow_speed + uv.y + flow_noise * 0.75)
		* 6.2831853
	);
	float flow_band = smoothstep(0.42, 0.88, mix(flow_wave, flow_noise, 0.40));
	float flow_alpha = mix(1.0 - flow_strength * 0.62, 1.0, flow_band);

	vec4 result = mix(
		tail_color,
		head_color,
		clamp(trail_position, 0.0, 1.0)
	);
	result.a *= painted_mask * travel_window * flow_alpha;

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
