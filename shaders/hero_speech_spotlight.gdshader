shader_type canvas_item;
render_mode unshaded;
uniform vec4 canvas_region = vec4(0.0, 0.0, 1280.0, 720.0);
uniform vec4 spotlight = vec4(1120.0, 590.0, 120.0, 140.0); // 亮圈中心与横纵半径，覆盖英雄和气泡
uniform float soft_inner = 0.70; // 中央保持原亮度的范围
uniform float soft_outer = 1.18; // 向外过渡至背景暗度的范围
uniform float dim_opacity = 0.28; // 教学背景压暗强度
uniform bool speech_enabled = true;
uniform float speech_strength : hint_range(0.0, 1.0) = 1.0; // 控制英雄亮区淡入淡出，外围暗度保持连续
uniform bool use_backdrop_color = false; // 复用检视暗幕时保留该节点原有的颜色
uniform bool focus_enabled = false;
uniform vec4 focus_rect;
uniform float focus_breath = 0.0;
uniform bool use_silhouette = false;
uniform sampler2D focus_texture : filter_linear, repeat_disable;
uniform vec4 focus_region = vec4(0.0, 0.0, 1.0, 1.0); // 英雄当前帧在图集中的归一化区域
const vec3 GLOW_COLOR = vec3(1.0, 0.81, 0.43); // 教学呼吸光的暖金色
const float GLOW_RADIUS = 13.0; // 呼吸光最远扩散的逻辑像素距离

float inside_focus_sprite(vec2 uv) {
	vec2 contained = step(focus_region.xy, uv) * step(uv, focus_region.xy + focus_region.zw);
	return contained.x * contained.y;
}

void fragment() {
	vec2 point = canvas_region.xy + UV * canvas_region.zw;
	float radius = length((point - spotlight.xy) / max(spotlight.zw, vec2(1.0)));
	float dim = dim_opacity * (speech_enabled ? mix(1.0, smoothstep(soft_inner, soft_outer, radius), speech_strength) : 1.0);
	float glow = 0.0;
	if (focus_enabled) {
		vec2 half_size = focus_rect.zw * 0.5;
		vec2 center_delta = abs(point - focus_rect.xy - half_size) - half_size;
		if (use_silhouette) {
			if (max(center_delta.x, center_delta.y) < GLOW_RADIUS) {
				vec2 local = (point - focus_rect.xy) / focus_rect.zw;
				vec2 texel = focus_region.zw / focus_rect.zw;
				vec2 sprite_uv = focus_region.xy + local * focus_region.zw;
				vec2 lo = focus_region.xy + texel * 0.5;
				vec2 hi = focus_region.xy + focus_region.zw - texel * 0.5;
				float center = texture(focus_texture, clamp(sprite_uv, lo, hi)).a;
				center *= inside_focus_sprite(sprite_uv);
				float halo = 0.0;
				for (int direction = 0; direction < 12; direction++) {
					float angle = float(direction) * TAU / 12.0;
					vec2 ray = vec2(cos(angle), sin(angle)) * texel;
					vec2 near_uv = sprite_uv + ray * (3.0 + focus_breath);
					vec2 far_uv = sprite_uv + ray * (7.0 + focus_breath * 2.5);
					float near_alpha = texture(focus_texture, clamp(near_uv, lo, hi)).a * inside_focus_sprite(near_uv);
					float far_alpha = texture(focus_texture, clamp(far_uv, lo, hi)).a * inside_focus_sprite(far_uv);
					halo += near_alpha * 0.7 + far_alpha * 0.3;
				}
				halo /= 12.0;
				dim *= 1.0 - max(center, smoothstep(0.0, 0.62, halo) * 0.9);
				glow = smoothstep(0.015, 0.48, halo) * (1.0 - center);
			}
		} else {
			// 普通控件保留亮区，圆角距离场让高光在目标边缘向外自然衰减。
			float corner = min(6.0, min(half_size.x, half_size.y));
			vec2 d = center_delta + vec2(corner);
			float edge = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner;
			dim *= smoothstep(0.0, GLOW_RADIUS, edge);
			glow = smoothstep(-2.0, 0.0, edge) * (1.0 - smoothstep(0.0, 7.0 + 4.0 * focus_breath, edge));
		}
	}
	glow *= mix(0.25, 0.56, focus_breath);
	float alpha = glow + dim * (1.0 - glow);
	// 外部的节点淡入淡出也作用于光晕；暗幕本身的透明度单独传入。
	vec3 dim_color = use_backdrop_color ? COLOR.rgb : vec3(0.0);
	COLOR = vec4((GLOW_COLOR * glow + dim_color * dim * (1.0 - glow)) / max(alpha, 0.0001), alpha * COLOR.a);
}
