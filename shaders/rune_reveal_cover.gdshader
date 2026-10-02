shader_type canvas_item;

uniform sampler2D scrape_mask : filter_nearest;
uniform bool reveal_only = false;

void fragment() {
	if (texture(TEXTURE, UV).a <= 0.0) {
		discard;
	}
	bool scraped = texture(scrape_mask, UV).r > 0.5;
	if (reveal_only ? !scraped : scraped) {
		discard;
	}
}
