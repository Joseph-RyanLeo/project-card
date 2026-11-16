// 根据一个输出像素在逻辑格中的覆盖范围，计算相邻两格的混色比例。
vec2 pixel_edge_sample_position(vec2 cell_position) {
	vec2 footprint = clamp(fwidth(cell_position), vec2(0.00001), vec2(1.0));
	vec2 box_start = cell_position - 0.5 * footprint;
	vec2 weight = clamp((fract(box_start) - (1.0 - footprint)) / footprint, 0.0, 1.0);
	return floor(box_start) + weight;
}
