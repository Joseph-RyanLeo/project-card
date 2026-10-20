shader_type canvas_item;
render_mode unshaded;

uniform float card_scale = 1.0; // 真实卡高相对原图136像素卡高的倍率
uniform float row_gap = 24.0; // 两张真实卡牌边缘之间的距离，只适配这一小段
uniform float canvas_height = 450.0; // 含两张卡牌与完整首尾特效的显示画布高度
const vec2 FRAME_GRID = vec2(16.0, 3.0); // 图集每个角度16帧，共三个角度
const float UPPER_CARD_BOTTOM = 250.0; // 原图上方卡牌的底边
const float LOWER_CARD_TOP = 274.0; // 原图下方卡牌的顶边，两卡间原始空隙24像素

void fragment() {
	vec2 atlas_position = UV * FRAME_GRID;
	vec2 cell = floor(atlas_position);
	vec2 local = fract(atlas_position);
	float y = local.y * canvas_height;
	float upper_bottom = UPPER_CARD_BOTTOM * card_scale;
	float lower_top = upper_bottom + row_gap;
	float source_y;
	if (y <= upper_bottom) {
		source_y = y / card_scale;
	} else if (y >= lower_top) {
		source_y = LOWER_CARD_TOP + (y - lower_top) / card_scale;
	} else {
		source_y = mix(UPPER_CARD_BOTTOM, LOWER_CARD_TOP, (y - upper_bottom) / max(row_gap, 0.001));
	}
	// 保留两段卡高和原始RGB；最近邻采样只重映射实际排间空隙。
	COLOR = texture(TEXTURE, (cell + vec2(local.x, clamp(source_y, 0.5, 449.5) / 450.0)) / FRAME_GRID);
}
