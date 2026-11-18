class_name SyntheticRig
extends RefCounted
## Синтетический гуманоидный риг для тестов загрузки и ретаргетинга без сторонних ассетов.
## Можно задать стиль имён костей, масштаб и «скрутку» осей костей —
## как у моделей из разных источников (Mixamo, AI-генераторы, Blender).

const STYLE_HUMANOID := "humanoid"
const STYLE_MIXAMO := "mixamo"
## Имена, которые не узнаёт ни один профиль рига.
const STYLE_UNKNOWN := "unknown"

## Имена Mixamo — как после импорта в Godot: «mixamorig:Hips» становится «mixamorig_Hips».
## [гуманоидное имя, имя в Mixamo, родитель (гуманоидное имя), смещение от родителя при scale=1]
const BONES: Array[Array] = [
	["Hips", "Hips", "", Vector3(0, 1.0, 0)],
	["Spine", "Spine", "Hips", Vector3(0, 0.12, 0)],
	["Chest", "Spine1", "Spine", Vector3(0, 0.15, 0)],
	["Head", "Head", "Chest", Vector3(0, 0.3, 0)],
	["LeftUpperLeg", "LeftUpLeg", "Hips", Vector3(0.1, -0.05, 0)],
	["LeftLowerLeg", "LeftLeg", "LeftUpperLeg", Vector3(0, -0.45, 0)],
	["LeftFoot", "LeftFoot", "LeftLowerLeg", Vector3(0, -0.45, 0)],
	["RightUpperLeg", "RightUpLeg", "Hips", Vector3(-0.1, -0.05, 0)],
	["RightLowerLeg", "RightLeg", "RightUpperLeg", Vector3(0, -0.45, 0)],
	["RightFoot", "RightFoot", "RightLowerLeg", Vector3(0, -0.45, 0)],
	["LeftUpperArm", "LeftArm", "Chest", Vector3(0.2, 0.2, 0)],
	["LeftLowerArm", "LeftForeArm", "LeftUpperArm", Vector3(0.28, 0, 0)],
	["RightUpperArm", "RightArm", "Chest", Vector3(-0.2, 0.2, 0)],
	["RightLowerArm", "RightForeArm", "RightUpperArm", Vector3(-0.28, 0, 0)],
]

const SWING_ANIMATION := "Swing"
const SWING_BONE := "LeftUpperLeg"
const SWING_DEGREES := 40.0


static func bone_name(humanoid: String, style: String) -> String:
	for b in BONES:
		if b[0] == humanoid:
			if style == STYLE_MIXAMO:
				return "mixamorig_" + str(b[1])
			if style == STYLE_UNKNOWN:
				return "bone_" + humanoid.to_lower()
			return humanoid
	return ""


## Строит сцену: корень → Skeleton3D (с мешами-кубиками, привязанными к костям) + AnimationPlayer.
## [param twist_degrees] поворачивает оси каждой кости вокруг Y (другая «ориентация костей»).
## [param arm_drop_degrees] опускает руки в позе покоя (0 — T-поза, 45–60 — A-поза).
static func build(
	style: String, scale: float = 1.0, twist_degrees: float = 0.0, arm_drop_degrees: float = 0.0
) -> Node3D:
	var root := Node3D.new()
	root.name = "SyntheticRig"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root
	var twist := Basis(Vector3.UP, deg_to_rad(twist_degrees))
	var drop := deg_to_rad(arm_drop_degrees)
	# Сначала считаем глобальные позы покоя, затем переводим в локальные.
	var globals: Dictionary[String, Transform3D] = {}
	for b in BONES:
		var human := str(b[0])
		var parent_name := str(b[2])
		var offset: Vector3 = b[3]
		offset *= scale
		if parent_name.contains("UpperArm") or parent_name.contains("LowerArm"):
			var side := -1.0 if human.begins_with("Left") else 1.0
			offset = Basis(Vector3.BACK, side * drop) * offset
		var origin := offset
		if parent_name != "":
			origin = globals[parent_name].origin + offset
		globals[human] = Transform3D(twist, origin)
		var idx := skeleton.add_bone(bone_name(human, style))
		var rest := globals[human]
		if parent_name != "":
			skeleton.set_bone_parent(idx, skeleton.find_bone(bone_name(parent_name, style)))
			rest = globals[parent_name].affine_inverse() * globals[human]
		skeleton.set_bone_rest(idx, rest)
	skeleton.reset_bone_poses()
	_add_skinned_mesh(skeleton, root, scale)
	_add_animation(root, skeleton, style)
	return root


## Сохраняет сцену в GLB. Возвращает код ошибки Godot.
static func save_glb(scene: Node3D, path: String) -> Error:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(scene, state)
	if err != OK:
		return err
	return doc.write_to_filesystem(state, path)


static func _add_skinned_mesh(skeleton: Skeleton3D, root: Node3D, scale: float) -> void:
	var vertices := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var cube: Array = BoxMesh.new().get_mesh_arrays()
	var cube_vertices: PackedVector3Array = cube[Mesh.ARRAY_VERTEX]
	var cube_indices: PackedInt32Array = cube[Mesh.ARRAY_INDEX]
	for i in skeleton.get_bone_count():
		var at := skeleton.get_bone_global_rest(i).origin
		var base := vertices.size()
		for v in cube_vertices:
			vertices.append(at + v * 0.08 * scale)
			bones.append_array([i, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		for index in cube_indices:
			indices.append(base + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	skeleton.add_child(mi)
	mi.owner = root
	mi.skeleton = NodePath("..")
	mi.skin = skeleton.create_skin_from_rest_transforms()


static func _add_animation(root: Node3D, skeleton: Skeleton3D, style: String) -> void:
	var bone := bone_name(SWING_BONE, style)
	var idx := skeleton.find_bone(bone)
	var rest := skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	var swung := rest * Quaternion(Vector3.RIGHT, deg_to_rad(SWING_DEGREES))
	var anim := Animation.new()
	anim.length = 1.0
	var track := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(track, NodePath("Skeleton3D:" + bone))
	anim.rotation_track_insert_key(track, 0.0, rest)
	anim.rotation_track_insert_key(track, 0.5, swung)
	anim.rotation_track_insert_key(track, 1.0, rest)
	var library := AnimationLibrary.new()
	library.add_animation(SWING_ANIMATION, anim)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	player.add_animation_library("", library)
