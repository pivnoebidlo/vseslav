class_name AssetOps
extends RefCounted
## Свои ассеты модуля (ADR-0041): модель окружения (GLB) в props/ и поверхность (PNG)
## в surfaces/. Файл копируется в папку модуля сразу (отмена записи его не удаляет —
## лишний файл безвреден), запись в props.json/surfaces.json — обычной правкой.
## Проверку самих файлов (лимиты GLB, PNG) делает игра перед импортом.

const PROPS := ModuleDoc.KIND_PROPS
const SURFACES := ModuleDoc.KIND_SURFACES
const SPINS: Array[String] = ["none", "quarter", "free"]
## Рядом с файлом в res:// — пометка «не импортировать» (файлы модуля читаются как есть).
const KEEP_IMPORT := '[remap]\n\nimporter="keep"\n'


## Копирует [param source] в папку модуля [param kind]/ под именем [param name];
## возвращает имя файла или "" (причина — в [param errors]).
static func copy_file(
	doc: ModuleDoc, source: String, kind: String, name: String, errors: Array[String]
) -> String:
	var ext := source.get_extension().to_lower()
	var file := "%s.%s" % [name, ext]
	if not ModuleDoc.is_valid_id(name) or name.contains("."):
		errors.append("bad file name '%s'" % name)
		return ""
	var dir := doc.dir.path_join(kind)
	DirAccess.make_dir_recursive_absolute(dir)
	var target := dir.path_join(file)
	if DirAccess.copy_absolute(source, target) != OK:
		errors.append("cannot copy %s" % source)
		return ""
	if target.begins_with("res://"):
		var marker := FileAccess.open(target + ".import", FileAccess.WRITE)
		if marker != null:
			marker.store_string(KEEP_IMPORT)
			marker.close()
	return file


## Регистрирует модель [param file] как prop [param prop_id] (fit — во сколько раз
## может быть больше клеток, jitter — разброс размера, spin — случайный поворот).
static func register_prop(
	doc: ModuleDoc, prop_id: String, file: String, fit: float, jitter: float, spin: String
) -> DocEdit:
	var entry := {"file": file}
	if not is_equal_approx(fit, 1.0):
		entry["fit"] = snappedf(fit, 0.05)
	if jitter > 0.0:
		entry["jitter"] = snappedf(jitter, 0.05)
	if spin != "none" and SPINS.has(spin):
		entry["spin"] = spin
	var edit := DocEdit.new("register prop")
	if not doc.has(PROPS, PROPS):
		edit.set_value(doc, PROPS, PROPS, [], {"props": {}})
	edit.set_value(doc, PROPS, PROPS, ["props", prop_id], entry)
	return edit


## Регистрирует поверхность: [param files] — color (обязательно), normal, roughness.
static func register_surface(
	doc: ModuleDoc, surface_id: String, files: Dictionary, tile: float
) -> DocEdit:
	var entry := {}
	for key: String in ["color", "normal", "roughness"]:
		if JsonRead.get_str(files, key) != "":
			entry[key] = files[key]
	entry["tile"] = snappedf(tile, 0.5)
	var edit := DocEdit.new("register surface")
	if not doc.has(SURFACES, SURFACES):
		edit.set_value(doc, SURFACES, SURFACES, [], {"surfaces": {}})
	edit.set_value(doc, SURFACES, SURFACES, ["surfaces", surface_id], entry)
	return edit


static func prop_ids(doc: ModuleDoc) -> Array[String]:
	return _ids(doc, PROPS, "props")


static func surface_ids(doc: ModuleDoc) -> Array[String]:
	return _ids(doc, SURFACES, "surfaces")


static func _ids(doc: ModuleDoc, kind: String, field: String) -> Array[String]:
	var value: Variant = doc.get_value(kind, kind, [field])
	var ids: Array[String] = []
	if value is Dictionary:
		var d: Dictionary = value
		ids.assign(d.keys())
	ids.sort()
	return ids
