shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/pixel_edge_aa.gdshaderinc"

uniform bool edge_only = false;

void fragment() {
	// 视口每轴按两倍采样。线性采样每格中心时，正好平均原图的 2×2 个样本。
	vec2 cell_size = TEXTURE_PIXEL_SIZE * 2.0;
	vec2 cell_position = UV / cell_size;
	vec2 cell = edge_only ? pixel_edge_sample_position(cell_position) : cell_position - 0.5;
	vec2 origin = (floor(cell) + 0.5) * cell_size;
	vec2 weight = fract(cell);
	vec4 top = mix(texture(TEXTURE, origin), texture(TEXTURE, origin + vec2(cell_size.x, 0.0)), weight.x);
	vec4 bottom = mix(texture(TEXTURE, origin + vec2(0.0, cell_size.y)), texture(TEXTURE, origin + cell_size), weight.x);
	COLOR = mix(top, bottom, weight.y);
}
