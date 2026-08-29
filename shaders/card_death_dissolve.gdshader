shader_type canvas_item;
render_mode unshaded;

uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge_color : source_color = vec4(0.38, 0.78, 0.28, 1.0);
uniform float noise_scale : hint_range(1.0, 24.0) = 7.0;
uniform float noise_seed = 0.0;


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


float layered_noise(vec2 uv) {
	float result = value_noise(uv * noise_scale) * 0.58;
	result += value_noise(uv * noise_scale * 2.07 + vec2(5.2, 1.3)) * 0.29;
	result += value_noise(uv * noise_scale * 4.13 + vec2(2.7, 8.1)) * 0.13;
	return result;
}


void fragment() {
	vec4 source = COLOR;
	// 多层卡面共用屏幕像素坐标，让边框、文字和插画沿同一噪声边界溶解。
	float noise_value = layered_noise(FRAGCOORD.xy / 128.0);
	float body_mask = step(dissolve_progress, noise_value);
	float edge_visible_mask = step(edge_progress, noise_value);
	float edge_mask = edge_visible_mask * (1.0 - body_mask);
	vec3 output_rgb = mix(source.rgb, dissolve_edge_color.rgb, edge_mask);
	float output_alpha = source.a * max(body_mask, edge_visible_mask);
	COLOR = vec4(output_rgb, output_alpha);
}
