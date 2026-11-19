extends GutTest
## У каждого ключа имени в данных модулей есть строка на русском и английском.

const MODULES: Array[String] = ["res://modules/base", "res://modules/spike"]


func _locale(module: String, lang: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(module.path_join("locales/%s.json" % lang))
	var parsed: Dictionary = JSON.parse_string(text)
	return parsed


## Все значения полей name_key/title_key во вложенных словарях и массивах.
func _collect_keys(value: Variant, into: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		for key: Variant in d:
			if str(key) == "name_key" or str(key) == "title_key":
				into.append(str(d[key]))
			else:
				_collect_keys(d[key], into)
	elif typeof(value) == TYPE_ARRAY:
		var a: Array = value
		for item: Variant in a:
			_collect_keys(item, into)


func test_every_name_key_is_translated() -> void:
	var ru := {}
	var en := {}
	for module in MODULES:
		ru.merge(_locale(module, "ru"))
		en.merge(_locale(module, "en"))
	assert_eq(ru.keys().size(), en.keys().size(), "ru and en have the same keys")
	var keys: Array[String] = []
	for module in MODULES:
		for dir: String in ["rules", "arenas"]:
			var path := module.path_join(dir)
			if not DirAccess.dir_exists_absolute(path):
				continue
			for file in DirAccess.get_files_at(path):
				if file.get_extension() == "json":
					_collect_keys(
						JSON.parse_string(FileAccess.get_file_as_string(path.path_join(file))), keys
					)
	assert_gt(keys.size(), 30)
	for key in keys:
		assert_true(ru.has(key), "ru: %s" % key)
		assert_true(en.has(key), "en: %s" % key)
