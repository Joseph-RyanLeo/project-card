shader_type canvas_item;
render_mode unshaded;

uniform vec2 ring_center;
uniform float ring_radius;
varying vec2 local_position;

void vertex() {
	// VERTEX 是控件内的坐标，换卡图或使用图集时不需要重算纹理 UV。
	local_position = VERTEX;
}

void fragment() {
	vec2 offset = local_position - ring_center;
	// 圆环下半部挡住身体。上半部保留原图的透明轮廓，让角色探出圆环。
	if (offset.y > 0.0) {
		COLOR.a *= 1.0 - smoothstep(ring_radius - 0.5, ring_radius + 0.5, length(offset));
	}
}
