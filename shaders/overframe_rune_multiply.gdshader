shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform sampler2D scrape_mask : filter_nearest;
uniform float layer_opacity = 0.55; // 对齐 Aseprite 的覆盖层不透明度
uniform vec2 pointer_force = vec2(0.0);
const float NORMAL_DEPTH = 2.2; // 灰色覆盖片轮廓的浮雕深度
const float NORMAL_STRENGTH = 0.34; // 检视时覆盖片的边缘明暗强度
varying vec2 rune_local_uv;
varying vec4 item_tint;

void vertex() {
	rune_local_uv = VERTEX / 23.0;
	item_tint = COLOR;
}

float cover_height(vec4 pixel) {
	return pixel.a * (0.5 + pixel.r * 0.5);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (source.a <= 0.0 || texture(scrape_mask, rune_local_uv).r > 0.5) {
		discard;
	}
	float tilt = min(length(pointer_force), 1.0);
	if (tilt > 0.0) {
		vec2 texel_x = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
		vec2 texel_y = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
		float slope_x = cover_height(texture(TEXTURE, UV + texel_x)) - cover_height(texture(TEXTURE, UV - texel_x));
		float slope_y = cover_height(texture(TEXTURE, UV + texel_y)) - cover_height(texture(TEXTURE, UV - texel_y));
		vec3 normal = normalize(vec3(-vec2(slope_x, slope_y) * NORMAL_DEPTH, 1.0));
		vec3 light = normalize(vec3(pointer_force * 1.8, 1.0));
		source.rgb = clamp(source.rgb + vec3((dot(normal, light) - light.z) * tilt * NORMAL_STRENGTH), vec3(0.0), vec3(1.0));
	}
	COLOR = vec4(mix(vec3(1.0), source.rgb * item_tint.rgb, source.a * item_tint.a * layer_opacity), 1.0);
}
