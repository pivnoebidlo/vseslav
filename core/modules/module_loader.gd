class_name ModuleLoader
extends RefCounted
## Загрузка модулей из папок (SPEC §7, ADR-0028): поиск, проверка файлов по схемам,
## порядок зависимостей, сборка содержимого и проверка ссылок. Модуль с любой ошибкой
## не загружается, вместе со всеми, кто от него зависит.

const ROOTS: Array[String] = ["res://modules", "user://modules"]
const SCHEMA_DIR := "res://schemas"
const MAX_FILES := 2000
const MAX_DEPTH := 8
const MAX_JSON_BYTES := 4 * 1024 * 1024
const ASSET_EXTENSIONS: Array[String] = ["png", "ogg", "glb"]
## Служебные файлы редактора Godot рядом с ассетами в res:// — не часть модуля.
const IGNORED_SUFFIXES: Array[String] = [".import", ".uid"]
const RULES_FILES: Array[String] = RulesDb.FILES
const FIXED_FILES: Dictionary[String, String] = {
	"module.json": "module.schema.json",
	"merchants.json": "merchants.schema.json",
	"world/world.json": "world.schema.json",
	"models/models.json": "models.schema.json",
	"props/props.json": "props.schema.json",
	"surfaces/surfaces.json": "surfaces.schema.json",
}
## Папки, где каждый .json — отдельная запись своего типа.
const DIR_FILES: Dictionary[String, String] = {
	"areas": "area.schema.json",
	"dialogs": "dialog.schema.json",
	"quests": "quest.schema.json",
	"locales": "locale.schema.json",
}


## Пакет модуля: манифест, разобранные файлы и ошибки их проверки.
class Package:
	extends RefCounted
	var manifest: ModuleManifest
	## Путь внутри модуля → разобранный JSON.
	var files: Dictionary[String, Variant] = {}
	var errors: Array[String] = []


var _schema: JsonSchema
var _path_re := RegEx.create_from_string("^[a-z0-9_]+(/[a-z0-9_]+)*\\.[a-z0-9]+$")


## Загружает все модули из [param roots]. Схемы — из [param schema_dir].
static func load_all(
	roots: Array[String] = ROOTS, schema_dir: String = SCHEMA_DIR
) -> ModuleContent:
	var loader := ModuleLoader.new()
	var schema_errors: Array[String] = []
	loader._schema = JsonSchema.load_dir(schema_dir, schema_errors)
	if not schema_errors.is_empty():
		var broken := ModuleContent.new()
		broken.errors = schema_errors
		return broken
	return loader._load(loader._discover(roots))


## Пакеты из подпапок [param roots], в которых есть module.json.
func _discover(roots: Array[String]) -> Array[Package]:
	var packages: Array[Package] = []
	for root in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var dirs := Array(DirAccess.get_directories_at(root))
		dirs.sort()
		for d: String in dirs:
			var dir := root.path_join(d)
			if FileAccess.file_exists(dir.path_join("module.json")):
				packages.append(_read_package(dir))
	return packages


func _load(packages: Array[Package]) -> ModuleContent:
	var by_id: Dictionary[String, Package] = {}
	var content := ModuleContent.new()
	var problems: Dictionary[String, Array] = {}
	for p in packages:
		var id := p.manifest.id
		if by_id.has(id):
			content.errors.append(
				(
					"%s: module '%s' is already loaded from %s"
					% [p.manifest.dir, id, by_id[id].manifest.dir]
				)
			)
			continue
		by_id[id] = p
	var loaded: Array[Package] = []
	for id in _order(by_id, problems):
		var p := by_id[id]
		var errs: Array[String] = []
		errs.append_array(p.errors)
		var order_problems: Array = problems.get(id, [])
		for e: Variant in order_problems:
			errs.append(str(e))
		for dep in p.manifest.dependencies:
			if not _contains(loaded, dep):
				errs.append("dependency '%s' is missing or failed to load" % dep)
		var candidate := loaded.duplicate()
		candidate.append(p)
		var built: ModuleContent = null
		if errs.is_empty():
			built = _assemble(candidate, by_id)
			errs.append_array(built.errors)
		if errs.is_empty():
			loaded = candidate
			content = _keep_errors(built, content)
		else:
			content.failed.append(id)
			for e in errs:
				content.errors.append("%s: %s" % [id, e])
	return content


## Переносит уже накопленные ошибки и отказы в новую сборку.
func _keep_errors(built: ModuleContent, previous: ModuleContent) -> ModuleContent:
	built.errors = previous.errors
	built.failed = previous.failed
	return built


# --- Чтение пакета --------------------------------------------------------------


func _read_package(dir: String) -> Package:
	var p := Package.new()
	var paths: Array[String] = []
	_list_files(dir, "", paths, 0, p.errors)
	for rel in paths:
		_read_file(p, dir, rel)
	var raw: Variant = p.files.get("module.json", {})
	var data: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	p.manifest = ModuleManifest.from_dict(data, dir)
	if p.manifest.id == "":
		p.manifest.id = dir.get_file()
	var errs: Array[String] = []
	p.manifest.check(errs)
	for e in errs:
		p.errors.append("module.json: " + e)
	return p


func _list_files(
	dir: String, rel: String, out: Array[String], depth: int, errors: Array[String]
) -> void:
	if depth > MAX_DEPTH:
		errors.append("%s: folders nested too deep" % rel)
		return
	var here := dir.path_join(rel) if rel != "" else dir
	var files := Array(DirAccess.get_files_at(here))
	files.sort()
	for f: String in files:
		if _ignored(f):
			continue
		if out.size() >= MAX_FILES:
			errors.append("more than %d files" % MAX_FILES)
			return
		out.append(rel.path_join(f) if rel != "" else f)
	var subdirs := Array(DirAccess.get_directories_at(here))
	subdirs.sort()
	for d: String in subdirs:
		_list_files(dir, rel.path_join(d) if rel != "" else d, out, depth + 1, errors)


func _ignored(file: String) -> bool:
	for suffix in IGNORED_SUFFIXES:
		if file.ends_with(suffix):
			return true
	return false


func _read_file(p: Package, dir: String, rel: String) -> void:
	if _path_re.search(rel) == null:
		p.errors.append("%s: bad file name (lowercase latin, digits, _ only)" % rel)
		return
	var ext := rel.get_extension()
	if ASSET_EXTENSIONS.has(ext):
		return
	if ext != "json":
		p.errors.append("%s: file type .%s is not allowed in modules" % [rel, ext])
		return
	var schema_name := _schema_for(rel)
	if schema_name == "":
		p.errors.append(
			"%s: unknown file (not part of module format %d)" % [rel, ModuleManifest.FORMAT]
		)
		return
	_parse_json(p, dir.path_join(rel), rel, schema_name)


## Читает JSON-файл с проверкой размера и схемы; разобранное — в p.files.
func _parse_json(p: Package, path: String, rel: String, schema_name: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		p.errors.append("%s: cannot read" % rel)
		return
	if file.get_length() > MAX_JSON_BYTES:
		p.errors.append("%s: larger than %d bytes" % [rel, MAX_JSON_BYTES])
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		# JSON считает строки с нуля, человеку привычнее с единицы.
		p.errors.append("%s:%d: %s" % [rel, json.get_error_line() + 1, json.get_error_message()])
		return
	_schema.validate(json.data, schema_name, rel, p.errors)
	p.files[rel] = json.data


func _schema_for(rel: String) -> String:
	if FIXED_FILES.has(rel):
		return FIXED_FILES[rel]
	var dir := rel.get_base_dir()
	if dir == "rules" and RULES_FILES.has(rel.get_file().get_basename()):
		return rel.get_file().get_basename() + ".schema.json"
	if DIR_FILES.has(dir):
		return DIR_FILES[dir]
	return ""


# --- Порядок зависимостей -------------------------------------------------------


## Id в порядке загрузки: зависимости раньше, иначе по алфавиту. Циклы — в [param problems].
func _order(
	by_id: Dictionary[String, Package], problems: Dictionary[String, Array]
) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(by_id.keys())
	ids.sort()
	var state: Dictionary[String, int] = {}
	var out: Array[String] = []
	for id in ids:
		_visit(id, by_id, state, out, problems, [])
	return out


func _visit(
	id: String,
	by_id: Dictionary[String, Package],
	state: Dictionary[String, int],
	out: Array[String],
	problems: Dictionary[String, Array],
	stack: Array[String],
) -> void:
	if not by_id.has(id) or state.get(id, 0) == 2:
		return
	if state.get(id, 0) == 1:
		var cycle := stack.slice(stack.find(id))
		var text := " -> ".join(PackedStringArray(cycle)) + " -> " + id
		for member: String in cycle:
			var list: Array = problems.get(member, [])
			list.append("dependency cycle: " + text)
			problems[member] = list
		return
	state[id] = 1
	stack.append(id)
	var deps := by_id[id].manifest.dependencies.duplicate()
	deps.sort()
	for dep: String in deps:
		_visit(dep, by_id, state, out, problems, stack)
	stack.pop_back()
	state[id] = 2
	out.append(id)


func _ancestors(id: String, by_id: Dictionary[String, Package]) -> Array[String]:
	var result: Array[String] = []
	var queue: Array[String] = [id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if not by_id.has(current):
			continue
		for dep in by_id[current].manifest.dependencies:
			if not result.has(dep):
				result.append(dep)
				queue.append(dep)
	result.sort()
	return result


func _contains(packages: Array[Package], id: String) -> bool:
	for p in packages:
		if p.manifest.id == id:
			return true
	return false


# --- Сборка ---------------------------------------------------------------------


## Собирает содержимое модулей [param packages] (по порядку) и проверяет ссылки.
func _assemble(packages: Array[Package], by_id: Dictionary[String, Package]) -> ModuleContent:
	var content := ModuleContent.new()
	var owners := ContentOwners.new()
	content.rules.owners = owners
	for p in packages:
		var id := p.manifest.id
		var errs: Array[String] = []
		owners.begin(id, _ancestors(id, by_id))
		_add_rules(content, p)
		_add_entries(content, p, owners, errs)
		content.modules.append(p.manifest)
		for e in errs:
			content.errors.append(e)
	content.rules.validate()
	for e in content.rules.errors:
		content.errors.append("rules: " + e)
	ModuleRefs.check(content, content.errors)
	return content


func _add_rules(content: ModuleContent, p: Package) -> void:
	for file in RULES_FILES:
		var rel := "rules/%s.json" % file
		if p.files.has(rel):
			var data: Dictionary = p.files[rel]
			content.rules.add(file, data)


func _add_entries(
	content: ModuleContent, p: Package, owners: ContentOwners, errs: Array[String]
) -> void:
	var rels: Array[String] = []
	rels.assign(p.files.keys())
	rels.sort()
	for rel in rels:
		var data: Dictionary = p.files[rel]
		var dir := rel.get_base_dir()
		var entry_id := rel.get_file().get_basename()
		if dir == "areas":
			if owners.claim("areas", entry_id, errs):
				content.areas[entry_id] = data
		elif dir == "dialogs":
			if owners.claim("dialogs", entry_id, errs):
				content.dialogs[entry_id] = data
		elif dir == "quests":
			if owners.claim("quests", entry_id, errs):
				content.quests[entry_id] = data
		elif dir == "locales":
			var lang := rel.get_file().get_basename()
			var strings: Dictionary = content.locales.get(lang, {})
			strings.merge(data, true)
			content.locales[lang] = strings
		elif rel == "world/world.json":
			if owners.claim("world", "world", errs):
				content.world = data
		elif rel == "merchants.json":
			for raw: Variant in JsonRead.get_array(data, "merchants"):
				var m: Dictionary = raw
				var mid := JsonRead.get_str(m, "id")
				if owners.claim("merchants", mid, errs):
					content.merchants[mid] = m
		elif rel == "props/props.json":
			var props := JsonRead.get_dict(data, "props")
			var prop_ids: Array[String] = []
			prop_ids.assign(props.keys())
			prop_ids.sort()
			for pid in prop_ids:
				var prop: Dictionary = props[pid]
				if owners.claim("props", pid, errs):
					content.props[pid] = prop
					content.prop_dirs[pid] = p.manifest.dir.path_join("props")
		elif rel == "surfaces/surfaces.json":
			var surfaces := JsonRead.get_dict(data, "surfaces")
			var surface_ids: Array[String] = []
			surface_ids.assign(surfaces.keys())
			surface_ids.sort()
			for sid in surface_ids:
				var surface: Dictionary = surfaces[sid]
				if owners.claim("surfaces", sid, errs):
					content.surfaces[sid] = surface
					content.surface_dirs[sid] = p.manifest.dir.path_join("surfaces")
		elif rel == "models/models.json":
			var figures := JsonRead.get_dict(data, "figures")
			var ids: Array[String] = []
			ids.assign(figures.keys())
			ids.sort()
			for fid in ids:
				var figure: Dictionary = figures[fid]
				if owners.claim("figures", fid, errs):
					content.figures[fid] = figure
					content.figure_dirs[fid] = p.manifest.dir.path_join("models")
