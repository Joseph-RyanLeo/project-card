shader_type canvas_item;
render_mode unshaded;

uniform float wall_x = 68.0; // 原画中竖直撞击墙的像素X
uniform float tail_length = 0.0; // 换算回原画像素的横向尾流保留长度
varying vec2 source_pixel;
varying vec4 item_modulate;

void vertex() {
	source_pixel = VERTEX + vec2(64.0);
	item_modulate = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// 仅裁掉中央入射水柱，保留水墙向两边散开的水花和碎滴。
	if (source_pixel.x < wall_x - tail_length && source_pixel.y >= 58.0 && source_pixel.y < 70.0) {
		source.a = 0.0;
	}
	COLOR = source * item_modulate;
}
