class_name ModuleWorkspace
extends RefCounted
## Какие модули есть и какие можно править (ADR-0039). Модули игры (res://) правятся,
## только когда игра запущена из исходников, — правки сразу попадают в репозиторий.
## В собранной игре правятся модули игрока в user://modules.

const USER_ROOT := "user://modules"


## Модули из [param roots]: {id, dir, title, writable}, по id.
static func list(roots: Array[String] = ModuleLoader.ROOTS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for root in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var dirs := DirAccess.get_directories_at(root)
		dirs.sort()
		for name in dirs:
			var dir := root.path_join(name)
			var path := dir.path_join(ModuleDoc.MANIFEST)
			if not FileAccess.file_exists(path):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary:
				continue
			var manifest: Dictionary = data
			(
				result
				. append(
					{
						"id": JsonRead.get_str(manifest, "id"),
						"dir": dir,
						"title": JsonRead.get_str(manifest, "title"),
						"writable": writable(dir),
					}
				)
			)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	return result


## Можно ли сохранять в папку модуля.
static func writable(dir: String) -> bool:
	if dir.begins_with("user://"):
		return true
	return dir.begins_with("res://") and not OS.has_feature("template")
