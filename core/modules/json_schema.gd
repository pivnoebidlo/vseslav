class_name JsonSchema
extends RefCounted
## Проверка данных по подмножеству JSON Schema 2020-12 (ADR-0028). Схемы лежат в
## schemas/ и служат единственным описанием формата: по ним проверяет игра, подсказывает
## редактор кода, строит формы редактор приключений.
##
## Поддержано: type, properties, required, additionalProperties, propertyNames, items,
## minItems, maxItems, enum, const, pattern, minLength, maxLength, minimum, maximum,
## anyOf, $ref (внутри схемы "#/$defs/x" и на другую схему "name.schema.json#/$defs/x").
## Любое другое ключевое слово — ошибка схемы (см. [method check_schema]): иначе автор
## схемы думал бы, что оно проверяется.

const ANNOTATIONS: Array[String] = [
	"$schema", "$id", "$defs", "$comment", "title", "description", "default", "examples"
]
const KEYWORDS: Array[String] = [
	"$ref",
	"type",
	"properties",
	"required",
	"additionalProperties",
	"propertyNames",
	"items",
	"minItems",
	"maxItems",
	"enum",
	"const",
	"pattern",
	"minLength",
	"maxLength",
	"minimum",
	"maximum",
	"anyOf",
]
const MAX_DEPTH := 64

## Схемы по имени файла ("module.schema.json") — для ссылок между схемами.
var schemas: Dictionary[String, Dictionary] = {}

var _patterns: Dictionary[String, RegEx] = {}


## Загружает все *.schema.json из папки. Ошибки чтения — в [param errors].
static func load_dir(dir: String, errors: Array[String]) -> JsonSchema:
	var js := JsonSchema.new()
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for file: String in files:
		if not file.ends_with(".schema.json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: not a JSON object" % dir.path_join(file))
			continue
		var schema: Dictionary = parsed
		js.schemas[file] = schema
	return js


## Проверяет [param value] по схеме [param schema_name]. Каждая ошибка — строка
## "<where><путь>: <что не так>"; путь в виде items[3].weight.
func validate(value: Variant, schema_name: String, where: String, errors: Array[String]) -> void:
	if not schemas.has(schema_name):
		errors.append("%s: no schema %s" % [where, schema_name])
		return
	var found: Array[String] = []
	_check(value, schemas[schema_name], schema_name, "$", found, 0)
	for e in found:
		errors.append("%s: %s" % [where, e])


## Ключевые слова, которые валидатор не умеет проверять, и битые $ref во всех схемах.
func check_schema(errors: Array[String]) -> void:
	var names: Array[String] = []
	names.assign(schemas.keys())
	names.sort()
	for name in names:
		_check_node(schemas[name], name, name, errors)


# --- Проверка значения ----------------------------------------------------------


func _check(
	value: Variant,
	schema: Dictionary,
	file: String,
	path: String,
	errors: Array[String],
	depth: int
) -> void:
	if depth > MAX_DEPTH:
		errors.append("%s: nested too deep" % path)
		return
	if schema.has("$ref"):
		var target := _resolve(file, str(schema["$ref"]))
		if target.is_empty():
			errors.append("%s: unresolved $ref %s" % [path, schema["$ref"]])
			return
		_check(value, target, _ref_file(file, str(schema["$ref"])), path, errors, depth + 1)
	if schema.has("type") and not _type_ok(value, schema["type"]):
		errors.append("%s: expected %s, got %s" % [path, _type_text(schema["type"]), _kind(value)])
		return
	if schema.has("enum"):
		var options: Array = schema["enum"]
		if not _contains(options, value):
			errors.append("%s: %s is not one of %s" % [path, JSON.stringify(value), options])
	if schema.has("const") and not _same(schema["const"], value):
		errors.append("%s: must be %s" % [path, JSON.stringify(schema["const"])])
	if schema.has("anyOf"):
		_check_any_of(value, schema, file, path, errors, depth)
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			_check_object(d, schema, file, path, errors, depth)
		TYPE_ARRAY:
			var a: Array = value
			_check_array(a, schema, file, path, errors, depth)
		TYPE_STRING:
			var s: String = value
			_check_string(s, schema, path, errors)
		TYPE_FLOAT, TYPE_INT:
			_check_number(value, schema, path, errors)


func _check_object(
	d: Dictionary, schema: Dictionary, file: String, path: String, errors: Array[String], depth: int
) -> void:
	var props: Dictionary = schema.get("properties", {})
	if schema.has("required"):
		var required: Array = schema["required"]
		for key: Variant in required:
			if not d.has(key):
				errors.append("%s: missing '%s'" % [path, key])
	var keys: Array[String] = []
	for key: Variant in d:
		keys.append(str(key))
	keys.sort()
	var extra: Variant = schema.get("additionalProperties", true)
	for key in keys:
		var at := _join(path, key)
		if schema.has("propertyNames"):
			var names: Dictionary = schema["propertyNames"]
			_check(key, names, file, at, errors, depth + 1)
		if props.has(key):
			var sub: Dictionary = props[key]
			_check(d[key], sub, file, at, errors, depth + 1)
		elif typeof(extra) == TYPE_BOOL:
			var allowed: bool = extra
			if not allowed:
				errors.append("%s: unknown field" % at)
		elif typeof(extra) == TYPE_DICTIONARY:
			var sub: Dictionary = extra
			_check(d[key], sub, file, at, errors, depth + 1)


func _check_array(
	a: Array, schema: Dictionary, file: String, path: String, errors: Array[String], depth: int
) -> void:
	if schema.has("minItems") and a.size() < _int(schema["minItems"]):
		errors.append("%s: at least %d items" % [path, _int(schema["minItems"])])
	if schema.has("maxItems") and a.size() > _int(schema["maxItems"]):
		errors.append("%s: at most %d items" % [path, _int(schema["maxItems"])])
	if not schema.has("items"):
		return
	var sub: Dictionary = schema["items"]
	for i in a.size():
		_check(a[i], sub, file, "%s[%d]" % [path, i], errors, depth + 1)


func _check_string(s: String, schema: Dictionary, path: String, errors: Array[String]) -> void:
	if schema.has("minLength") and s.length() < _int(schema["minLength"]):
		errors.append("%s: shorter than %d" % [path, _int(schema["minLength"])])
	if schema.has("maxLength") and s.length() > _int(schema["maxLength"]):
		errors.append("%s: longer than %d" % [path, _int(schema["maxLength"])])
	if schema.has("pattern"):
		var re := _regex(str(schema["pattern"]))
		if re != null and re.search(s) == null:
			errors.append("%s: '%s' does not match %s" % [path, s, schema["pattern"]])


## Границы — целые или дробные; JSON отдаёт все числа как float.
func _check_number(value: Variant, schema: Dictionary, path: String, errors: Array[String]) -> void:
	var f: float = value
	if schema.has("minimum"):
		var lo: float = schema["minimum"]
		if f < lo:
			errors.append("%s: less than %s" % [path, _num(lo)])
	if schema.has("maximum"):
		var hi: float = schema["maximum"]
		if f > hi:
			errors.append("%s: greater than %s" % [path, _num(hi)])


## 4 → "4", 0.1 → "0.1".
func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)


## anyOf: подходит хотя бы один вариант. Если не подошёл ни один, а по типу подходит
## ровно один вариант, показываем его ошибки — так понятнее, что исправить.
func _check_any_of(
	value: Variant,
	schema: Dictionary,
	file: String,
	path: String,
	errors: Array[String],
	depth: int
) -> void:
	var variants: Array = schema["anyOf"]
	var by_type: Array[Array] = []
	for v: Variant in variants:
		var sub: Dictionary = v
		var errs: Array[String] = []
		_check(value, sub, file, path, errs, depth + 1)
		if errs.is_empty():
			return
		var resolved := sub
		if sub.has("$ref"):
			resolved = _resolve(file, str(sub["$ref"]))
		if not resolved.has("type") or _type_ok(value, resolved["type"]):
			by_type.append(errs)
	if by_type.size() == 1:
		errors.append_array(by_type[0])
	else:
		errors.append("%s: matches none of the allowed forms" % path)


# --- Проверка самих схем --------------------------------------------------------


func _check_node(node: Variant, file: String, path: String, errors: Array[String]) -> void:
	if typeof(node) == TYPE_ARRAY:
		var arr: Array = node
		for i in arr.size():
			_check_node(arr[i], file, "%s[%d]" % [path, i], errors)
		return
	if typeof(node) != TYPE_DICTIONARY:
		return
	var d: Dictionary = node
	for key: Variant in d:
		var k := str(key)
		if not KEYWORDS.has(k) and not ANNOTATIONS.has(k):
			errors.append("%s: unsupported keyword '%s'" % [path, k])
	if d.has("$ref") and _resolve(file, str(d["$ref"])).is_empty():
		errors.append("%s: unresolved $ref %s" % [path, d["$ref"]])
	if d.has("pattern") and _regex(str(d["pattern"])) == null:
		errors.append("%s: bad pattern %s" % [path, d["pattern"]])
	for k: String in ["items", "additionalProperties", "propertyNames"]:
		if typeof(d.get(k)) == TYPE_DICTIONARY:
			_check_node(d[k], file, "%s.%s" % [path, k], errors)
	for k: String in ["properties", "$defs"]:
		if typeof(d.get(k)) == TYPE_DICTIONARY:
			var sub: Dictionary = d[k]
			for name: Variant in sub:
				_check_node(sub[name], file, "%s.%s.%s" % [path, k, name], errors)
	if typeof(d.get("anyOf")) == TYPE_ARRAY:
		_check_node(d["anyOf"], file, path + ".anyOf", errors)


# --- Внутреннее -----------------------------------------------------------------


## "#/$defs/x" — в той же схеме; "other.schema.json#/$defs/x" — в другой.
func _resolve(file: String, ref: String) -> Dictionary:
	var target_file := _ref_file(file, ref)
	if not schemas.has(target_file):
		return {}
	var node: Variant = schemas[target_file]
	var pointer := ref.get_slice("#", 1) if ref.contains("#") else ""
	for part in pointer.split("/", false):
		if typeof(node) != TYPE_DICTIONARY:
			return {}
		var d: Dictionary = node
		if not d.has(part):
			return {}
		node = d[part]
	if typeof(node) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary = node
	return result


func _ref_file(file: String, ref: String) -> String:
	var head := ref.get_slice("#", 0)
	return file if head == "" else head


func _type_ok(value: Variant, type: Variant) -> bool:
	if typeof(type) == TYPE_ARRAY:
		var types: Array = type
		for t: Variant in types:
			if _type_ok(value, t):
				return true
		return false
	var kind := _kind(value)
	if str(type) == "integer" and kind == "number":
		var f: float = value
		return f == floorf(f)
	return kind == str(type)


func _type_text(type: Variant) -> String:
	if typeof(type) == TYPE_ARRAY:
		var types: Array = type
		return " or ".join(PackedStringArray(types))
	return str(type)


func _kind(value: Variant) -> String:
	const KINDS := {
		TYPE_DICTIONARY: "object",
		TYPE_ARRAY: "array",
		TYPE_STRING: "string",
		TYPE_BOOL: "boolean",
		TYPE_NIL: "null",
		TYPE_FLOAT: "number",
		TYPE_INT: "number",
	}
	return str(KINDS.get(typeof(value), type_string(typeof(value))))


## Сравнение значений JSON: числа из JSON — float, из схемы — тоже float, строки — строки.
func _same(a: Variant, b: Variant) -> bool:
	var numbers: Array[int] = [TYPE_FLOAT, TYPE_INT]
	if numbers.has(typeof(a)) and numbers.has(typeof(b)):
		var fa: float = a
		var fb: float = b
		return fa == fb
	return typeof(a) == typeof(b) and a == b


func _contains(options: Array, value: Variant) -> bool:
	for o: Variant in options:
		if _same(o, value):
			return true
	return false


func _regex(pattern: String) -> RegEx:
	if _patterns.has(pattern):
		return _patterns[pattern]
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return null
	_patterns[pattern] = re
	return re


func _int(v: Variant) -> int:
	return JsonRead.to_int(v)


func _join(path: String, key: String) -> String:
	return "%s.%s" % [path, key]
