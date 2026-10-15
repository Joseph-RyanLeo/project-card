shader_type canvas_item;
render_mode unshaded;
uniform float pulse_speed = 3.2; // 可合成目标紫光的呼吸角速度
void fragment() {
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	float edge = step(0.90, max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0);
	COLOR = vec4(0.78, 0.40, 1.0, mix(0.10, 0.32, pulse) + edge * mix(0.20, 0.40, pulse));
}
