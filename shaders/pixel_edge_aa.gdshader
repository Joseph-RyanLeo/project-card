shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/pixel_edge_aa.gdshaderinc"

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec2 sample_position = pixel_edge_sample_position(UV / TEXTURE_PIXEL_SIZE);
	// 将格间权重换成线性采样坐标，一次读纹理即可完成混色。
	vec2 sample_uv = (sample_position + 0.5) * TEXTURE_PIXEL_SIZE;
	COLOR = texture(TEXTURE, sample_uv) * item_modulate;
}
