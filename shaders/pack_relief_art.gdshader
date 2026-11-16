shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/pack_relief.gdshaderinc"

// 在原包装UV内照明，封条裁切后仍取同一位置的颜色与法线；整体透视交给外层。
uniform vec2 pointer_force = vec2(0.0);
uniform float seal_hint_seconds = -1.0; // 负数关闭提示，否则表示扫光已播放的秒数
uniform float seal_sweep_seconds = 2.0; // 银线从左到右再返回的一轮时长
uniform float seal_sweep_width = 0.14; // 局部亮带占包装宽度的比例
uniform float seal_sweep_strength = 1.1; // 冷白色亮带的高光增量
uniform float seal_shadow_brightness = 0.42; // 亮带之外银线的亮度比例，降低可增强明暗对比
uniform float seal_hint_fade_seconds = 0.2; // 提示开始时的淡入时长
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = pack_relief_color(source, UV, pointer_force);
	// 使用原图银灰色和封口纵向位置双重限制，不照亮蓝色袋身与金纹。
	float silver = (1.0 - smoothstep(0.02, 0.10, max(source.r, max(source.g, source.b)) - min(source.r, min(source.g, source.b)))) * step(0.35, source.r);
	float seal = step(8.0, UV.y / TEXTURE_PIXEL_SIZE.y) * (1.0 - step(13.0, UV.y / TEXTURE_PIXEL_SIZE.y));
	if (seal_hint_seconds >= 0.0) {
		float center = 0.5 - 0.5 * cos(seal_hint_seconds * 6.283185 / seal_sweep_seconds);
		float band = exp(-pow((UV.x - center) / seal_sweep_width, 2.0));
		vec3 highlight = COLOR.rgb * mix(seal_shadow_brightness, 1.05, band)
			+ vec3(0.8, 0.92, 1.0) * band * seal_sweep_strength;
		float fade = smoothstep(0.0, seal_hint_fade_seconds, seal_hint_seconds);
		COLOR.rgb = mix(COLOR.rgb, highlight, silver * seal * fade);
	}
	COLOR *= item_modulate;
}
