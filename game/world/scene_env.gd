class_name SceneEnv
extends RefCounted
## Общее окружение 3D-сцен (исследование и бой на карте, ADR-0036): процедурное небо даёт
## рассеянный свет и отражения, тональная коррекция AgX, затенение в углах (SSAO),
## лёгкая дымка вдали, тёплое солнце с мягкими тенями. В помещении — тёмный фон
## без неба и дымки.

const SUN_COLOR := Color(1.0, 0.93, 0.82)


## Возвращает окружение, чтобы сцена могла его подстроить (помещение).
static func add_to(parent: Node) -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.52, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.78)
	sky_mat.ground_horizon_color = Color(0.6, 0.6, 0.55)
	sky_mat.ground_bottom_color = Color(0.3, 0.28, 0.24)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.74, 0.78)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.25
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	parent.add_child(sun)
	return env


## Помещение: фон — темнота, рассеянный свет тёплый и слабее, без дымки.
static func make_interior(env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.72, 0.55)
	env.ambient_light_energy = 0.5
	env.fog_enabled = false
