shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/pixel_gold_foil.gdshaderinc"

// 采用翻页参考的折线、圆柱弯曲、翻折背面三部分；所有几何计算在原图像素空间完成。
uniform float peel_progress : hint_range(0.0, 1.0) = 0.0; // 上半封皮揭开的比例
uniform float peel_angle_degrees = 0.0; // 翻皮相对向上的左右偏转角度，脚本限制范围
uniform float curl_radius = 6.0; // 折线连接正反两面的最大弯曲半径，单位为原图像素
uniform vec2 draw_padding = vec2(100.0, 150.0); // 顶点扩展范围，容纳翻到原图外的封皮背面
uniform vec2 pointer_force = vec2(0.0); // 检视鼠标位置驱动金边反光
uniform bool use_foil = true;
uniform float foil_strength = 0.85; // 金边反光的亮度
uniform vec3 gold_color = vec3(0.7529412, 0.5960784, 0.3215686);
uniform vec3 back_color = vec3(0.39, 0.20, 0.14); // 封皮背面的棕色

void vertex() {
	// shader可以改变取样，却不能在原四边形之外绘制；同步扩展顶点和UV保留原图位置。
	vec2 extra = (UV - vec2(0.5)) * 2.0 * draw_padding;
	VERTEX += extra;
	UV += extra * TEXTURE_PIXEL_SIZE;
}

vec4 sample_page(sampler2D page_texture, vec2 point, vec2 image_size) {
	vec2 uv = point / image_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) {
		return vec4(0.0);
	}
	return texture(page_texture, uv);
}

vec4 front_color(sampler2D page_texture, vec2 point, vec2 image_size, float shade) {
	vec4 source = sample_page(page_texture, point, image_size);
	vec2 sample_uv = point / image_size;
	vec3 output_color = source.rgb;
	if (use_foil && distance(source.rgb, gold_color) < 0.008) {
		output_color = pixel_gold_foil(source.rgb, sample_uv, pointer_force, foil_strength);
	}
	return vec4(output_color * shade, source.a);
}

vec4 over(vec4 bottom, vec4 top) {
	float alpha = top.a + bottom.a * (1.0 - top.a);
	if (alpha <= 0.0001) return vec4(0.0);
	return vec4((top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / alpha, alpha);
}

void fragment() {
	vec2 image_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 point = UV * image_size;
	vec4 result = vec4(0.0);
	if (peel_progress <= 0.0001) {
		result = front_color(TEXTURE, point, image_size, 1.0);
	} else if (peel_progress < 0.9999) {
		float angle = radians(peel_angle_degrees);
		vec2 normal = vec2(-sin(angle), cos(angle));
		// 用投影定义可旋转折线，不需要除以方向分量；水平/竖直方向同样有效。
		float low = min(0.0, normal.x * image_size.x);
		float high = max(0.0, normal.x * image_size.x) + normal.y * image_size.y;
		float radius = max(0.001, curl_radius * sin(peel_progress * PI));
		float fold = mix(high, low - radius, peel_progress);
		float distance_to_fold = dot(point, normal) - fold;
		if (distance_to_fold <= 0.0) {
			result = front_color(TEXTURE, point, image_size, 1.0);
			// 完整翻折背面：越过半圆弯曲后继续向折线内侧展开，不能只绘制狭窄卷边。
			vec2 back_point = point + normal * (PI * radius - 2.0 * distance_to_fold);
			vec4 back = sample_page(TEXTURE, back_point, image_size);
			result = over(result, vec4(back_color, back.a));
		} else if (distance_to_fold <= radius) {
			float arc_angle = asin(clamp(distance_to_fold / radius, 0.0, 1.0));
			float shade = mix(0.55, 1.0, cos(arc_angle));
			vec2 front_point = point + normal * (radius * arc_angle - distance_to_fold);
			result = front_color(TEXTURE, front_point, image_size, shade);
			vec2 back_point = point + normal * (radius * (PI - arc_angle) - distance_to_fold);
			vec4 back = sample_page(TEXTURE, back_point, image_size);
			result = over(result, vec4(back_color * shade, back.a));
		}
	}
	COLOR = result;
}
