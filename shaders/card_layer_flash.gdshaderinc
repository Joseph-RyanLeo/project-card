#include "res://shaders/card_finish.gdshaderinc"

uniform vec2 pointer_force = vec2(0.0);
uniform vec2 flash_direction_force = vec2(0.0);
uniform vec2 card_size = vec2(99.0, 136.0); // 整张卡的原生尺寸，供各层对齐同一道光带
uniform vec2 foil_padding = vec2(18.0);
uniform vec2 layer_origin = vec2(0.0); // 当前图层左上角在卡面上的原生坐标
uniform float stripe_spacing = 14.0;
uniform float stripe_width = 10.0;
uniform float flash_intensity = 0.2;
uniform float flash_offset = 0.0;
uniform float flash_angle_degrees = 50.0;
uniform bool outline_highlight_enabled = false;
uniform float outline_gain = 2.2; // 描边相对于背景闪纹的亮度倍率
uniform float outline_silhouette = 0.4; // 亮色像素贴着透明区时的轮廓反光比例

vec3 card_layer_flash(vec2 card_position, int flash_type) {
	vec2 plane_size = card_size + foil_padding * 2.0;
	vec2 plane_uv = (card_position + foil_padding) / plane_size;
	return card_flash_light(plane_uv, pointer_force, flash_direction_force, plane_size, flash_type,
		stripe_spacing, stripe_width, flash_intensity, flash_angle_degrees, flash_offset);
}

float card_outline_brightness(vec4 pixel) {
	return max(pixel.r, max(pixel.g, pixel.b));
}

float card_outline_contrast(vec4 pixel) {
	return max(card_outline_brightness(pixel), 1.0 - pixel.a);
}

vec3 card_outline_flash(vec2 card_position, vec4 pixel, vec4 left, vec4 right, vec4 up, vec4 down) {
	// 深色线条紧贴亮色或透明区时反光；亮色轮廓也可得到较弱反光。
	float darkness = 1.0 - smoothstep(0.12, 0.30, card_outline_brightness(pixel));
	float neighbor = max(max(card_outline_contrast(left), card_outline_contrast(right)),
		max(card_outline_contrast(up), card_outline_contrast(down)));
	float neighbor_alpha = min(min(left.a, right.a), min(up.a, down.a));
	float dark_edge = darkness * smoothstep(0.28, 0.62, neighbor);
	float silhouette = smoothstep(0.25, 0.75, pixel.a - neighbor_alpha) * outline_silhouette;
	return card_layer_flash(card_position, 0) * max(dark_edge, silhouette) * outline_gain;
}
