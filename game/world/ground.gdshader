// Земля области (ADR-0036): текстура земли и дороги в мировых координатах, дорога
// смешивается с землёй по маске карты (клетка «,» = 1) с рваным краем. Чтобы повтор
// текстуры не бросался в глаза, второй слой берётся под углом и крупнее, а яркость
// плавно гуляет по шуму.
shader_type spatial;

uniform sampler2D ground_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 ground_tint : source_color = vec3(1.0);
uniform float ground_tile = 3.0;

uniform sampler2D road_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 road_tint : source_color = vec3(1.0);
uniform float road_tile = 3.0;

uniform sampler2D road_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 map_cells = vec2(1.0);
uniform float cell_size = 1.5;
uniform bool has_road = false;

varying vec2 world_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	const mat2 TURN = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	vec2 g1 = world_xz / ground_tile;
	vec2 g2 = TURN * world_xz / (ground_tile * 2.3);
	vec3 albedo = mix(texture(ground_color, g1).rgb, texture(ground_color, g2).rgb, 0.4) * ground_tint;
	vec3 normal = texture(ground_normal, g1).rgb;
	float rough = texture(ground_rough, g1).r;
	if (has_road) {
		vec2 r1 = world_xz / road_tile;
		vec2 r2 = TURN * world_xz / (road_tile * 2.3);
		vec2 muv = (world_xz / cell_size + 0.5) / map_cells;
		float edge = value_noise(world_xz * 1.4) * 0.5 + value_noise(world_xz * 4.0) * 0.25;
		float w = smoothstep(0.42, 0.62, texture(road_mask, muv).r + edge - 0.37);
		vec3 road = mix(texture(road_color, r1).rgb, texture(road_color, r2).rgb, 0.4) * road_tint;
		albedo = mix(albedo, road, w);
		normal = mix(normal, texture(road_normal, r1).rgb, w);
		rough = mix(rough, texture(road_rough, r1).r, w);
	}
	float macro = value_noise(world_xz * 0.08) * 0.6 + value_noise(world_xz * 0.3) * 0.4;
	ALBEDO = albedo * mix(0.82, 1.12, macro);
	NORMAL_MAP = normal;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
