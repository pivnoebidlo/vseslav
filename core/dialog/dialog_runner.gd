class_name DialogRunner
extends RefCounted
## Разговор по данным dialogs/<id>.json (ADR-0029): узлы с репликой собеседника и
## вариантами ответа. Условия ответов и начала ("if") и действия ("then") — в том же
## виде, что у декларативных событий (SPEC §8): {"flag", "eq"} и {"action": "set_flag"}.
## Ответ может требовать проверки характеристики (ADR-0031): {"check": {"ability", "dc"}},
## успех ведёт в "next", провал — в "fail" (без "fail" провал заканчивает разговор).

var dialog_id: String = ""
## Последняя проверка (для анимации броска); null — ответ был без проверки.
var last_check: CheckResult = null
## Квесты, чья стадия изменилась при последнем выборе (для подсказки «Журнал обновлён»).
var quests_changed: Array[String] = []
## Текущий узел; пусто — разговор окончен.
var node_id: String = ""

var _nodes: Dictionary = {}
var _flags: WorldFlags
## Контекст действий (ADR-0042): вещи, отряд, запросы к игре.
var _ctx: EventContext


## Начинает разговор: первый узел из "start", чьё условие выполнено. [param ctx] —
## отряд и правила для действий с вещами и составом; без него — только флаги.
static func start(
	p_id: String, data: Dictionary, flags: WorldFlags, ctx: EventContext = null
) -> DialogRunner:
	var r := DialogRunner.new()
	r.dialog_id = p_id
	r._nodes = JsonRead.get_dict(data, "nodes")
	r._flags = flags
	r._ctx = ctx if ctx != null else EventContext.new(flags)
	r._enter(start_node(data, flags))
	return r


## Запросы к игре, накопленные разговором (диалог, бой, перенос, вещи…).
func take_requests() -> Array[Dictionary]:
	return _ctx.take_requests()


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
## Для ответа с проверкой бросает d20 через [param rng] с характеристиками
## [param speaker] — того, кто говорит.
func choose(index: int, rng: Rng = null, speaker: Abilities = null) -> void:
	last_check = null
	quests_changed.clear()
	var visible := options()
	if visible.is_empty():
		node_id = ""
		return
	if index < 0 or index >= visible.size():
		return
	var option := visible[index]
	var next := JsonRead.get_str(option, "next")
	var check := JsonRead.get_dict(option, "check")
	if not check.is_empty():
		var ability := JsonRead.get_str(check, "ability")
		var modifier := speaker.modifier(ability) if speaker != null else 0
		last_check = CheckResolver.roll(
			rng if rng != null else Rng.new(), modifier, JsonRead.get_int(check, "dc")
		)
		if not last_check.success:
			next = JsonRead.get_str(option, "fail")
	_run(JsonRead.get_array(option, "then"))
	_enter(next)


func _enter(id: String) -> void:
	node_id = id if _nodes.has(id) else ""
	if node_id != "":
		_run(JsonRead.get_array(_node(), "then"))


func _run(actions: Array) -> void:
	_ctx.quests.clear()
	EventActions.run(actions, _ctx)
	quests_changed.append_array(_ctx.quests)


func _node() -> Dictionary:
	if node_id == "" or not _nodes.has(node_id):
		return {}
	var node: Dictionary = _nodes[node_id]
	return node
