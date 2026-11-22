class_name ContentOwners
extends RefCounted
## Кто из модулей объявил запись с данным id (ADR-0028). Модуль может целиком заменить
## запись своей зависимости (прямой или через другие модули); совпадение id внутри
## одного модуля или с независимым модулем — ошибка.

var _owner: Dictionary[String, String] = {}
var _module: String = ""
var _ancestors: Array[String] = []


## Дальше записи объявляет модуль [param module_id]; [param ancestors] — все его
## зависимости, включая непрямые.
func begin(module_id: String, ancestors: Array[String]) -> void:
	_module = module_id
	_ancestors = ancestors


## true — запись [param kind]/[param id] можно положить: она новая или заменяет запись
## зависимости. Иначе причина — в [param errors].
func claim(kind: String, id: String, errors: Array[String]) -> bool:
	var key := "%s:%s" % [kind, id]
	if not _owner.has(key):
		_owner[key] = _module
		return true
	var previous: String = _owner[key]
	if previous == _module:
		errors.append("%s: duplicate id '%s'" % [kind, id])
		return false
	if _ancestors.has(previous):
		_owner[key] = _module
		return true
	errors.append(
		"%s: '%s' is already defined by %s, which is not a dependency" % [kind, id, previous]
	)
	return false


## Модуль, чья запись сейчас действует (пусто — записи нет).
func owner_of(kind: String, id: String) -> String:
	return _owner.get("%s:%s" % [kind, id], "")
