shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/pack_relief.gdshaderinc"

// 在原包装UV内照明，封条裁切后仍取同一位置的颜色与法线；整体透视交给外层。
uniform vec2 pointer_force = vec2(0.0);
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	COLOR = pack_relief_color(texture(TEXTURE, UV), UV, pointer_force) * item_modulate;
}
