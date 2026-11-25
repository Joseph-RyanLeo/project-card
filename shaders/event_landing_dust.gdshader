shader_type canvas_item;
render_mode unshaded;

uniform vec4 dust_color : source_color = vec4(0.49, 0.44, 0.35, 0.60); // 烟尘底色与最大不透明度
uniform vec2 canvas_size = vec2(326.0, 276.0); // 随方向扩展绘制范围，避免右侧烟尘被裁切
uniform vec2 canvas_origin = vec2(163.0, 138.0); // 扩展画布后仍固定在原着地点
uniform int puff_count = 0; // 本帧已经扬起且未消散的烟团数量，上限12
uniform vec4 puffs[12]; // 中心偏移X/Y、寿命百分比、当前透明度

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
vec4 puff_shape(vec2 p, float age, float opacity) {
	float remaining = 1.0 - age;
	float expansion = 1.0 - remaining * remaining * remaining;
	vec2 q = p / vec2(88.0, 73.0); // 与普通事件相同的椭圆横纵半径
	float radius = 0.95 + expansion * 0.42;
	float width = 0.11 + expansion * 0.14;
	// 包含边缘起伏与噪声的最大位移。界外透明度小于8位图像的半级。
	float reach = radius + 0.195 + width * 2.5;
	if (dot(q, q) > reach * reach) { return vec4(1000.0, 1.0, 0.0, 0.0); }
	float angle = atan(q.y, q.x);
	float curl = sin(angle * 12.0 + age * 3.0) * 0.05 + sin(angle * 19.0 - age * 2.0) * 0.025;
	float cloud = noise(p * 0.075 + vec2(age * 2.2, -age * 4.0));
	cloud = cloud * 0.65 + noise(p * 0.15 - age * 2.5) * 0.35;
	float distance = length(q) - radius - curl + (cloud - 0.5) * 0.24;
	float lobes = smoothstep(0.18 + age * 0.36, 0.72, cloud);
	float fade = lobes * opacity;
	return vec4(distance, width, fade, 0.72 + cloud * 0.48);
}
void fragment() {
	vec2 pixel = floor(UV * canvas_size / 2.0) * 2.0; // 两像素取样，保留烟团的像素颗粒
	vec2 p = pixel - canvas_origin;
	vec4 shape = vec4(1000.0, 1.0, 0.0, 0.0);
	for (int index = 0; index < puff_count; index++) {
		vec4 puff = puffs[index];
		vec4 next = puff_shape(p - puff.xy, puff.z, puff.w);
		// 椭圆取并集：只画合并后的外边界，重叠区域内部的圆环不再绘制。
		if (next.x < shape.x) { shape = next; }
	}
	float edge = shape.x / shape.y;
	float alpha = exp(-edge * edge) * shape.z;
	COLOR = vec4(dust_color.rgb * shape.w, alpha * dust_color.a);
}
