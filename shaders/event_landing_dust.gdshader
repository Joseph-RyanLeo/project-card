shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dust_color : source_color = vec4(0.49, 0.44, 0.35, 0.60); // 烟尘底色与最大不透明度

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	// 在逻辑画布上按两像素取样，让柔软烟团保留可见像素颗粒。
	vec2 pixel = floor(UV * vec2(326.0, 276.0) / 2.0) * 2.0;
	vec2 p = pixel - vec2(163.0, 138.0) + vec2(0.0, progress * 14.0);
	vec2 q = p / vec2(88.0, 73.0);
	float angle = atan(q.y, q.x);
	float expansion = 1.0 - pow(1.0 - progress, 3.0);
	float curl = sin(angle * 12.0 + progress * 3.0) * 0.05 + sin(angle * 19.0 - progress * 2.0) * 0.025;
	float radius = 0.95 + expansion * 0.42 + curl;
	float cloud = noise(p * 0.075 + vec2(progress * 2.2, -progress * 4.0));
	cloud = cloud * 0.65 + noise(p * 0.15 - progress * 2.5) * 0.35;
	float width = 0.11 + expansion * 0.14;
	float ring = exp(-pow((length(q) - radius + (cloud - 0.5) * 0.24) / width, 2.0));
	float lobes = smoothstep(0.18 + progress * 0.36, 0.72, cloud);
	float alpha = ring * lobes * smoothstep(0.0, 0.06, progress) * pow(1.0 - progress, 0.65);
	COLOR = vec4(dust_color.rgb * (0.72 + cloud * 0.48), alpha * dust_color.a);
}
