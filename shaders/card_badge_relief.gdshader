shader_type canvas_item;
render_mode unshaded;

uniform sampler2D badge_texture : source_color, filter_nearest;
uniform sampler2D shadow_texture : filter_linear, repeat_disable; // 独立连续采样投影；原图仍保留最近邻像素
uniform vec2 source_size = vec2(1.0); // 独立图标素材尺寸，用于按原图像素取样
uniform vec2 draw_size = vec2(1.0); // 图标实际绘制尺寸，保留原有缩放与居中
uniform vec2 draw_origin = vec2(0.0); // 原图在TextureRect内的居中偏移
uniform vec2 pointer_force = vec2(0.0);
uniform bool relief_enabled = true;
uniform float padding_pixels = 3.0; // 给轮廓外的投影保留3个原生像素
uniform float normal_strength = 2.4; // 轮廓与表面亮度生成的法线起伏强度
uniform float light_strength = 0.55; // 局部明暗强度；保留原图标识色
uniform float shadow_opacity = 0.46; // 图标投在卡面上的阴影透明度
uniform vec2 shadow_rest_offset = vec2(0.8, 1.15); // 鼠标居中时阴影向右下偏移的原生像素量
uniform float shadow_travel = 0.65; // 阴影随光源反向移动的原生像素量
varying vec2 badge_uv;
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
	// 用绘制几何恢复0～1坐标；不依赖图集UV，避免类别图标采到相邻图片。
	vec2 local_uv = (VERTEX - draw_origin) / max(draw_size, vec2(1.0));
	VERTEX += (local_uv - vec2(0.5)) * padding_pixels * 2.0;
	badge_uv = local_uv * (vec2(1.0) + padding_pixels * 2.0 / max(draw_size, vec2(1.0)))
		- padding_pixels / max(draw_size, vec2(1.0));
}

float badge_height(vec4 color) {
	return color.a * (0.8 + dot(color.rgb, vec3(0.299, 0.587, 0.114)) * 0.2);
}

float inside_badge(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

void fragment() {
	vec4 base = texture(badge_texture, clamp(badge_uv, vec2(0.0), vec2(1.0)));
	base.a *= inside_badge(badge_uv);
	float shadow_alpha = 0.0;
	if (relief_enabled) {
		vec2 step_uv = 1.0 / max(source_size, vec2(1.0));
		vec2 left = badge_uv - vec2(step_uv.x, 0.0);
		vec2 right = badge_uv + vec2(step_uv.x, 0.0);
		vec2 up = badge_uv - vec2(0.0, step_uv.y);
		vec2 down = badge_uv + vec2(0.0, step_uv.y);
		float dx = badge_height(texture(badge_texture, clamp(right, vec2(0.0), vec2(1.0)))) * inside_badge(right)
			- badge_height(texture(badge_texture, clamp(left, vec2(0.0), vec2(1.0)))) * inside_badge(left);
		float dy = badge_height(texture(badge_texture, clamp(down, vec2(0.0), vec2(1.0)))) * inside_badge(down)
			- badge_height(texture(badge_texture, clamp(up, vec2(0.0), vec2(1.0)))) * inside_badge(up);
		vec3 normal = normalize(vec3(-dx * normal_strength, -dy * normal_strength, 1.0));
		vec3 light = normalize(vec3(pointer_force.x * 0.85 - 0.35, pointer_force.y * 0.85 - 0.45, 1.0));
		float diffuse = max(dot(normal, light), 0.0);
		vec3 half_direction = normalize(light + vec3(0.0, 0.0, 1.0));
		float specular = pow(max(dot(normal, half_direction), 0.0), 24.0);
		base.rgb *= mix(1.0, 0.65 + diffuse * 0.4, light_strength);
		// 高光按原图亮度调节，黑色描边不会被漂白。
		float luminance = dot(base.rgb, vec3(0.299, 0.587, 0.114));
		base.rgb += vec3(specular * light_strength * 0.16 * smoothstep(0.06, 0.5, luminance));
		vec2 offset = shadow_rest_offset - pointer_force * shadow_travel;
		vec2 shadow_uv = badge_uv - offset / max(draw_size, vec2(1.0));
		vec2 padded_shadow_uv = (shadow_uv * source_size + vec2(1.0))
			/ vec2(textureSize(shadow_texture, 0));
		shadow_alpha = texture(shadow_texture, padded_shadow_uv).a * shadow_opacity;
	}
	float alpha = base.a + shadow_alpha * (1.0 - base.a);
	vec3 color = (base.rgb * base.a + vec3(0.025, 0.02, 0.035) * shadow_alpha * (1.0 - base.a))
		/ max(alpha, 0.0001);
	COLOR = vec4(color, alpha) * item_modulate;
}
