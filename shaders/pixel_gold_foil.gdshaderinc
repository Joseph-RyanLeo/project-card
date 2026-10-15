// 封皮和卡包共用同一种烫金光带；UV连续计算，不把光影锁在原图像素格上。
const vec3 PACK_GOLD = vec3(0.7529412, 0.5960784, 0.3215686);

vec3 pixel_gold_foil(vec3 gold, vec2 uv, vec2 force, float strength) {
	float stripe = sin(dot(uv, vec2(0.64, 0.77)) * 14.0
		+ (force.x * 1.35 + force.y * 0.35) * PI) * 0.5 + 0.5;
	return mix(gold * 0.77, vec3(1.0, 0.827, 0.525), pow(stripe, 10.0) * strength);
}

vec3 pack_gold_foil(vec3 source, vec2 uv, vec2 force, float strength) {
	// 六张主题包装中，这三色只用于中央图案；深色描边、银饰和文字保留原色。
	bool gold = distance(source, PACK_GOLD) < 0.008
		|| distance(source, vec3(0.5764706, 0.4470588, 0.2117647)) < 0.008
		|| distance(source, vec3(1.0, 0.8274510, 0.5254902)) < 0.008;
	return gold ? pixel_gold_foil(PACK_GOLD, uv, force, strength) : source;
}
