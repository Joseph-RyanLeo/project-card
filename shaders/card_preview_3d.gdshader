shader_type canvas_item;
render_mode unshaded;

// 把合成后的整张卡当成一个平面做透视和扫光，避免多层节点各自变形。
uniform bool use_3d = false;
uniform float fov : hint_range(20.0, 120.0, 1.0) = 72.0;
uniform float max_tilt_degrees : hint_range(0.0, 24.0, 0.5);
uniform float inset : hint_range(0.0, 1.0, 0.01);
uniform vec2 pointer_force = vec2(0.0);

uniform bool use_flash = false;
uniform int flash_type : hint_range(0, 2) = 0;
uniform float stripe_spacing : hint_range(1.0, 50.0, 0.5);
uniform float stripe_width : hint_range(1.0, 20.0, 0.5);
uniform float flash_intensity : hint_range(0.0, 2.0, 0.05);
uniform float flash_angle_degrees : hint_range(0.0, 360.0, 1.0) = 50.0;

uniform vec2 card_texture_size_px = vec2(1.0);
uniform vec2 mask_origin_px = vec2(0.0);
uniform vec2 mask_size_px = vec2(1.0);

uniform bool use_normal_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear;
uniform float normal_light_strength : hint_range(0.0, 1.0, 0.05) = 0.32;


mat3 inverse_rotation_matrix(vec2 force) {
	float y_angle = radians(force.x * max_tilt_degrees);
	float x_angle = radians(-force.y * max_tilt_degrees);
	float sin_y = sin(y_angle);
	float cos_y = cos(y_angle);
	float sin_x = sin(x_angle);
	float cos_x = cos(x_angle);
	return mat3(
		vec3(cos_y, 0.0, -sin_y),
		vec3(sin_y * sin_x, cos_x, cos_y * sin_x),
		vec3(sin_y * cos_x, -sin_x, cos_y * cos_x)
	);
}


void vertex() {
	if (use_3d) {
		float perspective_scale = tan(radians(fov) * 0.5);
		vec2 texture_size = 1.0 / TEXTURE_PIXEL_SIZE;
		VERTEX += (UV - vec2(0.5)) * texture_size * perspective_scale * (1.0 - inset);
	}
}


void fragment() {
	vec2 sample_uv = UV;
	if (use_3d) {
		float perspective_scale = tan(radians(fov) * 0.5);
		mat3 inverse_rotation = inverse_rotation_matrix(pointer_force);
		vec3 projected = inverse_rotation * vec3(
			UV - vec2(0.5),
			0.5 / perspective_scale
		);
		float camera_distance = (0.5 / perspective_scale) + 0.5;
		projected.xy *= camera_distance * inverse_rotation[2].z;
		vec2 camera_offset = camera_distance * inverse_rotation[2].xy;
		if (projected.z <= 0.0) {
			discard;
		}
		sample_uv = projected.xy / projected.z - camera_offset + vec2(0.5);
		if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
			discard;
		}
	}

	vec4 source = texture(TEXTURE, sample_uv);
	vec2 card_pixel = sample_uv * card_texture_size_px;
	vec2 mask_uv = (card_pixel - mask_origin_px) / max(mask_size_px, vec2(1.0));
	float inside_mask = (
		step(0.0, mask_uv.x)
		* step(mask_uv.x, 1.0)
		* step(0.0, mask_uv.y)
		* step(mask_uv.y, 1.0)
	);
	vec3 output_color = source.rgb;
	if (use_normal_texture && inside_mask > 0.0) {
		vec4 packed_normal = texture(normal_texture, clamp(mask_uv, vec2(0.0), vec2(1.0)));
		vec3 normal_value = normalize(packed_normal.rgb * 2.0 - 1.0);
		vec3 light_direction = normalize(vec3(pointer_force.x, -pointer_force.y, 1.2));
		float normal_light = max(dot(normal_value, light_direction), 0.0);
		float light_multiplier = mix(0.82, 1.18, normal_light);
		output_color *= mix(1.0, light_multiplier, normal_light_strength * packed_normal.a);
	}

	if (use_flash) {
		float flash_angle = radians(flash_angle_degrees);
		vec2 flash_direction = vec2(cos(flash_angle), sin(flash_angle));
		float flash_position = pointer_force.x * 1.35 + pointer_force.y * 0.35;
		float stripe = sin(
			dot(sample_uv, flash_direction) * stripe_spacing
			+ flash_position * PI
		) * 0.5 + 0.5;
		// 扫光作用于 SubViewport 已经合成并裁切好的整张卡；透明留白仍由 source.a 控制。
		float flash_amount = pow(stripe, stripe_width) * flash_intensity;
		if (flash_type == 0) {
			output_color += vec3(flash_amount);
		} else if (flash_type == 1) {
			output_color += vec3(1.0, 0.78, 0.24) * flash_amount;
		} else {
			// 彩虹颜色固定在卡牌空间，不跟着某一条光带移动；同一条光带经过
			// 卡牌不同位置时会自然取得不同颜色。
			float hue = fract(sample_uv.x * 0.85 + sample_uv.y * 0.55);
			vec3 rainbow = vec3(
				0.5 + 0.5 * sin(6.2831 * hue),
				0.5 + 0.5 * sin(6.2831 * (hue + 0.33)),
				0.5 + 0.5 * sin(6.2831 * (hue + 0.66))
			);
			output_color += rainbow * flash_amount;
		}
	}

	COLOR = vec4(output_color, source.a);
}
