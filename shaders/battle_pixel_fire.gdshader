shader_type canvas_item;
render_mode unshaded;

uniform vec2 effect_size = vec2(128.0, 160.0); // 火焰绘制区域的逻辑像素尺寸
uniform float pixel_size = 2.0; // 火焰色块的逻辑像素大小
uniform float effect_time = 0.0; // 从战斗或预览的可暂停时钟传入
uniform float flow_speed = 1.6; // 向上流动的速度
uniform float flow_frequency = 5.0; // 向上流动的两层噪声密度，同时塑造焰尖与内部色块
uniform float warp_strength = 0.10; // 火苗左右摆动幅度
uniform float intensity = 1.0; // 多份灼烧叠加时的外观强度
uniform float pulse_strength = 0.0; // 每跳及终结时的短促增强
uniform float opacity = 1.0; // 出现和预览结束时的整体透明度
uniform bool foreground = false; // 前景只显示卡外火团接入卡面的一小部分
uniform vec4 card_rect = vec4(16.0, 18.0, 100.0, 136.0); // 卡牌在火焰画布内的位置和尺寸
uniform float foreground_depth = 14.0; // 外侧火团向卡内延伸的最大像素，脚本按卡牌倍率缩放
uniform float foreground_tip_depth = 14.0; // 内侧焰尖额外伸入的最大像素，脚本按卡牌倍率缩放
uniform float canvas_width_scale = 2.0; // 背景画布左右留白，火焰仍维持原来的实际尺寸
const float INWARD_RATIO = 0.65; // 卡外火团越厚，向卡内延伸越深的比例
const float INNER_TIP_SPACING_RATIO = 1.5; // 内层焰尖间距相对主体深度的比例，拉长焰尖不会使其变稀
const float SIDE_FOLD_LIFT_RATIO = 1.6; // 侧焰向卡内每深入1像素，对应从下方多少像素的外焰翻卷上来
const float INNER_RISE_SPEED_RATIO = 1.25; // 内层噪声与侧边火舌沿屏幕向上移动的速度，相对主体深度
const float INNER_COLOR_DEPTH_RATIO = 0.5; // 内侧暗边、主体到亮区的总厚度，相对主体深度
// 取自用户参考图下方四块色板的中央颜色：暗边、主体、热区、亮芯。
const vec3 DARK = vec3(109.0, 66.0, 57.0) / 255.0;
const vec3 BODY = vec3(167.0, 95.0, 73.0) / 255.0;
const vec3 HOT = vec3(212.0, 156.0, 107.0) / 255.0;
const vec3 CORE = vec3(236.0, 208.0, 160.0) / 255.0;
const float BODY_HALF_WIDTH = 0.48; // 下部火焰主体的最大半宽
const float TIP_START_HEIGHT = 0.30; // 从底部起多高开始向主焰尖收窄
const float TIP_END_HEIGHT = 0.96; // 主焰尖的最高归一化位置，给画布顶部留白
const float BASE_ROUND_HEIGHT = 0.18; // 圆弧底部占火焰绘制高度的比例

float hash_value(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 weight = local * local * (3.0 - 2.0 * local);
	return mix(mix(hash_value(cell), hash_value(cell + vec2(1, 0)), weight.x),
		mix(hash_value(cell + vec2(0, 1)), hash_value(cell + vec2(1, 1)), weight.x), weight.y);
}

// 上下层统一使用背景火团的轮廓、噪声与热度；返回轮廓值、热度和可见性。
vec3 flame_shape(vec2 uv) {
	float height = 1.0 - uv.y;
	vec2 noise_uv = vec2(uv.x * flow_frequency * 0.75, height * 3.5 - effect_time * flow_speed * 1.5);
	float broad_noise = noise(noise_uv);
	float fine_noise = noise(noise_uv * vec2(1.9, 1.7) + vec2(5.7, 2.3));
	float n = mix(broad_noise, fine_noise, 0.28);
	// 下宽上窄的整体底形只生成一次；上行噪声侵蚀边界，形成会弯折、断开的焰尖。
	float tip = clamp((height - TIP_START_HEIGHT) / (TIP_END_HEIGHT - TIP_START_HEIGHT), 0.0, 1.0);
	float base_cap = sqrt(max(1.0 - pow(max((BASE_ROUND_HEIGHT - height) / BASE_ROUND_HEIGHT, 0.0), 2.0), 0.0));
	float growth = 1.0 + clamp((intensity - 1.0) * 0.08 + pulse_strength * 0.025, 0.0, 0.06);
	float half_width = BODY_HALF_WIDTH * pow(1.0 - tip, 0.8) * base_cap * growth;
	float sway = sin(height * 5.0 - effect_time * flow_speed * 1.4) * warp_strength * height;
	float center = 0.5 - 0.11 * height * height + sway;
	float tip_envelope = 1.0 - smoothstep(0.75, 1.0, tip);
	float erosion = (n - 0.48) * mix(0.12, 0.65, height) * (0.65 + warp_strength * 2.0) * tip_envelope;
	float field = half_width - abs(uv.x - center) - erosion;
	// 热区与亮芯主要留在下部，避免上端变成一根等亮的圆柱。
	float heat = field / max(half_width, 0.01) * 0.65 + (n - 0.5) * 0.75 + 0.15 + uv.y * 0.10 + pulse_strength * 0.06;
	heat -= smoothstep(0.40, 0.90, height) * 0.55;
	heat = min(heat, 1.0 - smoothstep(0.45, 0.85, height) * 0.80);
	float visible = step(0.0, field) * step(height, TIP_END_HEIGHT) * step(0.01, height);
	return vec3(field, heat, visible);
}

vec2 flame_uv(vec2 point) {
	vec2 uv = point / effect_size;
	uv.x = (uv.x - 0.5) * canvas_width_scale + 0.5;
	return uv;
}

vec3 flame_color(float heat) {
	return heat < 0.22 ? DARK : (heat < 0.48 ? BODY : (heat < 0.75 ? HOT : CORE));
}

void fragment() {
	vec2 point = (floor(UV * effect_size / pixel_size) + vec2(0.5)) * pixel_size;
	vec3 shape = flame_shape(flame_uv(point));
	float visible = shape.z;
	float heat = shape.y;
	if (foreground) {
		vec2 offset = point - card_rect.xy;
		vec2 remaining = card_rect.zw - offset;
		float edge = min(min(offset.x, remaining.x), remaining.y);
		// 只从左右和底边接入；顶部不沿卡框额外生成一圈火苗。
		vec2 outside = point;
		if (offset.x <= remaining.x && offset.x <= remaining.y) {
			outside.x = card_rect.x - pixel_size * 0.5;
		} else if (remaining.x <= remaining.y) {
			outside.x = card_rect.x + card_rect.z + pixel_size * 0.5;
		} else {
			outside.y = card_rect.y + card_rect.w + pixel_size * 0.5;
		}
		outside = (floor(outside / pixel_size) + vec2(0.5)) * pixel_size;
		vec3 contact = flame_shape(flame_uv(outside));
		float overhang = max(contact.x, 0.0) * effect_size.x / canvas_width_scale;
		// 平滑收束深度，避免厚火团被固定宽度切成一条笔直的卡框装饰。
		float depth = foreground_depth * (1.0 - exp(-overhang * INWARD_RATIO / foreground_depth));
		bool from_side = min(offset.x, remaining.x) <= remaining.y;
		float rise = effect_time * flow_speed * foreground_depth * INNER_RISE_SPEED_RATIO;
		float spacing = max(foreground_depth * INNER_TIP_SPACING_RATIO, pixel_size);
		float rim_distance = (depth - edge);
		if (from_side) {
			// 把真实外焰连续地翻到卡面前；不再按固定间距生成独立火舌。
			float fold_strength = foreground_tip_depth / max(foreground_depth, pixel_size);
			float fold_scale = exp(max(edge, 0.0) / foreground_depth);
			float outward = foreground_depth * (fold_scale - 1.0) * INWARD_RATIO / max(fold_strength, 0.01);
			vec2 folded_point = outside;
			folded_point.x += (offset.x <= remaining.x ? -1.0 : 1.0) * outward;
			folded_point.y += max(edge, 0.0) * SIDE_FOLD_LIFT_RATIO * fold_strength;
			folded_point = (floor(folded_point / pixel_size) + vec2(0.5)) * pixel_size;
			vec3 folded = flame_shape(flame_uv(folded_point));
			vec2 root = vec2(outside.x, folded_point.y);
			vec3 root_contact = flame_shape(flame_uv(root));
			float fold_field = folded.x * effect_size.x / canvas_width_scale / max(fold_scale * INWARD_RATIO, 1.0);
			fold_field = mix(-effect_size.y, fold_field, folded.z * root_contact.z);
			// 有限的内侧区域自然收束；原来的主体只负责与卡外接触处保持连续。
			fold_field = min(fold_field, foreground_depth + foreground_tip_depth - edge);
			float body_field = mix(-effect_size.y, min(rim_distance, shape.x * effect_size.x / canvas_width_scale), contact.z * shape.z);
			rim_distance = max(body_field, fold_field);
		} else {
			// 底部火舌固定根部X位置；噪声只沿Y向上流动，不再沿卡底横向滑动。
			float tip_noise = noise(vec2(point.x / spacing * 0.65, (point.y + rise) / spacing * 0.8));
			float triangle = 1.0 - abs(fract(point.x / spacing + tip_noise * 0.35) * 2.0 - 1.0);
			float amplitude = (0.7 + tip_noise * 0.3) * smoothstep(0.0, max(foreground_tip_depth, pixel_size), overhang);
			depth += foreground_tip_depth * pow(triangle, 2.5) * amplitude;
			float slope = foreground_tip_depth * amplitude * 2.5 * pow(triangle, 1.5) * 2.0 / spacing;
			rim_distance = (depth - edge) / sqrt(1.0 + slope * slope);
			rim_distance = mix(-effect_size.y, min(rim_distance, shape.x * effect_size.x / canvas_width_scale), contact.z * shape.z);
		}
		float color_depth = max(foreground_depth * INNER_COLOR_DEPTH_RATIO, pixel_size * 3.0);
		// 用外层的同一色板：暗边→主体→亮区；亮区也在尖端前收束，不填成一块色。
		heat = clamp(rim_distance / color_depth, 0.0, 1.0) * 0.70;
		float inside_card = step(0.0, min(offset.x, offset.y)) * step(0.0, min(remaining.x, remaining.y));
		visible = inside_card * step(0.0, rim_distance);
	}
	vec3 color = flame_color(heat);
	COLOR = vec4(color, visible * opacity);
}
