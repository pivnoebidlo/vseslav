class_name DialogOps
extends RefCounted
## Правки диалогов (ADR-0039): новый диалог, реплики, ответы, связи, тексты.
## Каждая функция возвращает DocEdit — применяет его UndoStack. Ключи строк
## создаются сами: DLG_<ДИАЛОГ>_<РЕПЛИКА> и DLG_<ДИАЛОГ>_<РЕПЛИКА>_O<n>.

const KIND := ModuleDoc.KIND_DIALOG
const FIRST_NODE := "start"
## Метаданные редактора в файле диалога (игрой не читаются): положения реплик в графе.
const EDITOR_KEY := "_editor"


static func node_key(dialog_id: String, node_id: String) -> String:
	return ("DLG_%s_%s" % [dialog_id, node_id]).replace(".", "_").to_upper()


## Новый диалог с первой репликой [param text] (по-русски).
static func new_dialog(doc: ModuleDoc, dialog_id: String, text: String) -> DocEdit:
	var key := node_key(dialog_id, FIRST_NODE)
	var data := {"start": FIRST_NODE, "nodes": {FIRST_NODE: {"text": key}}}
	var edit := DocEdit.new("new dialog")
	edit.set_value(doc, KIND, dialog_id, [], data)
	edit.set_text(doc, key, "ru", text)
	return edit


static func delete_dialog(doc: ModuleDoc, dialog_id: String) -> DocEdit:
	var edit := DocEdit.new("delete dialog")
	for key in _keys_of(doc.entry(KIND, dialog_id)):
		for lang in ModuleDoc.LANGS:
			if doc.text(key, lang) != "":
				edit.set_text(doc, key, lang, "")
	edit.set_value(doc, KIND, dialog_id, [], null)
	return edit


## Свободный id реплики: [param base], base_2, base_3…
static func free_node_id(doc: ModuleDoc, dialog_id: String, base: String = "node") -> String:
	var nodes := _nodes(doc, dialog_id)
	if not nodes.has(base):
		return base
	var n := 2
	while nodes.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


## Новая реплика; если задан ответ ([param from_node], [param option]), он ведёт к ней.
static func add_node(
	doc: ModuleDoc,
	dialog_id: String,
	node_id: String,
	text: String,
	from_node: String = "",
	option: int = -1
) -> DocEdit:
	var key := node_key(dialog_id, node_id)
	var edit := DocEdit.new("add node")
	edit.set_value(doc, KIND, dialog_id, ["nodes", node_id], {"text": key})
	edit.set_text(doc, key, "ru", text)
	if from_node != "" and option >= 0:
		var options := options_of(doc, dialog_id, from_node)
		if option < options.size():
			var picked: Dictionary = options[option]
			var changed := picked.duplicate(true)
			changed["next"] = node_id
			options[option] = changed
			edit.set_value(doc, KIND, dialog_id, ["nodes", from_node, "options"], options)
	return edit


## Удаляет реплику и её строки; ответы, которые вели к ней, теперь заканчивают разговор.
static func remove_node(doc: ModuleDoc, dialog_id: String, node_id: String) -> DocEdit:
	var edit := DocEdit.new("remove node")
	var nodes := _nodes(doc, dialog_id)
	for other: String in _sorted(nodes.keys()):
		if other == node_id:
			continue
		var options := options_of(doc, dialog_id, other)
		var touched := false
		for i in options.size():
			var o: Dictionary = options[i]
			for field: String in ["next", "fail"]:
				if JsonRead.get_str(o, field) == node_id:
					o.erase(field)
					touched = true
		if touched:
			edit.set_value(doc, KIND, dialog_id, ["nodes", other, "options"], options)
	var node: Dictionary = nodes.get(node_id, {})
	for key in _node_keys(node):
		for lang in ModuleDoc.LANGS:
			if doc.text(key, lang) != "":
				edit.set_text(doc, key, lang, "")
	edit.set_value(doc, KIND, dialog_id, ["nodes", node_id], null)
	edit.set_value(doc, KIND, dialog_id, [EDITOR_KEY, "pos", node_id], null)
	var start: Variant = doc.get_value(KIND, dialog_id, ["start"])
	if start is String and start == node_id:
		var rest: Array[String] = _sorted(nodes.keys())
		rest.erase(node_id)
		edit.set_value(doc, KIND, dialog_id, ["start"], rest[0] if not rest.is_empty() else null)
	return edit


## Новый ответ в конце списка реплики.
static func add_option(doc: ModuleDoc, dialog_id: String, node_id: String, text: String) -> DocEdit:
	var options := options_of(doc, dialog_id, node_id)
	var key := free_option_key(doc, dialog_id, node_id)
	options.append({"text": key})
	var edit := DocEdit.new("add option")
	edit.set_value(doc, KIND, dialog_id, ["nodes", node_id, "options"], options)
	edit.set_text(doc, key, "ru", text)
	return edit


static func remove_option(
	doc: ModuleDoc, dialog_id: String, node_id: String, index: int
) -> DocEdit:
	var options := options_of(doc, dialog_id, node_id)
	var edit := DocEdit.new("remove option")
	if index < 0 or index >= options.size():
		return edit
	var removed: Dictionary = options[index]
	var key := JsonRead.get_str(removed, "text")
	if key.begins_with(node_key(dialog_id, node_id)):
		for lang in ModuleDoc.LANGS:
			if doc.text(key, lang) != "":
				edit.set_text(doc, key, lang, "")
	options.remove_at(index)
	edit.set_value(doc, KIND, dialog_id, ["nodes", node_id, "options"], options)
	return edit


## Заменяет ответ [param index] целиком (условия, проверка, переходы, действия).
static func set_option(
	doc: ModuleDoc, dialog_id: String, node_id: String, index: int, option: Dictionary
) -> DocEdit:
	var options := options_of(doc, dialog_id, node_id)
	var edit := DocEdit.new("edit option")
	if index >= 0 and index < options.size():
		options[index] = option.duplicate(true)
		edit.set_value(doc, KIND, dialog_id, ["nodes", node_id, "options"], options)
	return edit


## Куда ведёт ответ: [param field] — next или fail, "" — заканчивает разговор.
static func link(
	doc: ModuleDoc, dialog_id: String, node_id: String, index: int, field: String, target: String
) -> DocEdit:
	var options := options_of(doc, dialog_id, node_id)
	if index < 0 or index >= options.size():
		return DocEdit.new()
	var current: Dictionary = options[index]
	var o := current.duplicate(true)
	if target == "":
		o.erase(field)
	else:
		o[field] = target
	return set_option(doc, dialog_id, node_id, index, o)


## Ключ строки ответа, которого ещё нет в реплике.
static func free_option_key(doc: ModuleDoc, dialog_id: String, node_id: String) -> String:
	var used: Dictionary[String, bool] = {}
	for raw: Variant in options_of(doc, dialog_id, node_id):
		var o: Dictionary = raw
		used[JsonRead.get_str(o, "text")] = true
	var n := 1
	while true:
		var key := "%s_O%d" % [node_key(dialog_id, node_id), n]
		if not used.has(key) and doc.text(key, "ru") == "":
			return key
		n += 1
	return ""


static func options_of(doc: ModuleDoc, dialog_id: String, node_id: String) -> Array:
	var value: Variant = doc.get_value(KIND, dialog_id, ["nodes", node_id, "options"])
	if not value is Array:
		return []
	var a: Array = value
	return a.duplicate(true)


## Положение реплики в графе (метаданные редактора).
static func move_node(doc: ModuleDoc, dialog_id: String, node_id: String, pos: Vector2i) -> DocEdit:
	var edit := DocEdit.new("move node")
	edit.set_value(doc, KIND, dialog_id, [EDITOR_KEY, "pos", node_id], [pos.x, pos.y])
	return edit


static func node_pos(doc: ModuleDoc, dialog_id: String, node_id: String) -> Variant:
	var value: Variant = doc.get_value(KIND, dialog_id, [EDITOR_KEY, "pos", node_id])
	if value is Array:
		var a: Array = value
		if a.size() == 2:
			return JsonRead.to_vec2i(a)
	return null


static func _nodes(doc: ModuleDoc, dialog_id: String) -> Dictionary:
	var value: Variant = doc.get_value(KIND, dialog_id, ["nodes"])
	return value if value is Dictionary else {}


static func _node_keys(node: Dictionary) -> Array[String]:
	var keys: Array[String] = [JsonRead.get_str(node, "text")]
	for raw: Variant in JsonRead.get_array(node, "options"):
		if raw is Dictionary:
			var o: Dictionary = raw
			keys.append(JsonRead.get_str(o, "text"))
	return keys


static func _keys_of(dialog: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	var nodes := JsonRead.get_dict(dialog, "nodes")
	for id: String in _sorted(nodes.keys()):
		var node: Dictionary = nodes[id]
		keys.append_array(_node_keys(node))
	return keys


static func _sorted(values: Array) -> Array[String]:
	var result: Array[String] = []
	result.assign(values)
	result.sort()
	return result
