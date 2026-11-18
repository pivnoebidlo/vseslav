extends GutTest
## Этап 0: загрузка GLB во время игры и ретаргетинг на другой скелет.
## Модели генерируются SyntheticRig, сторонние ассеты не нужны.

const TMP := "user://test_tmp/models"

var _profiles: Array[RigProfile] = []


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	_profiles = RigProfile.load_all()


func _make_glb(
	file: String, style: String, scale: float = 1.0, twist: float = 0.0, arm_drop: float = 0.0
) -> String:
	var scene := SyntheticRig.build(style, scale, twist, arm_drop)
	var path := TMP.path_join(file)
	assert_eq(SyntheticRig.save_glb(scene, path), OK, "save %s" % file)
	scene.free()
	return path


func _load(path: String, limits: ModelLimits = ModelLimits.new()) -> LoadedModel:
	var model := CharacterLoader.load_file(path, _profiles, limits)
	if model.root != null:
		autofree(model.root)
	return model


func _error_keys(model: LoadedModel) -> Array[String]:
	var keys: Array[String] = []
	for e in model.errors:
		keys.append(str(e["key"]))
	return keys


## Направление кости (от неё к дочерней) в пространстве модели в текущей позе.
func _direction(skeleton: Skeleton3D, bone: String, child: String) -> Vector3:
	var a := skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	var b := skeleton.get_bone_global_pose(skeleton.find_bone(child)).origin
	return (b - a).normalized()


## Поворот кости в пространстве модели относительно её позы покоя.
func _delta(skeleton: Skeleton3D, bone: String) -> Quaternion:
	var i := skeleton.find_bone(bone)
	var pose := skeleton.get_bone_global_pose(i).basis.get_rotation_quaternion()
	var rest := skeleton.get_bone_global_rest(i).basis.get_rotation_quaternion()
	return pose * rest.inverse()


func test_rig_profiles_load_and_detect() -> void:
	assert_eq(_profiles.size(), 3)
	var kaykit: Array[String] = ["root", "hips", "upperleg.l", "lowerleg.l", "upperarm.l"]
	assert_eq(RigProfile.detect_profile(_profiles, kaykit).id, "kaykit")
	var mixamo: Array[String] = [
		"mixamorig:Hips", "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftArm"
	]
	assert_eq(RigProfile.detect_profile(_profiles, mixamo).id, "mixamo")
	var humanoid: Array[String] = ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftUpperArm"]
	assert_eq(RigProfile.detect_profile(_profiles, humanoid).id, "humanoid")
	var unknown: Array[String] = ["a", "b", "c"]
	assert_null(RigProfile.detect_profile(_profiles, unknown))


func test_mixamo_name_variants() -> void:
	var mixamo: RigProfile = null
	for p in _profiles:
		if p.id == "mixamo":
			mixamo = p
	assert_eq(mixamo.humanoid_name("mixamorig:LeftUpLeg"), "LeftUpperLeg")
	assert_eq(mixamo.humanoid_name("mixamorig_LeftUpLeg"), "LeftUpperLeg")
	assert_eq(mixamo.humanoid_name("mixamorig2:Spine1"), "Chest")
	assert_eq(mixamo.humanoid_name("mixamorig:LeftHandIndex1"), "")


func test_loads_glb_from_outside_project_and_renames_bones() -> void:
	var model := _load(_make_glb("mixamo.glb", SyntheticRig.STYLE_MIXAMO))
	assert_true(model.ok(), "errors: %s" % [model.errors])
	assert_eq(model.rig.id, "mixamo")
	assert_eq(model.bones, SyntheticRig.BONES.size())
	assert_gt(model.triangles, 0)
	assert_gt(model.skeleton.find_bone("LeftUpperLeg"), -1)
	assert_eq(model.skeleton.find_bone("mixamorig_LeftUpLeg"), -1)
	var anim := model.animation_player.get_animation(SyntheticRig.SWING_ANIMATION)
	assert_true(
		str(anim.track_get_path(0)).ends_with(":LeftUpperLeg"), "track follows renamed bone"
	)


func test_animation_plays_after_rename() -> void:
	var model := _load(_make_glb("mixamo_anim.glb", SyntheticRig.STYLE_MIXAMO))
	add_child(model.root)
	await wait_process_frames(2)
	model.animation_player.play(SyntheticRig.SWING_ANIMATION)
	model.animation_player.seek(0.5, true)
	model.animation_player.speed_scale = 0.0
	await wait_process_frames(3)
	var swing := rad_to_deg(_delta(model.skeleton, "LeftUpperLeg").get_angle())
	assert_almost_eq(swing, SyntheticRig.SWING_DEGREES, 0.5)


func test_unknown_rig_loads_with_warning() -> void:
	var model := _load(_make_glb("unknown.glb", SyntheticRig.STYLE_UNKNOWN))
	assert_true(model.ok())
	assert_null(model.rig)
	assert_eq(model.warnings.size(), 1)
	assert_eq(str(model.warnings[0]["key"]), CharacterLoader.WARN_UNKNOWN_RIG)


func test_rejects_bad_files() -> void:
	var path := _make_glb("limits.glb", SyntheticRig.STYLE_HUMANOID)
	assert_eq(_error_keys(_load(TMP.path_join("nope.glb"))), [CharacterLoader.ERR_NOT_FOUND])
	assert_eq(_error_keys(_load(TMP.path_join("model.gltf"))), [CharacterLoader.ERR_EXTENSION])

	var small := ModelLimits.new()
	small.max_file_bytes = 100
	assert_eq(_error_keys(_load(path, small)), [CharacterLoader.ERR_TOO_BIG])

	var few_bones := ModelLimits.new()
	few_bones.max_bones = 5
	assert_eq(_error_keys(_load(path, few_bones)), [CharacterLoader.ERR_BONES])

	var few_tris := ModelLimits.new()
	few_tris.max_triangles = 10
	assert_eq(_error_keys(_load(path, few_tris)), [CharacterLoader.ERR_TRIANGLES])


func test_rejects_garbage_bytes() -> void:
	var path := TMP.path_join("garbage.glb")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not a glb file")
	f.close()
	assert_eq(_error_keys(_load(path)), [CharacterLoader.ERR_PARSE])


func test_retarget_to_different_skeleton() -> void:
	# Источник: гуманоидные имена, T-поза. Цель: имена Mixamo, крупнее в 1.3 раза,
	# оси костей повёрнуты на 70°, руки в позе покоя опущены на 60° (A-поза) —
	# как у моделей из других программ. Направления костей должны совпасть.
	var source := CharacterLoader.load_file(
		_make_glb("src.glb", SyntheticRig.STYLE_HUMANOID), _profiles
	)
	var target := _load(_make_glb("dst.glb", SyntheticRig.STYLE_MIXAMO, 1.3, 70.0, 60.0))
	assert_true(source.ok() and target.ok())
	var target_skeleton := target.skeleton
	assert_true(Retarget.attach(source, target))
	assert_eq(source.root.get_parent(), target.root, "source lives inside the target model")
	add_child(target.root)
	await wait_process_frames(2)

	source.animation_player.play(SyntheticRig.SWING_ANIMATION)
	source.animation_player.seek(0.5, true)
	source.animation_player.speed_scale = 0.0
	await wait_process_frames(3)

	var swing := rad_to_deg(_delta(source.skeleton, "LeftUpperLeg").get_angle())
	assert_almost_eq(swing, SyntheticRig.SWING_DEGREES, 0.5, "source leg is swung")
	for pair: Array[String] in [
		["LeftUpperLeg", "LeftLowerLeg"] as Array[String],
		["LeftUpperArm", "LeftLowerArm"] as Array[String],
		["RightUpperArm", "RightLowerArm"] as Array[String],
		["Spine", "Chest"] as Array[String],
	]:
		var src := _direction(source.skeleton, pair[0], pair[1])
		var dst := _direction(target_skeleton, pair[0], pair[1])
		assert_almost_eq(
			rad_to_deg(src.angle_to(dst)), 0.0, 1.0, "%s points the same way" % pair[0]
		)
	# Пропорции цели сохраняются: таз остаётся на своей высоте, а не на высоте источника.
	var hips := target_skeleton.find_bone("Hips")
	assert_almost_eq(
		target_skeleton.get_bone_global_pose(hips).origin.y,
		target_skeleton.get_bone_global_rest(hips).origin.y,
		0.01,
		"target hips keep their own height"
	)


func test_retarget_refuses_unknown_rig() -> void:
	var source := _load(_make_glb("src2.glb", SyntheticRig.STYLE_HUMANOID))
	var target := _load(_make_glb("unknown2.glb", SyntheticRig.STYLE_UNKNOWN))
	assert_false(Retarget.attach(source, target))
