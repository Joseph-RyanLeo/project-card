shader_type canvas_item;

uniform sampler2D previous_texture : source_color, filter_nearest;
uniform float blend_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool use_rarity_blend = false; // 中央图标独立切图案时，额外与卡框共用品级颜色渐变
uniform sampler2D previous_rarity_texture : source_color, filter_nearest;
uniform sampler2D previous_rarity_previous_texture : source_color, filter_nearest;
uniform float rarity_blend_amount : hint_range(0.0, 1.0) = 1.0; // 与卡框相同的颜色过渡进度
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	// 同一层混合RGBA，两个不透明卡框之间的过渡仍保持不透明。
	vec4 current = mix(texture(previous_texture, UV), texture(TEXTURE, UV), blend_amount);
	if (use_rarity_blend) {
		vec4 previous = mix(texture(previous_rarity_previous_texture, UV), texture(previous_rarity_texture, UV), blend_amount);
		current = mix(previous, current, rarity_blend_amount);
	}
	COLOR = current * item_tint;
}
