// 整卡与全息前后层共用同一旋转；内层只改变深度，不再叠加自己的角度。
mat3 card_inverse_rotation(vec2 force, float tilt_degrees) {
	float y_angle = radians(force.x * tilt_degrees);
	float x_angle = radians(-force.y * tilt_degrees);
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
