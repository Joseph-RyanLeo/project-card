shader_type canvas_item;
render_mode unshaded;
uniform float white_amount : hint_range(0.0, 1.0) = 0.0; // 0为原色，1为保留透明轮廓的纯白剪影
uniform float jelly_amount : hint_range(0.0, 1.0) = 0.0; // 果冻挤压强度；默认0，纹章等共用闪白的对象不变形
uniform float jelly_progress : hint_range(0.0, 1.0) = 0.0; // 回弹进度；0为挤压峰值，1为完全恢复，由演出时间轴驱动
uniform float jelly_stretch : hint_range(0.0, 0.3) = 0.10; // 挤压峰值时向上下拉长的比例
uniform float jelly_squeeze : hint_range(0.0, 0.3) = 0.08; // 挤压峰值时左右收窄的比例
uniform float jelly_recoil : hint_range(0.0, 1.0) = 0.45; // 快速反弹时横宽竖扁的反向挤压幅度，相对首次挤压峰值
uniform float jelly_overshoot : hint_range(0.0, 0.2) = 0.055; // 反弹后整卡超出正常尺寸的比例，默认整体弹大5.5%
uniform vec2 jelly_pivot = vec2(0.0); // 裸卡中心在快照纹理内的位置，包含越界图标时也不偏移支点
const float RECOIL_REACH = 0.20; // 前20%快速反弹到反向挤压极限（0.08秒）
const float RECOIL_LEAVE = 0.32; // 极限附近停留至32%（约3帧），再开始整体弹大
const float OVERSHOOT_REACH = 0.64; // 64%时到达整体弹大极限
const float OVERSHOOT_LEAVE = 0.76; // 弹大极限停留至76%（约3帧），之后缩回原形
varying vec4 item_tint;
void vertex() {
	item_tint = COLOR; // 单独保留节点透明度，避免fragment内已乘纹理的COLOR把白色重新染回原色
	float progress = clamp(jelly_progress, 0.0, 1.0);
	// smoothstep两端速度为0：极限慢、中段快；平台区保留几帧形状，让回弹节奏可读。
	float rebound = mix(1.0, -jelly_recoil, smoothstep(0.0, RECOIL_REACH, progress));
	float expand = smoothstep(RECOIL_LEAVE, OVERSHOOT_REACH, progress);
	float pulse = jelly_amount * mix(rebound, 0.0, expand);
	float swell = 1.0 + jelly_amount * jelly_overshoot * expand * (1.0 - smoothstep(OVERSHOOT_LEAVE, 1.0, progress));
	vec2 stretch = vec2(1.0 - jelly_squeeze * pulse, 1.0 + jelly_stretch * pulse) * swell;
	VERTEX = jelly_pivot + (VERTEX - jelly_pivot) * stretch;
}
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(mix(source.rgb, vec3(1.0), white_amount), source.a) * item_tint;
}
