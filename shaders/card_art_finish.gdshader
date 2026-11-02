shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/card_finish.gdshaderinc"
#include "res://shaders/card_projection.gdshaderinc"

uniform vec2 pointer_force = vec2(0.0);
uniform bool background_layer = false;
uniform bool use_3d = false;
uniform float max_tilt_degrees = 10.0; // 与整卡共用的最大倾角，不额外叠加旋转
uniform float fov = 72.0; // 与整卡共用的透视视野角
uniform float layer_depth = 0.0; // 图层距卡框平面的深度；正数在前，负数在后，单位为原生像素
uniform vec2 projection_size = vec2(129.0, 155.0); // 整卡合成画布的原生尺寸，与外层投影坐标一致
uniform vec2 card_origin = vec2(0.0); // 卡牌在合成画布中的位置，包含图标安全边
uniform vec2 layer_size = vec2(1.0); // 当前图层的原生绘制尺寸，用于还原素材坐标
uniform bool embossed = false;
uniform bool has_normal_texture = false;
uniform sampler2D surface_normal : hint_normal, filter_nearest;
uniform float effect_strength = 0.75; // 浮雕明暗和局部反光的强度
uniform float texture_density = 42.0; // 细密压纹线条的重复密度
uniform int card_finish = -1; // 2为全息；碎闪由合成后的整卡材质统一处理
uniform vec2 layer_origin = vec2(0.0); // 当前图层在卡面中的原生像素起点
uniform vec2 card_size = vec2(99.0, 136.0); // 共用卡面坐标，让两层材质纹理接续
varying vec4 item_modulate;
varying vec2 finish_position;

vec3 depth_projection(vec2 force) {
	if (!use_3d || abs(layer_depth) < 0.001) { return vec3(1.0, 0.0, 0.0); }
	mat3 rotation = card_inverse_rotation(force, max_tilt_degrees);
	float camera_distance = 0.5 / tan(radians(fov) * 0.5) + 0.5;
	vec3 camera = -camera_distance * rotation[2];
	float z = -layer_depth / max(projection_size.x, projection_size.y);
	float fraction = z / camera.z;
	// 抵消正面姿态的远近缩放，保留原取景；倾斜时仍按真实深度求交。
	float rest_scale = 1.0 + z / camera_distance;
	return vec3((1.0 - fraction) / rest_scale, fraction * camera.xy / rest_scale);
}

vec2 source_position(vec2 point, vec3 projection) {
	vec2 centered = (point + card_origin) / projection_size - vec2(0.5);
	return (centered * projection.x + projection.yz + vec2(0.5)) * projection_size - card_origin;
}

void vertex() {
	item_modulate = COLOR;
	if (!background_layer && use_3d && abs(layer_depth) > 0.001) {
		vec3 projection = depth_projection(pointer_force);
		vec2 centered = (VERTEX + layer_origin + card_origin) / projection_size - vec2(0.5);
		VERTEX = ((centered - projection.yz) / projection.x + vec2(0.5)) * projection_size
			- card_origin - layer_origin;
	}
	finish_position = VERTEX + layer_origin;
}

float relief_height(vec4 color) {
	return (0.65 + dot(color.rgb, vec3(0.299, 0.587, 0.114)) * 0.35) * color.a;
}

void fragment() {
	vec3 projection = depth_projection(pointer_force);
	vec2 original_position = finish_position;
	vec2 uv = UV;
	if (use_3d && abs(layer_depth) > 0.001) {
		original_position = source_position(finish_position, projection);
		uv = (original_position - layer_origin) / max(layer_size, vec2(1.0));
	}
	if (background_layer && use_3d && abs(layer_depth) > 0.001) {
		// 抵消内层额外的缩放，只保留深度偏移；整体透视继续由外层统一处理。
		uv = (uv - vec2(0.5)) / projection.x + vec2(0.5);
		// 原图保持原倍率；移出素材的窄边用边缘像素延展，不通过放大裁切来遮空。
		uv = clamp(uv, TEXTURE_PIXEL_SIZE * 0.5, vec2(1.0) - TEXTURE_PIXEL_SIZE * 0.5);
		original_position = layer_origin + uv * layer_size;
	}
	vec4 source = texture(TEXTURE, uv);
	vec3 output_color = source.rgb;
	vec2 finish_uv = original_position / max(card_size, vec2(1.0));
	if (card_finish == 2) {
		output_color = holographic_finish(output_color, finish_uv, pointer_force, effect_strength, texture_density);
	}
	if (embossed) {
		vec3 normal;
		if (has_normal_texture) {
			normal = normalize(texture(surface_normal, uv).rgb * 2.0 - 1.0);
		} else {
			// 无手绘法线时，以轮廓和亮度生成可用的浮雕；并非角色的真实几何。
			vec2 step_uv = TEXTURE_PIXEL_SIZE;
			float dx = relief_height(texture(TEXTURE, clamp(uv + vec2(step_uv.x, 0.0), vec2(0.0), vec2(1.0))))
				- relief_height(texture(TEXTURE, clamp(uv - vec2(step_uv.x, 0.0), vec2(0.0), vec2(1.0))));
			float dy = relief_height(texture(TEXTURE, clamp(uv + vec2(0.0, step_uv.y), vec2(0.0), vec2(1.0))))
				- relief_height(texture(TEXTURE, clamp(uv - vec2(0.0, step_uv.y), vec2(0.0), vec2(1.0))));
			normal = normalize(vec3(-dx * 3.5, dy * 3.5, 1.0));
		}
		float groove = sin((uv.x + uv.y * 0.55) * texture_density * 6.283185);
		normal = normalize(normal + vec3(groove * 0.13, groove * 0.07, 0.0));
		vec3 light = normalize(vec3(pointer_force.x * 1.2 + 0.15, -pointer_force.y * 1.2 - 0.2, 1.0));
		float diffuse = max(dot(normal, light), 0.0);
		float specular = pow(max(dot(normal, normalize(light + vec3(0.0, 0.0, 1.0))), 0.0), 48.0);
		output_color *= mix(1.0, 0.7 + diffuse * 0.32, effect_strength);
		output_color += finish_spectrum(dot(normal.xy, light.xy) * 1.7 + uv.y * 0.2)
			* specular * effect_strength * 0.4;
	}
	COLOR = vec4(output_color, source.a) * item_modulate;
}
