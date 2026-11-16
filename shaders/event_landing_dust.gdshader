shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dust_color : source_color = vec4(0.49, 0.44, 0.35, 0.60); // 烟尘底色与最大不透明度
uniform vec2 canvas_size = vec2(326.0, 276.0); // 随方向扩展绘制范围，避免右侧烟尘被裁切
uniform vec2 canvas_origin = vec2(163.0, 138.0); // 扩展画布后仍固定在原着地点
uniform vec2 directional_spread = vec2(0.0); // 着地点至最后一团烟尘的位移，零值保持原环状烟尘
uniform float elapsed_seconds = 0.0;
uniform float slide_seconds = 0.0; // 卡包实际滑行时长
uniform float slide_power = 2.0; // 卡包实际减速指数
uniform int puff_count = 1; // 沿途椭圆烟团数量，上限12
uniform float puff_life_seconds = 1.16; // 组件传入每团从扬起至消散的秒数

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// 返回椭圆的有符号边界距离、边缘宽度、消散强度与明暗度。负距离表示烟团内部。
vec4 puff_shape(vec2 position, float age) {
	if (age <= 0.0 || age >= 1.0) { return vec4(1000.0, 1.0, 0.0, 0.0); }
	vec2 p = position + vec2(0.0, age * 14.0);
	float expansion = 1.0 - pow(1.0 - age, 3.0);
	vec2 q = p / vec2(88.0, 73.0); // 与普通事件相同的椭圆横纵半径
	float angle = atan(q.y, q.x);
	float curl = sin(angle * 12.0 + age * 3.0) * 0.05 + sin(angle * 19.0 - age * 2.0) * 0.025;
	float radius = 0.95 + expansion * 0.42 + curl;
	float cloud = noise(p * 0.075 + vec2(age * 2.2, -age * 4.0));
	cloud = cloud * 0.65 + noise(p * 0.15 - age * 2.5) * 0.35;
	float width = 0.11 + expansion * 0.14;
	float distance = length(q) - radius + (cloud - 0.5) * 0.24;
	float lobes = smoothstep(0.18 + age * 0.36, 0.72, cloud);
	float fade = lobes * smoothstep(0.0, 0.06, age) * pow(1.0 - age, 0.65);
	return vec4(distance, width, fade, 0.72 + cloud * 0.48);
}
void fragment() {
	vec2 pixel = floor(UV * canvas_size / 2.0) * 2.0; // 两像素取样，保留烟团的像素颗粒
	vec2 p = pixel - canvas_origin;
	vec4 shape = puff_shape(p, progress);
	if (length(directional_spread) > 0.001) {
		shape = vec4(1000.0, 1.0, 0.0, 0.0);
		for (int index = 0; index < 12; index++) {
			if (index >= puff_count) { break; }
			float fraction = float(index) / max(1.0, float(puff_count - 1));
			// 反求卡包滑到该路段的时刻，减速越明显，后段烟团出现越晚。
			float birth = slide_seconds * (1.0 - pow(1.0 - fraction, 1.0 / slide_power));
			vec4 next = puff_shape(p - directional_spread * fraction, (elapsed_seconds - birth) / puff_life_seconds);
			// 椭圆取并集：只画合并后的外边界，重叠区域内部的圆环不再绘制。
			if (next.x < shape.x) { shape = next; }
		}
	}
	float alpha = exp(-pow(shape.x / shape.y, 2.0)) * shape.z;
	COLOR = vec4(dust_color.rgb * shape.w, alpha * dust_color.a);
}
