#include "res://shaders/pixel_gold_foil.gdshaderinc"

uniform sampler2D body_normal : hint_normal, filter_linear, repeat_disable;
uniform sampler2D gold_normal : hint_normal, filter_linear, repeat_disable;
uniform sampler2D body_height : filter_linear, repeat_disable;
uniform sampler2D body_regions : filter_nearest, repeat_disable;
uniform int debug_view = 0; // 0材质、1高度、2当前强度法线、3素色光照、4凹凸位置
uniform float body_strength = 0.65; // 袋身鼓起、封边和短折痕的凹凸强度
uniform float gold_strength = 0.45; // 金色图案的浅压纹强度
uniform float body_reflection_strength = 0.08; // 袋身柔和反射的亮度，随袋身滑块一起关闭
uniform float body_reflection_softness = 10.0; // 袋身反射的集中程度；数值越小，亮区越宽
uniform float body_reflection_width = 0.38; // 包装反射亮区占袋宽的比例
uniform float support_shadow_strength = 0.45; // 卡叠肩部按真实坡度计算的柔和明暗对比
uniform float support_highlight_strength = 0.065; // 肩部反射的提亮幅度，避免发光描边
uniform float light_angle_degrees = 60.0; // 固定光源所在方向：0右、90下、180左、270上
uniform float light_front = 0.2; // 光源偏向正面的程度，越小越贴着表面照射
uniform float light_brightness = 0.95; // 材质和素色光照的亮度倍率，0为关灯
uniform float light_mouse_influence = 0.8; // 默认80%鼠标反侧、20%固定方向；1完全使用鼠标反侧

vec3 relief_normal(vec3 packed_value, float strength) {
	vec3 n = packed_value * 2.0 - 1.0;
	return normalize(vec3(n.xy * strength, max(n.z, 0.01)));
}

vec4 pack_relief_color(vec4 source, vec2 uv, vec2 pointer_force) {
	bool is_gold = distance(source.rgb, PACK_GOLD) < 0.008
		|| distance(source.rgb, vec3(0.5764706, 0.4470588, 0.2117647)) < 0.008
		|| distance(source.rgb, vec3(1.0, 0.8274510, 0.5254902)) < 0.008;
	vec3 body = relief_normal(texture(body_normal, uv).rgb, body_strength);
	vec3 normal_value = body;
	if (is_gold) {
		vec3 gold = relief_normal(texture(gold_normal, uv).rgb, gold_strength);
		normal_value = normalize(vec3(body.xy / body.z + gold.xy / gold.z, 1.0));
	}
	// 固定方向以屏幕顺时针角度表达，再转换为Y向上的法线坐标。
	float light_angle = radians(light_angle_degrees);
	vec2 fixed_direction = vec2(cos(light_angle), -sin(light_angle));
	vec2 mouse_direction = vec2(-pointer_force.x, pointer_force.y);
	vec2 light_xy = mix(fixed_direction, mouse_direction, light_mouse_influence) * 0.85;
	vec3 light_direction = normalize(vec3(light_xy, light_front));
	// 烫金和宽反射也使用混合后的光源，鼠标比例为0时不再单独跟随鼠标扫光。
	vec2 lighting_force = vec2(-light_xy.x, light_xy.y) / 0.85;
	float flat_light = light_direction.z;
	float diffuse_delta = dot(normal_value, light_direction) - flat_light;
	vec3 color = pack_gold_foil(source.rgb, uv, lighting_force, 0.85);
	color *= clamp(1.0 + diffuse_delta * 0.85, 0.6, 1.35);
	vec3 halfway = normalize(light_direction + vec3(0.0, 0.0, 1.0));
	if (is_gold) {
		float specular_delta = pow(max(dot(normal_value, halfway), 0.0), 42.0)
			- pow(max(halfway.z, 0.0), 42.0);
		color += vec3(1.0, 0.83, 0.53) * specular_delta * 0.2;
	} else {
		// 反射由袋身法线决定，折痕会让宽亮区自然断开；深色描边保留清楚的像素轮廓。
		float ink_mask = smoothstep(0.06, 0.2, max(source.r, max(source.g, source.b)));
		float reflection = pow(max(dot(body, halfway), 0.0), body_reflection_softness);
		vec2 reflected_offset = uv - (vec2(0.5) - lighting_force * vec2(0.18, 0.15));
		reflected_offset += vec2(body.x, -body.y) * 0.25;
		reflection *= exp(-dot(reflected_offset / vec2(body_reflection_width, 0.8), reflected_offset / vec2(body_reflection_width, 0.8)));
		reflection *= body_reflection_strength * min(body_strength, 1.0) * ink_mask;
		color += vec3(0.82, 0.9, 1.0) * reflection;
	}
	// 局部凸脊与凹沟都由当前高度图重算，平坦区域不加入额外明暗。
	vec3 height_regions = texture(body_regions, uv).rgb;
	float shoulder = clamp(height_regions.g + height_regions.b, 0.0, 1.0) * min(body_strength, 1.0);
	// 保留XY分量的长度：正中或浅坡处自然减弱，避免归一化近零向量造成明暗翻转。
	float shoulder_facing = dot(body.xy, light_direction.xy);
	color *= 1.0 + shoulder_facing * shoulder * support_shadow_strength;
	float shoulder_reflection = max(shoulder_facing, 0.0) * shoulder * support_highlight_strength;
	// 向柔和亮色混合，而非额外叠加发光能量；保留包装原色和印刷细节。
	color = mix(color, max(color, vec3(0.9, 0.94, 1.0)), shoulder_reflection);
	if (debug_view == 1) {
		color = texture(body_height, uv).rgb;
	} else if (debug_view == 2) {
		color = body * 0.5 + 0.5;
	} else if (debug_view == 3) {
		// 使用同一袋身法线与光源，去掉文字和图案，直接观察卡叠四周的坡面。
		color = vec3(0.56, 0.59, 0.63) * (0.28 + max(dot(body, light_direction), 0.0) * 0.85);
		color += vec3(0.1) * pow(max(dot(body, halfway), 0.0), body_reflection_softness) * min(body_strength, 1.0);
	} else if (debug_view == 4) {
		vec3 regions = texture(body_regions, uv).rgb;
		color = mix(vec3(0.12), vec3(0.95, 0.65, 0.15), regions.r);
		color = mix(color, vec3(0.12, 0.85, 1.0), regions.g);
		color = mix(color, vec3(0.85, 0.22, 0.65), regions.b);
	}
	if (debug_view == 0 || debug_view == 3) {
		color *= light_brightness;
	}
	return vec4(color, source.a);
}
