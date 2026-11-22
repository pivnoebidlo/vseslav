class_name DialogRunner
extends RefCounted
## Разговор по данным dialogs/<id>.json (ADR-0029): узлы с репликой собеседника и
## вариантами ответа. Условия ответов и начала ("if") и действия ("then") — в том же
## виде, что у декларативных событий (SPEC §8): {"flag", "eq"} и {"action": "set_flag"}.

const ACTION_SET_FLAG := "set_flag"
const ACTIONS: Array[String] = [ACTION_SET_FLAG]

var dialog_id: String = ""
## Текущий узел; пусто — разговор окончен.
var node_id: String = ""

var _nodes: Dictionary = {}
var _flags: WorldFlags


## Начинает разговор: первый узел из "start", чьё условие выполнено.
static func start(p_id: String, data: Dictionary, flags: WorldFlags) -> DialogRunner:
	var r := DialogRunner.new()
	r.dialog_id = p_id
	r._nodes = JsonRead.get_dict(data, "nodes")
	r._flags = flags
	r._enter(start_node(data, flags))
	return r


## "start" — id узла или список [{"if": [...], "node": id}], первый подходящий.
static func start_node(data: Dictionary, flags: WorldFlags) -> String:
	var start_value: Variant = data.get("start", "")
	if typeof(start_value) == TYPE_STRING:
		return str(start_value)
	if typeof(start_value) != TYPE_ARRAY:
		return ""
	var variants: Array = start_value
	for raw: Variant in variants:
		var v: Dictionary = raw
		if flags.all_match(JsonRead.get_array(v, "if")):
			return JsonRead.get_str(v, "node")
	return ""


## Применяет действия списка "then".
static func apply(actions: Array, flags: WorldFlags) -> void:
	for raw: Variant in actions:
		var a: Dictionary = raw
		match JsonRead.get_str(a, "action"):
			ACTION_SET_FLAG:
				flags.set_flag(JsonRead.get_str(a, "flag"), a.get("value", true))


func ended() -> bool:
	return node_id == ""


## Ключ строки реплики собеседника.
func text_key() -> String:
	return JsonRead.get_str(_node(), "text")


## Ответы, чьи условия выполнены: {"text": ключ, ...} в порядке данных.
func options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in JsonRead.get_array(_node(), "options"):
		var option: Dictionary = raw
		if _flags.all_match(JsonRead.get_array(option, "if")):
			result.append(option)
	return result


## Выбрать ответ по номеру среди [method options]. Ответ без "next" заканчивает
## разговор; без вариантов ответа разговор заканчивает выбор 0 («уйти»).
func choose(index: int) -> void:
	var visible := options()
	if visible.is_empty():
		node_id = ""
		return
	if index < 0 or index >= visible.size():
		return
	var option := visible[index]
	apply(JsonRead.get_array(option, "then"), _flags)
	_enter(JsonRead.get_str(option, "next"))


func _enter(id: String) -> void:
	node_id = id if _nodes.has(id) else ""
	if node_id != "":
		apply(JsonRead.get_array(_node(), "then"), _flags)


func _node() -> Dictionary:
	if node_id == "" or not _nodes.has(node_id):
		return {}
	var node: Dictionary = _nodes[node_id]
	return node
