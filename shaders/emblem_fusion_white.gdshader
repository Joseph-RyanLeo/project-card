shader_type canvas_item;
render_mode unshaded;
uniform float white_amount : hint_range(0.0, 1.0) = 0.0; // 0为原色，1为保留透明轮廓的纯白剪影
varying vec4 item_tint;
void vertex() {
	item_tint = COLOR; // 单独保留节点透明度，避免fragment内已乘纹理的COLOR把白色重新染回原色
}
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(mix(source.rgb, vec3(1.0), white_amount), source.a) * item_tint;
}
