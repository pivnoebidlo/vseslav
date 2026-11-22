class_name ModuleLocales
extends RefCounted
## Строки модуля (locales/<lang>.json, SPEC §7) → TranslationServer.
## Ключи модуля не пересекаются с ключами интерфейса (locales/ui.csv).

const LANGS: Array[String] = ["ru", "en"]

## Строки, добавленные через [method apply]: при повторной загрузке (смена сцены)
## прежние убираются, чтобы не копились.
static var _applied: Array[Translation] = []


## Строки всех загруженных модулей (ModuleContent.locales: язык → ключ → текст).
static func apply(locales: Dictionary[String, Dictionary]) -> void:
	for old in _applied:
		TranslationServer.remove_translation(old)
	_applied.clear()
	var langs: Array[String] = []
	langs.assign(locales.keys())
	langs.sort()
	for lang in langs:
		_applied.append(_add(lang, locales[lang]))


## Добавляет строки модуля из папки [param module_dir] для всех языков.
static func load_module(module_dir: String) -> void:
	for lang in LANGS:
		var path := module_dir.path_join("locales").path_join(lang + ".json")
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Bad locale file: %s" % path)
			continue
		var data: Dictionary = parsed
		_add(lang, data)


static func _add(lang: String, data: Dictionary) -> Translation:
	var translation := Translation.new()
	translation.locale = lang
	for key: Variant in data:
		translation.add_message(StringName(str(key)), str(data[key]))
	TranslationServer.add_translation(translation)
	return translation
