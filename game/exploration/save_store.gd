class_name SaveStore
extends RefCounted
## Сохранения игры на диске (user://saves, ADR-0032): быстрое (F5) и автосохранение
## перед каждым боем. Загружается самое свежее. Загрузка — через смену сцены: сцена
## исследования при старте берёт [member pending].

const DIR := "user://saves"
const QUICK := "user://saves/game_quick.json"
const AUTO := "user://saves/game_auto.json"

## Сохранение, которое сцена исследования применит при старте.
static var pending: GameSave = null
## Начать новую игру: флаги и партия — с нуля.
static var new_game := false


static func write(save: GameSave, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(save.to_dict(), "  ", true))
	file.close()


static func has_any() -> bool:
	return FileAccess.file_exists(QUICK) or FileAccess.file_exists(AUTO)


## Самое свежее сохранение; null — нет или не читается (причины — в [param errors]).
static func latest(errors: Array[String]) -> GameSave:
	var path := ""
	var newest := -1
	for p: String in [QUICK, AUTO]:
		if FileAccess.file_exists(p) and FileAccess.get_modified_time(p) > newest:
			newest = FileAccess.get_modified_time(p)
			path = p
	if path == "":
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append(GameSave.ERR_DATA)
		return null
	var data: Dictionary = parsed
	return GameSave.from_dict(data, errors)
