class_name MapPanel
extends VBoxContainer
## Вкладка «Карта» (ADR-0041): инструменты (выбор, клетки, высота, объект, выход,
## сундук, точка появления, бой), карта сверху и свойства выбранного. Правки — сигналом
## [signal edited]; id для новых выходов и прочего спрашивает экран ([member ask_id]).

signal edited(edit: DocEdit)
signal preview_requested

const TOOL_SELECT := "select"
const TOOL_TILE := "tile"
const TOOL_HEIGHT := "height"
const TOOL_OBJECT := "object"
const TOOL_EXIT := "exit"
const TOOL_CHEST := "chest"
const TOOL_SPAWN := "spawn"
const TOOL_ENCOUNTER := "encounter"
const TOOL_EVENT := "event"
const EVENT_ZONE := 4
const TOOLS: Array[String] = [
	TOOL_SELECT,
	TOOL_TILE,
	TOOL_HEIGHT,
	TOOL_OBJECT,
	TOOL_EXIT,
	TOOL_CHEST,
	TOOL_SPAWN,
	TOOL_ENCOUNTER,
	TOOL_EVENT,
]
const TILES: Array[String] = [".", ",", "#", "T", "=", "+"]
const ROTATIONS: Array[int] = [0, 90, 180, 270]
const ENCOUNTER_ZONE := 6
const ENCOUNTER_BATTLE := 14

## (заголовок, подсказка, обработчик(id, текст), занят(id)) — окно ввода id у экрана.
var ask_id: Callable

var _doc: ModuleDoc
var _area := ""
var _content: ModuleContent
var _text_of: Callable
var _catalog: EditorCatalog
var _editable := true
var _tool := TOOL_SELECT
var _tool_buttons: Dictionary[String, Button] = {}
var _tile := OptionButton.new()
var _level := SpinBox.new()
var _brush := SpinBox.new()
var _prop := OptionButton.new()
var _prop_w := SpinBox.new()
var _prop_d := SpinBox.new()
var _rotation := OptionButton.new()
var _canvas := MapCanvas.new()
var _inspector := MapInspector.new()


func _init() -> void:
	add_theme_constant_override("separation", 6)
	add_child(_toolbar())
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	add_child(split)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_canvas)
	_inspector.custom_minimum_size = Vector2(380, 0)
	split.add_child(_inspector)
	_canvas.stroke_finished.connect(_on_stroke)
	_canvas.cell_clicked.connect(_on_click)
	_canvas.entity_picked.connect(func(_k: String, _i: int) -> void: _show_inspector())
	_canvas.entity_dragged.connect(_on_drag)
	_inspector.edited.connect(func(edit: DocEdit) -> void: edited.emit(edit))
	_inspector.select_requested.connect(_select_entity)


func show_area(
	doc: ModuleDoc,
	area_id: String,
	content: ModuleContent,
	text_of: Callable,
	catalog: EditorCatalog,
	editable: bool
) -> void:
	var first := area_id != _area
	_doc = doc
	_area = area_id
	_content = content
	_text_of = text_of
	_catalog = catalog
	_editable = editable
	_fill_props()
	_canvas.set_area(doc.entry(ModuleDoc.KIND_AREA, area_id))
	if first:
		_canvas.selected_kind = ""
		_canvas.selected_index = -1
		_canvas.fit_view.call_deferred()
	_show_inspector()
	for t: String in _tool_buttons:
		_tool_buttons[t].disabled = not editable and t != TOOL_SELECT


func _select_entity(kind: String, index: int) -> void:
	_canvas.selected_kind = kind
	_canvas.selected_index = index
	_canvas.queue_redraw()
	_show_inspector()


func _show_inspector() -> void:
	_inspector.show_selection(
		_doc,
		_area,
		_content,
		_text_of,
		_catalog,
		_editable,
		_canvas.selected_kind,
		_canvas.selected_index
	)


# --- Инструменты --------------------------------------------------------------------


func _toolbar() -> HFlowContainer:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 4)
	for t in TOOLS:
		var b := Button.new()
		b.text = tr("UI_MAP_TOOL_" + t.to_upper())
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = t == _tool
		b.pressed.connect(_set_tool.bind(t))
		_tool_buttons[t] = b
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	for t in TILES:
		_tile.add_item(tr("UI_MAP_TILE_" + _tile_name(t)))
	bar.add_child(_tile)
	_level.min_value = 0
	_level.max_value = AreaOps.MAX_LEVEL
	_level.prefix = tr("UI_MAP_LEVEL")
	bar.add_child(_level)
	_brush.min_value = 1
	_brush.max_value = 15
	_brush.prefix = tr("UI_MAP_BRUSH")
	_brush.value_changed.connect(func(v: float) -> void: _canvas.brush_size = int(v))
	bar.add_child(_brush)
	bar.add_child(VSeparator.new())
	bar.add_child(_prop)
	for s: SpinBox in [_prop_w, _prop_d]:
		s.min_value = 1
		s.max_value = 16
		bar.add_child(s)
	_prop_w.prefix = "↔"
	_prop_d.prefix = "↕"
	for r in ROTATIONS:
		_rotation.add_item("%d°" % r)
	bar.add_child(_rotation)
	bar.add_child(VSeparator.new())
	bar.add_child(_button("UI_MAP_FIT", func() -> void: _canvas.fit_view()))
	bar.add_child(_button("UI_MAP_PREVIEW", func() -> void: preview_requested.emit()))
	return bar


func _set_tool(tool: String) -> void:
	_tool = tool
	for t: String in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	_canvas.brush_mode = tool == TOOL_TILE or tool == TOOL_HEIGHT


func _fill_props() -> void:
	var keep := _prop.get_item_text(_prop.selected) if _prop.selected >= 0 else ""
	_prop.clear()
	for id in prop_ids(_doc, _content):
		_prop.add_item(id)
		if id == keep:
			_prop.select(_prop.item_count - 1)


## Модели всех модулей и свои (ещё не сохранённые) — по id.
static func prop_ids(doc: ModuleDoc, content: ModuleContent) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(content.props.keys())
	for id in AssetOps.prop_ids(doc):
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	return ids


static func _tile_name(t: String) -> String:
	match t:
		".":
			return "GROUND"
		",":
			return "ROAD"
		"#":
			return "BUILDING"
		"T":
			return "TREE"
		"=":
			return "FENCE"
	return "GRAVE"


# --- Действия мышью -----------------------------------------------------------------


func _on_stroke(cells: Array[Vector2i]) -> void:
	if not _editable:
		return
	if _tool == TOOL_TILE:
		edited.emit(AreaOps.paint(_doc, _area, cells, TILES[maxi(_tile.selected, 0)]))
	elif _tool == TOOL_HEIGHT:
		edited.emit(AreaOps.paint_height(_doc, _area, cells, int(_level.value)))


## Клик по клетке из 3D-предпросмотра — как по карте сверху.
func click_cell(cell: Vector2i) -> void:
	_on_click(cell)


func _on_click(cell: Vector2i) -> void:
	if not _editable:
		_show_inspector()
		return
	match _tool:
		TOOL_OBJECT:
			if _prop.selected >= 0:
				var size := Vector2i(int(_prop_w.value), int(_prop_d.value))
				var rot := ROTATIONS[maxi(_rotation.selected, 0)]
				var prop := _prop.get_item_text(_prop.selected)
				_select_new(MapCanvas.KIND_OBJECT)
				edited.emit(AreaOps.add_object(_doc, _area, prop, cell, size, rot))
		TOOL_EXIT:
			_ask_and_add(MapCanvas.KIND_EXIT, "UI_MAP_NEW_EXIT", cell)
		TOOL_CHEST:
			_ask_and_add(MapCanvas.KIND_CHEST, "UI_MAP_NEW_CHEST", cell)
		TOOL_SPAWN:
			_ask_and_add(MapCanvas.KIND_SPAWN, "UI_MAP_NEW_SPAWN", cell)
		TOOL_ENCOUNTER:
			_ask_and_add(MapCanvas.KIND_ENCOUNTER, "UI_MAP_NEW_ENCOUNTER", cell)
		TOOL_EVENT:
			_ask_and_add(MapCanvas.KIND_EVENT, "UI_MAP_NEW_EVENT", cell)
		_:
			_show_inspector()


func _ask_and_add(kind: String, title_key: String, cell: Vector2i) -> void:
	var add := func(id: String, text: String) -> void:
		var name := text if text != "" else id
		match kind:
			MapCanvas.KIND_EXIT:
				var to := _area
				edited.emit(AreaOps.add_exit(_doc, _area, id, name, cell, to, "start"))
			MapCanvas.KIND_CHEST:
				edited.emit(AreaOps.add_chest(_doc, _area, id, name, cell, "chest"))
			MapCanvas.KIND_SPAWN:
				edited.emit(AreaOps.set_spawn(_doc, _area, id, cell))
			MapCanvas.KIND_ENCOUNTER:
				var half := ENCOUNTER_ZONE / 2
				var zone := Rect2i(
					cell - Vector2i(half, half), Vector2i(ENCOUNTER_ZONE, ENCOUNTER_ZONE)
				)
				var b := ENCOUNTER_BATTLE / 2
				var battle := Rect2i(
					cell - Vector2i(b, b), Vector2i(ENCOUNTER_BATTLE, ENCOUNTER_BATTLE)
				)
				edited.emit(AreaOps.add_encounter(_doc, _area, id, _clip(zone), _clip(battle)))
			MapCanvas.KIND_EVENT:
				var h := EVENT_ZONE / 2
				var r := Rect2i(cell - Vector2i(h, h), Vector2i(EVENT_ZONE, EVENT_ZONE))
				edited.emit(AreaOps.add_event(_doc, _area, id, _clip(r)))
		_select_new(kind)
	var taken := func(id: String) -> bool: return _id_taken(kind, id)
	var nameless: Array[String] = [
		MapCanvas.KIND_SPAWN, MapCanvas.KIND_ENCOUNTER, MapCanvas.KIND_EVENT
	]
	var hint := "" if nameless.has(kind) else tr("UI_ED_NAME_RU")
	ask_id.call(tr(title_key), hint, add, taken)


## Новая сущность — последняя в списке (точки — по имени, выбор после правки).
func _select_new(kind: String) -> void:
	_canvas.selected_kind = kind
	if kind == MapCanvas.KIND_SPAWN:
		_canvas.selected_index = -1
	else:
		_canvas.selected_index = AreaOps.list_of(_doc, _area, kind).size()


func _id_taken(kind: String, id: String) -> bool:
	if kind == MapCanvas.KIND_SPAWN:
		return AreaOps.dict_of(_doc, _area, "spawns").has(id)
	for raw: Variant in AreaOps.list_of(_doc, _area, kind):
		var e: Dictionary = raw
		if JsonRead.get_str(e, "id") == id:
			return true
	return false


func _clip(r: Rect2i) -> Rect2i:
	var size := AreaOps.size_of(_doc, _area)
	return r.intersection(Rect2i(Vector2i.ZERO, size))


## Перетаскивание: клетка сущности (у боя — всё вместе: зона, участок, противники).
func _on_drag(kind: String, index: int, to: Vector2i) -> void:
	if not _editable:
		return
	if kind == MapCanvas.KIND_SPAWN:
		var spawns := AreaOps.dict_of(_doc, _area, "spawns")
		var names: Array[String] = []
		names.assign(spawns.keys())
		names.sort()
		spawns[names[index]] = [to.x, to.y]
		edited.emit(AreaOps.set_field(_doc, _area, "spawns", spawns))
		return
	var list := AreaOps.list_of(_doc, _area, kind)
	var e: Dictionary = list[index]
	if kind == MapCanvas.KIND_EVENT:
		var ezone := Encounter.rect_of(JsonRead.get_array(e, "zone"))
		e["zone"] = _moved_rect(JsonRead.get_array(e, "zone"), to - ezone.position)
	elif kind == MapCanvas.KIND_ENCOUNTER:
		var zone := Encounter.rect_of(JsonRead.get_array(e, "zone"))
		var shift := to - zone.position
		e["zone"] = _moved_rect(JsonRead.get_array(e, "zone"), shift)
		e["battle"] = _moved_rect(JsonRead.get_array(e, "battle"), shift)
		for raw: Variant in JsonRead.get_array(e, "combatants"):
			var foe: Dictionary = raw
			var at := JsonRead.to_vec2i(foe.get("at", [0, 0])) + shift
			foe["at"] = [at.x, at.y]
	else:
		e["at"] = [to.x, to.y]
	edited.emit(AreaOps.set_field(_doc, _area, kind, list))


static func _moved_rect(values: Array, shift: Vector2i) -> Array:
	var r := Encounter.rect_of(values)
	return [r.position.x + shift.x, r.position.y + shift.y, r.size.x, r.size.y]


func _button(key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b
