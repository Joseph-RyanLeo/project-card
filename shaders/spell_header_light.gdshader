shader_type canvas_item;

uniform vec2 header_size = vec2(42.0, 43.0); // 分类图标的原生像素尺寸
uniform float charge : hint_range(0.0, 1.0) = 0.0; // 由未释放令牌数量计算的常态亮度
uniform float brightness_gain = 0.0; // 令牌数趋于饱和时的亮度增幅
uniform float saturation_gain = 0.0; // 令牌数趋于饱和时的饱和度增幅
uniform float release_glow : hint_range(0.0, 1.0) = 0.0; // 释放动画从零到峰值的进度
uniform float release_strength = 0.0; // 峰值边缘光强度倍率
const float GLOW_MARGIN = 3.0; // 四边留出的外发光像素
const vec3 GOLD = vec3(1.0, 0.78, 0.32);
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
	VERTEX += (UV * 2.0 - 1.0) * GLOW_MARGIN;
}

void fragment() {
	vec2 pixel = (UV - 0.5) * (header_size + 2.0 * GLOW_MARGIN);
	vec2 source_uv = pixel / header_size + 0.5;
	vec4 source = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThanEqual(source_uv, vec2(1.0)))) {
		source.a = 0.0;
	}
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 lit_color = clamp(mix(vec3(luminance), source.rgb, 1.0 + saturation_gain * charge) * (1.0 + brightness_gain * charge), 0.0, 1.0);

	vec2 edge = abs(pixel) - header_size * 0.5 + vec2(1.5);
	float distance_to_frame = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0);
	float glow = release_glow * release_strength;
	float frame_light = (1.0 - smoothstep(0.4, 2.8, abs(distance_to_frame))) * glow;
	float halo = (1.0 - smoothstep(0.0, GLOW_MARGIN + 1.5, max(distance_to_frame, 0.0))) * glow * 0.65;
	COLOR = vec4(mix(GOLD, mix(lit_color, GOLD, min(frame_light, 1.0)), source.a), clamp(max(source.a, halo), 0.0, 1.0)) * item_tint;
}
