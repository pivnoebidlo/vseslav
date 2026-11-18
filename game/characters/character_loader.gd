class_name CharacterLoader
extends RefCounted
## Загрузка GLB во время игры (ADR-0009, SPEC §11). Файл — недоверенные данные:
## сначала размер и расширение, затем разбор без внешних ссылок, затем лимиты,
## и только после этого создаётся сцена.

const ERR_NOT_FOUND := "ERR_MODEL_NOT_FOUND"
const ERR_EXTENSION := "ERR_MODEL_EXTENSION"
const ERR_TOO_BIG := "ERR_MODEL_TOO_BIG"
const ERR_PARSE := "ERR_MODEL_PARSE"
const ERR_TRIANGLES := "ERR_MODEL_TOO_MANY_TRIS"
const ERR_SKELETONS := "ERR_MODEL_TOO_MANY_SKELETONS"
const ERR_BONES := "ERR_MODEL_TOO_MANY_BONES"
const ERR_TEXTURE := "ERR_MODEL_TEXTURE_TOO_BIG"
const WARN_UNKNOWN_RIG := "WARN_MODEL_UNKNOWN_RIG"


## Загружает модель из файла. [param profiles] — профили ригов (RigProfile.load_all()).
static func load_file(
	path: String, profiles: Array[RigProfile], limits: ModelLimits = ModelLimits.new()
) -> LoadedModel:
	var model := LoadedModel.new()
	model.path = path
	if path.get_extension().to_lower() != "glb":
		model.add_error(ERR_EXTENSION, {"file": path.get_file()})
		return model
	if not FileAccess.file_exists(path):
		model.add_error(ERR_NOT_FOUND, {"file": path.get_file()})
		return model
	var file := FileAccess.open(path, FileAccess.READ)
	model.file_bytes = file.get_length()
	if model.file_bytes > limits.max_file_bytes:
		model.add_error(
			ERR_TOO_BIG,
			{
				"file": path.get_file(),
				"size": _mb(model.file_bytes),
				"limit": _mb(limits.max_file_bytes)
			}
		)
		return model
	var bytes := file.get_buffer(model.file_bytes)
	file.close()
	# Сигнатура GLB: без неё Godot попытается разобрать файл как текстовый glTF.
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "glTF":
		model.add_error(ERR_PARSE, {"file": path.get_file()})
		return model

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	# Пустой base_path: внешние ссылки (uri на файлы рядом) не разрешаются.
	if doc.append_from_buffer(bytes, "", state) != OK:
		model.add_error(ERR_PARSE, {"file": path.get_file()})
		return model

	validate_state(state, limits, model)
	if not model.errors.is_empty():
		return model

	model.rig = RigProfile.detect_profile(profiles, joint_names(state))
	if model.rig == null:
		model.add_warning(WARN_UNKNOWN_RIG, {"file": path.get_file()})
	else:
		rename_joints(state, model.rig)

	var scene := doc.generate_scene(state)
	model.root = scene as Node3D
	if model.root == null:
		if scene != null:
			scene.free()
		model.add_error(ERR_PARSE, {"file": path.get_file()})
		return model
	model.root.name = path.get_file().get_basename().validate_node_name()
	var skeletons := model.root.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		model.skeleton = skeletons[0] as Skeleton3D
	var players := model.root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		model.animation_player = players[0] as AnimationPlayer
	return model


## Проверяет лимиты по разобранному GLTF до создания сцены; ошибки пишет в [param model].
static func validate_state(state: GLTFState, limits: ModelLimits, model: LoadedModel) -> void:
	var file := model.path.get_file()
	model.triangles = count_triangles(state)
	if model.triangles > limits.max_triangles:
		model.add_error(
			ERR_TRIANGLES, {"file": file, "count": model.triangles, "limit": limits.max_triangles}
		)
	var skeletons := state.get_skeletons()
	if skeletons.size() > limits.max_skeletons:
		model.add_error(
			ERR_SKELETONS, {"file": file, "count": skeletons.size(), "limit": limits.max_skeletons}
		)
	model.bones = joint_names(state).size()
	if model.bones > limits.max_bones:
		model.add_error(ERR_BONES, {"file": file, "count": model.bones, "limit": limits.max_bones})
	for image in state.get_images():
		if image == null:
			continue
		var side := maxi(image.get_width(), image.get_height())
		if side > limits.max_texture_side:
			model.add_error(
				ERR_TEXTURE, {"file": file, "size": side, "limit": limits.max_texture_side}
			)
			break


static func count_triangles(state: GLTFState) -> int:
	var total := 0
	for gltf_mesh in state.get_meshes():
		var mesh := gltf_mesh.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			if mesh.get_surface_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mesh.get_surface_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				total += vertices.size() / 3
			else:
				total += indices.size() / 3
	return total


## Имена костей (узлов-суставов) всех скелетов в файле.
static func joint_names(state: GLTFState) -> Array[String]:
	var names: Array[String] = []
	var nodes := state.get_nodes()
	for skeleton in state.get_skeletons():
		for joint in skeleton.joints:
			names.append(nodes[joint].resource_name)
	return names


## Переименовывает кости в гуманоидные имена до создания сцены:
## так кости и дорожки анимаций остаются согласованными.
static func rename_joints(state: GLTFState, rig: RigProfile) -> void:
	if rig.identity:
		return
	var nodes := state.get_nodes()
	var used: Dictionary[String, bool] = {}
	for skeleton in state.get_skeletons():
		for joint in skeleton.joints:
			var node := nodes[joint]
			var target := rig.humanoid_name(node.resource_name)
			if target == "" or used.has(target):
				continue
			used[target] = true
			node.resource_name = target


static func _mb(bytes: int) -> String:
	return "%.1f" % (bytes / 1048576.0)
