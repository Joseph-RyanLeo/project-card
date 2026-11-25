shader_type canvas_item;
render_mode unshaded;

uniform sampler2D game_screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.42; // 扫描线与亮部微光的混合强度
uniform float output_scale = 1.0; // 游戏逻辑像素到窗口像素的显示倍率
uniform vec2 curvature = vec2(0.0); // 横向与纵向的曲面变形，由显示壳同步给鼠标坐标换算

const float SCANLINE_MODULATION = 0.078; // 满强度时横纹围绕原亮度上下波动的最大比例
const float SCANLINE_CHROMA = 0.09; // 满强度时红蓝彩纹的幅度
const vec3 SCANLINE_COLOR_PHASES = vec3(-1.15, 0.24, 1.85); // 红绿蓝亮峰在同一横纹周期内的错位，单位为弧度
const vec3 LUMINANCE_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
const float SCANLINE_MIN_PERIOD = 6.0; // 一组横纹占据的最小屏幕像素数，给明暗过渡留足像素
const float SCANLINE_PERIOD_PER_SCALE = 4.0; // 窗口放大时横纹周期随倍率增加的系数
const float SCANLINE_STRENGTH_CURVE = 1.6; // 减缓低档起步，给微弱横纹保留更多刻度
const float SPILL_GAIN = 0.09; // 满强度时邻近亮部的微光比例
const float BORDER_FEATHER_PIXELS = 0.85; // 曲面外缘的像素过渡，减少弧线的锯齿
const vec3 BEZEL_COLOR = vec3(0.014, 0.012, 0.016); // 弯曲画面外的深色边框

void fragment() {
	vec2 uv = SCREEN_UV;
	// crt_projection.gd 使用同一公式把可见的指针位置换回原画布。
	vec2 centered = uv * 2.0 - 1.0;
	vec2 source_uv = (centered * (1.0 + curvature * centered.yx * centered.yx) + 1.0) * 0.5;
	vec3 original = texture(game_screen, source_uv).rgb;
	vec3 picture = original;
	if (scanline_strength > 0.0) {
		float amount = pow(scanline_strength, SCANLINE_STRENGTH_CURVE);
		float period = max(SCANLINE_MIN_PERIOD, round(output_scale * SCANLINE_PERIOD_PER_SCALE));
		float phase = TAU * (FRAGCOORD.y - 0.5) / period;
		vec2 source_step = SCREEN_PIXEL_SIZE * max(1.0, output_scale);
		vec3 neighbors = (
			texture(game_screen, source_uv + vec2(source_step.x, 0.0)).rgb
			+ texture(game_screen, source_uv - vec2(source_step.x, 0.0)).rgb
			+ texture(game_screen, source_uv + vec2(0.0, source_step.y)).rgb
			+ texture(game_screen, source_uv - vec2(0.0, source_step.y)).rgb
		) * 0.25;
		vec3 spill = max(neighbors - max(original, vec3(0.48)), vec3(0.0)) * SPILL_GAIN;
		// 围绕原画面的亮度交替增减，使纯色区域的横纹柔和并保持平均亮度。
		float modulation = SCANLINE_MODULATION * cos(phase);
		vec3 chroma = cos(vec3(phase) + SCANLINE_COLOR_PHASES);
		// 扣去色纹带来的亮度增量，使红蓝变化与横纹原有的明暗各自成立。
		chroma -= vec3(dot(chroma, LUMINANCE_WEIGHTS));
		float luma = dot(original, LUMINANCE_WEIGHTS);
		float color_light = luma * (1.0 - smoothstep(0.83, 1.0, luma));
		picture += amount * (original * modulation + chroma * (color_light * SCANLINE_CHROMA) + spill);
	}
	if (curvature.x > 0.0 || curvature.y > 0.0) {
		vec2 overshoot = max(-source_uv, source_uv - 1.0) / SCREEN_PIXEL_SIZE;
		float bezel = smoothstep(-BORDER_FEATHER_PIXELS, BORDER_FEATHER_PIXELS, max(overshoot.x, overshoot.y));
		picture = mix(picture, BEZEL_COLOR, bezel);
	}
	COLOR = vec4(picture, 1.0);
}
