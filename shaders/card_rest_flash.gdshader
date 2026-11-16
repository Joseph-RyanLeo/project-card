shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://shaders/card_finish.gdshaderinc"

uniform int flash_type = 0;
uniform bool use_fractured = false;
uniform float finish_strength = 0.75; // 与检视共用碎闪强度
uniform float finish_density = 32.0; // 与检视共用固定晶片密度
uniform float fractured_brightness = 1.0; // 碎闪晶片高光的明度倍率
uniform float fractured_saturation = 0.55; // 碎闪晶片彩色反光相对白光的比例
uniform float fractured_hue_degrees = 0.0; // 碎闪晶片整体色相旋转角度
uniform vec2 pointer_force = vec2(0.0);
uniform vec2 flash_direction_force = vec2(0.0); // 最近一次有效鼠标方向，中心附近保持上次光带角度
uniform vec2 mask_origin_px = vec2(18.0);
uniform vec2 mask_size_px = vec2(99.0, 136.0);
uniform vec2 texture_size_px = vec2(135.0, 172.0);
uniform float stripe_spacing = 14.0; // 与检视相同的光带间距
uniform float stripe_width = 10.0; // 与检视相同的光带宽度曲线
uniform float flash_intensity = 0.2; // 与检视相同的静止反光亮度
uniform float flash_offset = 0.0; // 闪纹平移相位，1为一个重复周期
uniform float flash_angle_degrees = 50.0; // 尚无有效鼠标方向时的默认光带角度
varying vec4 item_modulate;

void vertex() { item_modulate = COLOR; }

void fragment() {
	vec3 light;
	if (use_fractured) {
		vec2 card_uv = (UV * texture_size_px - mask_origin_px) / mask_size_px;
		light = fractured_finish(vec3(0.0), card_uv, pointer_force, finish_strength, finish_density, fractured_brightness, fractured_saturation, fractured_hue_degrees);
	} else {
		light = card_flash_light(UV, pointer_force, flash_direction_force, texture_size_px, flash_type, stripe_spacing, stripe_width, flash_intensity, flash_angle_degrees, flash_offset);
	}
	COLOR = vec4(light * item_modulate.rgb, texture(TEXTURE, UV).a * item_modulate.a);
}
