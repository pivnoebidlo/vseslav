class_name JsonRead
extends RefCounted
## Типизированное чтение данных из JSON.
## JSON.parse_string() возвращает все числа как float, а строгий режим проекта
## запрещает int(Variant) — поэтому всё чтение данных идёт через эти функции.


static func to_int(value: Variant, default: int = 0) -> int:
	match typeof(value):
		TYPE_INT:
			var i: int = value
			return i
		TYPE_FLOAT:
			var f: float = value
			if f != floorf(f):
				push_error("Expected integer, got %s" % f)
			return int(f)
		TYPE_STRING:
			var s: String = value
			if s.is_valid_int():
				return s.to_int()
	push_error("Expected integer, got %s" % type_string(typeof(value)))
	return default


static func get_int(data: Dictionary, key: String, default: int = 0) -> int:
	if not data.has(key):
		return default
	return to_int(data[key], default)


static func get_bool(data: Dictionary, key: String, default: bool = false) -> bool:
	var value: Variant = data.get(key, default)
	if typeof(value) != TYPE_BOOL:
		push_error("Expected bool for '%s'" % key)
		return default
	var b: bool = value
	return b


static func get_str(data: Dictionary, key: String, default: String = "") -> String:
	return str(data.get(key, default))


static func get_array(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		push_error("Expected array for '%s'" % key)
		return []
	var a: Array = value
	return a


static func get_dict(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		push_error("Expected object for '%s'" % key)
		return {}
	var d: Dictionary = value
	return d


## Массив строк; не-строки приводятся через str().
static func get_str_array(data: Dictionary, key: String) -> Array[String]:
	var result: Array[String] = []
	for item: Variant in get_array(data, key):
		result.append(str(item))
	return result


## Пара [x, z] → Vector2i.
static func to_vec2i(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		push_error("Expected [x, z]")
		return Vector2i.ZERO
	var a: Array = value
	if a.size() != 2:
		push_error("Expected [x, z]")
		return Vector2i.ZERO
	return Vector2i(to_int(a[0]), to_int(a[1]))
