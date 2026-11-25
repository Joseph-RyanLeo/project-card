shader_type canvas_item;

uniform sampler2D scrape_mask : filter_nearest;
uniform bool reveal_only = false;
varying vec2 rune_local_uv;

void vertex() {
	rune_local_uv = VERTEX / 23.0;
}

void fragment() {
	if (texture(TEXTURE, UV).a <= 0.0) {
		discard;
	}
	bool scraped = texture(scrape_mask, rune_local_uv).r > 0.5;
	if (reveal_only ? !scraped : scraped) {
		discard;
	}
}
