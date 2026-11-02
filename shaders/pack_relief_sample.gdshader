shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/card_projection.gdshaderinc"
#include "res://shaders/pack_relief.gdshaderinc"

uniform bool use_3d = true;
uniform float fov = 72.0; // 与共用检视表面保持一致的透视视角
uniform float max_tilt_degrees = 10.0; // 最大检视倾角
uniform float inset = 0.0; // 共用检视表面的透视留边
uniform float texture_render_scale = 1.0; // 合成画布的采样倍率
uniform vec2 pointer_force = vec2(0.0);
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
	if (use_3d) {
		vec2 logical_size = 1.0 / (TEXTURE_PIXEL_SIZE * texture_render_scale);
		VERTEX += (UV - vec2(0.5)) * logical_size * tan(radians(fov) * 0.5) * (1.0 - inset);
	}
}

void fragment() {
	vec2 uv = UV;
	if (use_3d) {
		float perspective = tan(radians(fov) * 0.5);
		mat3 inverse_rotation = card_inverse_rotation(pointer_force, max_tilt_degrees);
		vec3 projected = inverse_rotation * vec3(UV - vec2(0.5), 0.5 / perspective);
		float distance_to_camera = 0.5 / perspective + 0.5;
		projected.xy *= distance_to_camera * inverse_rotation[2].z;
		if (projected.z <= 0.0) { discard; }
		uv = projected.xy / projected.z - distance_to_camera * inverse_rotation[2].xy + vec2(0.5);
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { discard; }
	}
	vec4 source = texture(TEXTURE, uv);
	COLOR = pack_relief_color(source, uv, pointer_force) * item_modulate;
}
