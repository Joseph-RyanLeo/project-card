shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/card_projection.gdshaderinc"

uniform vec2 panel_size = vec2(1.0);
uniform float spread = 16.0; // 柔光的扩散半径
uniform float inner_pixel = 1.0; // 当前画布里一个游戏逻辑像素的宽度
uniform float pulse_weight = 0.0;
uniform vec3 glow_color = vec3(1.0, 0.72, 0.29); // 默认使用手柄的暖金色
uniform bool use_silhouette = false;
uniform sampler2D silhouette_texture : filter_linear, repeat_disable;
uniform vec4 silhouette_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool projected_shape = false;
uniform vec2 projection_force = vec2(0.0);
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

float rectangle_glow(vec2 point, float radius) {
	vec2 edge = abs(point - panel_size * 0.5) - (panel_size * 0.5 - spread);
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0);
	float halo = exp(-pow(max(distance_to_edge, 0.0) / (radius * 0.43), 2.0));
	return halo * smoothstep(-inner_pixel, 0.0, distance_to_edge)
		* (1.0 - smoothstep(radius * 0.55, radius, distance_to_edge));
}

float silhouette_alpha(vec2 uv, mat3 rotation) {
	if (projected_shape) {
		// 和检视卡面相同的反投影，商品倾斜时采样实际已经移动的边缘。
		float perspective = tan(radians(72.0) * 0.5);
		float distance = 0.5 / perspective + 0.5;
		vec3 projected = rotation * vec3((uv - 0.5) / (1.0 + perspective), 0.5 / perspective);
		uv = projected.xy * (distance * rotation[2].z / max(projected.z, 0.001))
			- distance * rotation[2].xy + 0.5;
	}
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return texture(silhouette_texture, uv).a * inside.x * inside.y;
}

float silhouette_glow(vec2 point, float radius) {
	vec2 uv = (point - silhouette_rect.xy) / silhouette_rect.zw;
	mat3 rotation = card_inverse_rotation(projection_force, 10.0);
	float center = silhouette_alpha(uv, rotation);
	float nearby = 0.0;
	float inner = 1.0;
	for (int direction = 0; direction < 8; direction++) {
		float angle = float(direction) * TAU / 8.0;
		vec2 ray = vec2(cos(angle), sin(angle)) / silhouette_rect.zw;
		inner = min(inner, silhouette_alpha(uv + ray * inner_pixel, rotation));
		nearby += silhouette_alpha(uv + ray * radius * 0.26, rotation) * 0.65;
		nearby += silhouette_alpha(uv + ray * radius * 0.72, rotation) * 0.35;
	}
	float edge = center * (1.0 - inner);
	return max(edge, smoothstep(0.0, 0.42, nearby / 8.0) * (1.0 - center));
}

void fragment() {
	vec2 point = UV * panel_size;
	float phase = 0.5 - 0.5 * cos(TIME * TAU / 1.8);
	float pulse = mix(1.0, mix(0.53, 1.0, phase), pulse_weight);
	float radius = spread * mix(0.73, 1.0, phase * pulse_weight);
	float halo = use_silhouette ? silhouette_glow(point, radius) : rectangle_glow(point, radius);
	COLOR = vec4(glow_color, halo * pulse * 0.72) * item_modulate;
}
