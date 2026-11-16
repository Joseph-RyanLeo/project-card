shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/card_layer_flash.gdshaderinc"

uniform bool foil_enabled = false;
uniform bool pointer_light_enabled = false; // 明暗与闪纹独立，法线／全息／超框也能使用
uniform int flash_type = 0;
uniform float foil_shade_strength = 0.45; // 与人物、背景共用的柔和明暗幅度
#include "res://shaders/card_film.gdshaderinc"

varying vec4 item_modulate;
varying vec2 finish_position;

void vertex() {
	item_modulate = COLOR;
	finish_position = VERTEX + layer_origin;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 plane_size = card_size + foil_padding * 2.0;
	vec2 plane_uv = (UV * card_size + foil_padding) / plane_size;
	if (foil_enabled) { source.rgb += card_layer_flash(finish_position, flash_type); }
	if (film_kind != 0) { source.rgb = card_film_finish(source.rgb, UV, UV, pointer_force, 1); }
	if (pointer_light_enabled) { source.rgb *= card_pointer_light(plane_uv, pointer_force, foil_shade_strength); }
	if (outline_highlight_enabled && source.a >= 0.5) {
		vec2 dx = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
		vec2 dy = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
		source.rgb += card_outline_flash(finish_position, source,
			texture(TEXTURE, UV - dx) * step(dx.x, UV.x),
			texture(TEXTURE, UV + dx) * step(UV.x + dx.x, 1.0),
			texture(TEXTURE, UV - dy) * step(dy.y, UV.y),
			texture(TEXTURE, UV + dy) * step(UV.y + dy.y, 1.0));
	}
	COLOR = source * item_modulate;
}
