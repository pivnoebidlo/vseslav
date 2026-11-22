// Подсветка клетки поля боя (ADR-0036): почти прозрачная середина и яркая рамка,
// чтобы под подсветкой была видна земля.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.8, 0.96, max(d.x, d.y));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (0.3 + 0.7 * edge);
}
