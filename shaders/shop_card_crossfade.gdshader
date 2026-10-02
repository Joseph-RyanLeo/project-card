shader_type canvas_item;

uniform sampler2D previous_texture : source_color, filter_nearest;
uniform float blend_amount : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	// 同一层混合RGBA，两个不透明卡框之间的过渡仍保持不透明。
	COLOR = mix(texture(previous_texture, UV), texture(TEXTURE, UV), blend_amount) * item_tint;
}
