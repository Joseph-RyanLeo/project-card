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
uniform vec4 focus_regions[12];
uniform int focus_region_count = 0;
uniform float focus_breath = 0.0;
uniform float focus_glow_gain = 1.0; // 单独高亮目标时补足原本由暗幕提供的对比
uniform bool use_silhouette = false;
uniform sampler2D focus_texture : filter_linear, repeat_disable;
uniform vec4 focus_region = vec4(0.0, 0.0, 1.0, 1.0); // 英雄当前帧在图集中的归一化区域
uniform vec2 focus_texture_pixel = vec2(1.0);
uniform vec4 canvas_to_focus_axes = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 canvas_to_focus_origin = vec2(0.0);
uniform vec2 focus_sprite_size = vec2(1.0);
const vec3 GLOW_COLOR = vec3(1.0, 0.81, 0.43); // 教学呼吸光的暖金色
const float GLOW_RADIUS = 17.0; // 呼吸光最远扩散的逻辑像素距离
const float INNER_PIXEL = 1.0; // 目标轮廓内跟着亮起的一圈逻辑像素

float inside_focus_sprite(vec2 uv) {
	vec2 contained = step(focus_region.xy, uv) * step(uv, focus_region.xy + focus_region.zw);
	return contained.x * contained.y;
}

vec2 focus_local_vector(vec2 canvas_vector) {
	return vec2(dot(canvas_vector, canvas_to_focus_axes.xy), dot(canvas_vector, canvas_to_focus_axes.zw));
}

float focus_edge(vec2 point, vec4 rect) {
	vec2 half_size = rect.zw * 0.5;
	vec2 delta = abs(point - rect.xy - half_size) - half_size;
	float corner = min(6.0, min(half_size.x, half_size.y));
	vec2 d = delta + vec2(corner);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner;
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
				vec2 local = (focus_local_vector(point) + canvas_to_focus_origin) / focus_sprite_size;
				vec2 sprite_uv = focus_region.xy + local * focus_region.zw;
				vec2 lo = focus_region.xy + focus_texture_pixel * 0.5;
				vec2 hi = focus_region.xy + focus_region.zw - focus_texture_pixel * 0.5;
				float center = texture(focus_texture, clamp(sprite_uv, lo, hi)).a;
				center *= inside_focus_sprite(sprite_uv);
				float halo = 0.0;
				float inner = 1.0;
				for (int direction = 0; direction < 12; direction++) {
					float angle = float(direction) * TAU / 12.0;
					vec2 ray = focus_local_vector(vec2(cos(angle), sin(angle))) / focus_sprite_size * focus_region.zw;
					vec2 inner_uv = sprite_uv + ray * INNER_PIXEL;
					vec2 near_uv = sprite_uv + ray * (4.0 + focus_breath);
					vec2 far_uv = sprite_uv + ray * (10.0 + focus_breath * 4.0);
					inner = min(inner, texture(focus_texture, clamp(inner_uv, lo, hi)).a * inside_focus_sprite(inner_uv));
					float near_alpha = texture(focus_texture, clamp(near_uv, lo, hi)).a * inside_focus_sprite(near_uv);
					float far_alpha = texture(focus_texture, clamp(far_uv, lo, hi)).a * inside_focus_sprite(far_uv);
					halo += near_alpha * 0.7 + far_alpha * 0.3;
				}
				halo /= 12.0;
				dim *= 1.0 - max(center, smoothstep(0.0, 0.62, halo) * 0.9);
				glow = max(center * (1.0 - inner), smoothstep(0.015, 0.48, halo) * (1.0 - center));
			}
		} else {
			// 普通控件保留亮区，圆角距离场让高光在目标边缘向外自然衰减。
			float edge = focus_region_count == 0 ? focus_edge(point, focus_rect) : focus_edge(point, focus_regions[0]);
			for (int index = 1; index < focus_region_count; index++) {
				edge = min(edge, focus_edge(point, focus_regions[index]));
			}
			dim *= smoothstep(0.0, GLOW_RADIUS, edge);
			glow = smoothstep(-INNER_PIXEL, 0.0, edge) * (1.0 - smoothstep(0.0, 11.0 + 5.0 * focus_breath, edge));
		}
	}
	glow = min(1.0, glow * mix(0.25, 0.56, focus_breath) * focus_glow_gain);
	float alpha = glow + dim * (1.0 - glow);
	// 外部的节点淡入淡出也作用于光晕；暗幕本身的透明度单独传入。
	vec3 dim_color = use_backdrop_color ? COLOR.rgb : vec3(0.0);
	COLOR = vec4((GLOW_COLOR * glow + dim_color * dim * (1.0 - glow)) / max(alpha, 0.0001), alpha * COLOR.a);
}
