shader_type canvas_item;
render_mode unshaded;

// 使用刮刀自身的透明轮廓刻出凹槽，不引入另一套位置和命中素材。
void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	float edge = texture(TEXTURE, UV - TEXTURE_PIXEL_SIZE).a;
	vec3 shade = mix(vec3(0.50, 0.35, 0.20), vec3(0.28, 0.18, 0.10), edge);
	COLOR = vec4(shade, alpha * 0.9);
}
