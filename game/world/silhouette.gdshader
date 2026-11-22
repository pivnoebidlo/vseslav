// Силуэт сквозь стены (как в BG3): рисуется поверх фигуры без проверки глубины и
// оставляет только те места, где фигуру заслоняет что-то непрозрачное.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_back, blend_mix;

uniform vec4 color : source_color = vec4(0.3, 0.55, 1.0, 0.55);
// Насколько ближе должна быть преграда, чтобы считать фигуру заслонённой (м).
uniform float bias = 0.15;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

void fragment() {
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	float scene_distance = -view.z / view.w;
	float own_distance = -VERTEX.z;
	if (scene_distance > own_distance - bias) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
