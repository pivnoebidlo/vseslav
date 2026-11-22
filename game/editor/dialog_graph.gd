class_name DialogGraph
extends GraphEdit
## Граф диалога (ADR-0039): реплика — узел, её ответы — выходы справа, вход — слева.
## Протянуть ответ к реплике — связать; к пустому месту — новая реплика; Delete —
## удалить реплику. Положения узлов хранятся в метаданных диалога.

signal node_selected_id(node_id: String)
signal link_requested(node_id: String, option: int, field: String, target: String)
signal new_node_requested(from_node: String, option: int, field: String, at: Vector2)
signal node_moved(node_id: String, pos: Vector2i)
signal delete_requested(node_id: String)

const COLUMN := 330
const ROW := 190
const PREVIEW_CHARS := 90
const START_COLOR := Color(1.0, 0.85, 0.35)
const OPTION_COLOR := Color(0.55, 0.75, 1.0)
const FAIL_COLOR := Color(0.95, 0.45, 0.4)

## Имя узла GraphEdit → id реплики (id может содержать точку, имя ноды — нет).
var _ids: Dictionary[String, String] = {}
var _names: Dictionary[String, String] = {}
## Имя узла → список выходов: [индекс ответа, поле next|fail].
var _ports: Dictionary[String, Array] = {}


func _init() -> void:
	right_disconnects = true
	show_zoom_label = true
	minimap_enabled = false
	connection_request.connect(_on_connect)
	disconnection_request.connect(_on_disconnect)
	connection_to_empty.connect(_on_to_empty)
	node_selected.connect(_on_selected)
	delete_nodes_request.connect(_on_delete)
	end_node_move.connect(_on_moved)


## Перестраивает граф. [param text_of] — (ключ) → текст для превью.
func build(doc: ModuleDoc, dialog_id: String, text_of: Callable, selected: String) -> void:
	clear_connections()
	for child in get_children():
		if child is GraphNode:
			remove_child(child)
			child.queue_free()
	_ids.clear()
	_names.clear()
	_ports.clear()
	var data := doc.entry(ModuleDoc.KIND_DIALOG, dialog_id)
	var nodes := JsonRead.get_dict(data, "nodes")
	var ids: Array[String] = []
	ids.assign(nodes.keys())
	ids.sort()
	var layout := _auto_layout(data, ids)
	var starts := _start_nodes(data)
	for i in ids.size():
		var id := ids[i]
		var name := "n%d" % i
		_ids[name] = id
		_names[id] = name
	for id in ids:
		var node: Dictionary = nodes[id]
		var g := _graph_node(id, node, text_of, starts.has(id))
		var pos: Variant = DialogOps.node_pos(doc, dialog_id, id)
		var at: Vector2i = pos if pos is Vector2i else layout.get(id, Vector2i.ZERO)
		g.position_offset = Vector2(at)
		g.selected = id == selected
		add_child(g)
	for id in ids:
		var ports: Array = _ports[_names[id]]
		var owner_node: Dictionary = nodes[id]
		var options := JsonRead.get_array(owner_node, "options")
		for p in ports.size():
			var port: Array = ports[p]
			var index: int = port[0]
			var field: String = port[1]
			var o: Dictionary = options[index]
			var target := JsonRead.get_str(o, field)
			if _names.has(target):
				connect_node(_names[id], p, _names[target], 0)


func _graph_node(id: String, node: Dictionary, text_of: Callable, is_start: bool) -> GraphNode:
	var g := GraphNode.new()
	g.name = _names[id]
	g.title = ("★ " if is_start else "") + id
	g.custom_minimum_size = Vector2(260, 0)
	var text := Label.new()
	text.text = _preview(str(text_of.call(JsonRead.get_str(node, "text"))))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(240, 0)
	if is_start:
		text.add_theme_color_override("font_color", START_COLOR)
	g.add_child(text)
	g.set_slot(0, true, 0, Color.WHITE, false, 0, Color.WHITE)
	var ports: Array = []
	var options := JsonRead.get_array(node, "options")
	for i in options.size():
		var o: Dictionary = options[i]
		var line := Label.new()
		var marks := ""
		if not JsonRead.get_array(o, "if").is_empty():
			marks += "❓"
		if o.has("check"):
			var check := JsonRead.get_dict(o, "check")
			marks += (
				"🎲%s %d "
				% [JsonRead.get_str(check, "ability").to_upper(), JsonRead.get_int(check, "dc")]
			)
		line.text = "→ %s%s" % [marks, _preview(str(text_of.call(JsonRead.get_str(o, "text"))))]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_theme_color_override("font_color", OPTION_COLOR)
		line.add_theme_font_size_override("font_size", 13)
		g.add_child(line)
		g.set_slot(g.get_child_count() - 1, false, 0, Color.WHITE, true, 0, OPTION_COLOR)
		ports.append([i, "next"])
		if o.has("check"):
			var fail := Label.new()
			fail.text = tr("UI_ED_ON_FAIL")
			fail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			fail.add_theme_color_override("font_color", FAIL_COLOR)
			fail.add_theme_font_size_override("font_size", 12)
			g.add_child(fail)
			g.set_slot(g.get_child_count() - 1, false, 0, Color.WHITE, true, 0, FAIL_COLOR)
			ports.append([i, "fail"])
	_ports[g.name] = ports
	return g


## Раскладка без сохранённых положений: по глубине от начала, остальные — справа.
func _auto_layout(data: Dictionary, ids: Array[String]) -> Dictionary:
	var depth: Dictionary[String, int] = {}
	var queue: Array[String] = []
	for s in _start_nodes(data):
		if not depth.has(s):
			depth[s] = 0
			queue.append(s)
	var nodes := JsonRead.get_dict(data, "nodes")
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if not nodes.has(id):
			continue
		var from: Dictionary = nodes[id]
		for raw: Variant in JsonRead.get_array(from, "options"):
			var o: Dictionary = raw
			for field: String in ["next", "fail"]:
				var t := JsonRead.get_str(o, field)
				if t != "" and not depth.has(t):
					depth[t] = depth[id] + 1
					queue.append(t)
	var max_depth := 0
	for id in ids:
		var d: int = depth.get(id, 0)
		max_depth = maxi(max_depth, d)
	var rows: Dictionary[int, int] = {}
	var result := {}
	for id in ids:
		var column: int = depth.get(id, max_depth + 1)
		var row: int = rows.get(column, 0)
		rows[column] = row + 1
		result[id] = Vector2i(40 + column * COLUMN, 40 + row * ROW)
	return result


static func _start_nodes(data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var start: Variant = data.get("start", "")
	if start is String:
		result.append(start)
	elif start is Array:
		var variants: Array = start
		for raw: Variant in variants:
			if raw is Dictionary:
				var v: Dictionary = raw
				result.append(JsonRead.get_str(v, "node"))
	return result


static func _preview(text: String) -> String:
	var one := text.replace("\n", " ")
	return one if one.length() <= PREVIEW_CHARS else one.left(PREVIEW_CHARS) + "…"


func _port(from_name: String, from_port: int) -> Array:
	var ports: Array = _ports.get(from_name, [])
	return ports[from_port] if from_port < ports.size() else []


func _on_connect(from_node: StringName, from_port: int, to_node: StringName, _to_port: int) -> void:
	var port := _port(from_node, from_port)
	if port.is_empty() or not _ids.has(to_node):
		return
	link_requested.emit(_ids[from_node], port[0], port[1], _ids[to_node])


func _on_disconnect(from_node: StringName, from_port: int, _to: StringName, _to_port: int) -> void:
	var port := _port(from_node, from_port)
	if not port.is_empty():
		link_requested.emit(_ids[from_node], port[0], port[1], "")


func _on_to_empty(from_node: StringName, from_port: int, release: Vector2) -> void:
	var port := _port(from_node, from_port)
	if port.is_empty():
		return
	var at := (release + scroll_offset) / zoom
	new_node_requested.emit(_ids[from_node], port[0], port[1], at)


func _on_selected(node: Node) -> void:
	if _ids.has(node.name):
		node_selected_id.emit(_ids[node.name])


func _on_delete(nodes: Array[StringName]) -> void:
	for n in nodes:
		if _ids.has(n):
			delete_requested.emit(_ids[n])


func _on_moved() -> void:
	for child in get_children():
		var g := child as GraphNode
		if g != null and g.selected and _ids.has(g.name):
			node_moved.emit(_ids[g.name], Vector2i(g.position_offset))
