class_name WorldPanel
extends HBoxContainer
## Глобальная карта в редакторе (ADR-0051): схема городов и дорог слева, свойства выбранного
## справа. Режимы: выбор и перетаскивание, новый город по клику, дорога между двумя городами.
## Правки — сигналом [signal edited], как у остальных панелей (отмена и повтор — у экрана).

signal edited(edit: DocEdit)

const MODE_SELECT := "select"
const MODE_CITY := "city"
const MODE_ROAD := "road"
const MODES: Array[String] = [MODE_SELECT, MODE_CITY, MODE_ROAD]
const SCHEME_SIZE := Vector2(560, 420)
const HIT_RADIUS := 14.0
const ROAD_HIT := 8.0
const DEFAULT_DAYS := 2

## (заголовок, подсказка, ok(id, текст), занят(id)) — окно ввода id у экрана.
var ask_id: Callable

var _doc: ModuleDoc
var _content: ModuleContent
var _editable := true
var _mode := MODE_SELECT
var _city := ""
var _road: Array[String] = []
var _road_from := ""
var _drag := ""
var _drag_moved := false
var _scheme := Control.new()
var _mode_buttons: Dictionary[String, Button] = {}
var _inspector := VBoxContainer.new()
var _hint := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var bar := HBoxContainer.new()
	left.add_child(bar)
	var labels: Dictionary[String, String] = {
		MODE_SELECT: "UI_WORLD_MODE_SELECT",
		MODE_CITY: "UI_WORLD_MODE_CITY",
		MODE_ROAD: "UI_WORLD_MODE_ROAD",
	}
	for mode in MODES:
		var b := Button.new()
		b.text = tr(labels[mode])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_mode.bind(mode))
		_mode_buttons[mode] = b
		bar.add_child(b)
	_hint.add_theme_font_size_override("font_size", 12)
	left.add_child(_hint)
	_scheme.custom_minimum_size = SCHEME_SIZE
	_scheme.draw.connect(_draw_scheme)
	_scheme.gui_input.connect(_on_scheme_input)
	left.add_child(_scheme)
	_inspector.custom_minimum_size = Vector2(340, 0)
	_inspector.add_theme_constant_override("separation", 6)
	add_child(_inspector)
	_set_mode(MODE_SELECT)


## Показать карту модуля [param doc]; [param content] — загруженные модули (для названий).
func show_world(doc: ModuleDoc, content: ModuleContent, editable: bool) -> void:
	_doc = doc
	_content = content
	_editable = editable
	if _city != "" and not WorldOps.city_ids(doc).has(_city):
		_city = ""
	if not _road.is_empty() and WorldOps.find_road(doc, _road[0], _road[1]) < 0:
		_road.clear()
	_refresh()


func _set_mode(mode: String) -> void:
	_mode = mode
	_road_from = ""
	for m in _mode_buttons:
		_mode_buttons[m].set_pressed_no_signal(m == mode)
	_refresh()


func _refresh() -> void:
	match _mode:
		MODE_SELECT:
			_hint.text = tr("UI_WORLD_HINT_SELECT")
		MODE_CITY:
			_hint.text = tr("UI_WORLD_HINT_CITY")
		MODE_ROAD:
			_hint.text = (
				tr("UI_WORLD_HINT_ROAD_FROM") if _road_from == "" else tr("UI_WORLD_HINT_ROAD_TO")
			)
	_scheme.queue_redraw()
	_rebuild_inspector()


# --- Схема ---------------------------------------------------------------------------


func _draw_scheme() -> void:
	if _doc == null:
		return
	var font := _scheme.get_theme_default_font()
	for raw: Variant in WorldOps.roads(_doc):
		var r: Dictionary = raw
		var a := _at_of(JsonRead.get_str(r, "from"))
		var b := _at_of(JsonRead.get_str(r, "to"))
		var picked := (
			_road.size() == 2 and _same_road(JsonRead.get_str(r, "from"), JsonRead.get_str(r, "to"))
		)
		var color := UiStyle.ACTIVE if picked else Color(0.7, 0.6, 0.4)
		_scheme.draw_line(a, b, color, 3.0)
		_scheme.draw_string(font, (a + b) / 2.0, str(JsonRead.get_int(r, "days")), 0, -1, 13)
	for id in WorldOps.city_ids(_doc):
		var at := _at_of(id)
		var color := UiStyle.ACTIVE if id == _city or id == _road_from else Color(0.85, 0.85, 0.9)
		_scheme.draw_circle(at, 7.0, color)
		_scheme.draw_string(font, at + Vector2(11, 4), _city_title(id), 0, -1, 14)


func _at_of(id: String) -> Vector2:
	for raw: Variant in WorldOps.cities(_doc):
		var c: Dictionary = raw
		if JsonRead.get_str(c, "id") == id:
			return Vector2(JsonRead.to_vec2i(c.get("at", [0, 0]))) * _scheme.size / 1000.0
	return Vector2.ZERO


func _same_road(a: String, b: String) -> bool:
	return (_road[0] == a and _road[1] == b) or (_road[0] == b and _road[1] == a)


func _city_title(id: String) -> String:
	var title := _doc.text(WorldOps.city_key(id), "ru")
	return title if title != "" else id


## Ближайший город у точки [param pos] в пикселях схемы; "" — нет рядом.
func _city_at(pos: Vector2) -> String:
	var best := ""
	var best_d := HIT_RADIUS
	for id in WorldOps.city_ids(_doc):
		var d := _at_of(id).distance_to(pos)
		if d <= best_d:
			best = id
			best_d = d
	return best


## Дорога у точки [param pos]: [a, b] или пусто.
func _road_at(pos: Vector2) -> Array[String]:
	for raw: Variant in WorldOps.roads(_doc):
		var r: Dictionary = raw
		var a := JsonRead.get_str(r, "from")
		var b := JsonRead.get_str(r, "to")
		var p := _at_of(a)
		var q := _at_of(b)
		var seg := q - p
		var t := clampf((pos - p).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
		if (p + seg * t).distance_to(pos) <= ROAD_HIT:
			var pair: Array[String] = [a, b]
			return pair
	return []


func _scheme_to_cities(pos: Vector2) -> Vector2i:
	return Vector2i(pos * 1000.0 / _scheme.size)


# --- Ввод ----------------------------------------------------------------------------


func _on_scheme_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and _drag != "":
		_drag_moved = true
		_scheme.queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or _doc == null:
		return
	if not button.pressed:
		_release(button.position)
		return
	_press(button.position)


func _press(pos: Vector2) -> void:
	var hit := _city_at(pos)
	match _mode:
		MODE_SELECT:
			_drag = hit if _editable else ""
			_drag_moved = false
			_select_at(pos, hit)
		MODE_CITY:
			if hit == "":
				_ask_new_city(pos)
		MODE_ROAD:
			_pick_for_road(hit)
	_refresh()


func _release(pos: Vector2) -> void:
	if _drag != "" and _drag_moved:
		edited.emit(WorldOps.move_city(_doc, _drag, _scheme_to_cities(pos)))
	_drag = ""
	_drag_moved = false


func _select_at(pos: Vector2, hit: String) -> void:
	if hit != "":
		_city = hit
		_road.clear()
		return
	_city = ""
	var road := _road_at(pos)
	_road.assign(road)


func _pick_for_road(hit: String) -> void:
	if hit == "":
		_road_from = ""
		return
	if _road_from == "":
		_road_from = hit
		return
	if hit != _road_from:
		edited.emit(WorldOps.add_road(_doc, _road_from, hit, DEFAULT_DAYS))
	_road_from = ""


func _ask_new_city(pos: Vector2) -> void:
	var at := _scheme_to_cities(pos)
	var areas := _doc.ids(ModuleDoc.KIND_AREA)
	if areas.is_empty():
		_hint.text = tr("UI_WORLD_NO_AREAS")
		return
	var area := areas[0]
	var spawn := _first_spawn(area)
	var add := func(id: String, text: String) -> void:
		var title := text if text != "" else id
		edited.emit(WorldOps.add_city(_doc, id, title, area, spawn, at))
	var taken := func(id: String) -> bool: return WorldOps.city_ids(_doc).has(id)
	ask_id.call(tr("UI_WORLD_NEW_CITY"), tr("UI_WORLD_NEW_CITY_HINT"), add, taken)


func _first_spawn(area_id: String) -> String:
	var spawns: Array[String] = []
	spawns.assign(AreaOps.dict_of(_doc, area_id, "spawns").keys())
	spawns.sort()
	return spawns[0] if not spawns.is_empty() else "start"


# --- Свойства выбранного -------------------------------------------------------------


func _rebuild_inspector() -> void:
	for child in _inspector.get_children():
		_inspector.remove_child(child)
		child.queue_free()
	if _doc == null:
		return
	if _city != "":
		_city_inspector(_city)
	elif _road.size() == 2:
		_road_inspector(_road[0], _road[1])
	else:
		var help := Label.new()
		help.text = tr("UI_WORLD_NOTHING_SELECTED")
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector.add_child(help)


func _city_inspector(id: String) -> void:
	var c := _city_data(id)
	_inspector.add_child(_title(tr("UI_WORLD_CITY") + " " + id))
	var name_edit := LineEdit.new()
	name_edit.text = _city_title(id)
	name_edit.editable = _editable
	name_edit.text_submitted.connect(
		func(text: String) -> void:
			var edit := DocEdit.new("city name")
			edit.set_text(_doc, WorldOps.city_key(id), "ru", text)
			edited.emit(edit)
	)
	_inspector.add_child(name_edit)
	var area_pick := OptionButton.new()
	area_pick.disabled = not _editable
	var areas := _doc.ids(ModuleDoc.KIND_AREA)
	var current := JsonRead.get_str(c, "area")
	for a in areas:
		area_pick.add_item(a)
		if a == current:
			area_pick.select(area_pick.item_count - 1)
	area_pick.item_selected.connect(
		func(i: int) -> void:
			edited.emit(WorldOps.set_city_place(_doc, id, areas[i], _first_spawn(areas[i])))
	)
	_inspector.add_child(_row(tr("UI_WORLD_AREA"), area_pick))
	var spawn_pick := OptionButton.new()
	spawn_pick.disabled = not _editable
	var spawns: Array[String] = []
	spawns.assign(AreaOps.dict_of(_doc, current, "spawns").keys())
	spawns.sort()
	for s in spawns:
		spawn_pick.add_item(s)
		if s == JsonRead.get_str(c, "spawn"):
			spawn_pick.select(spawn_pick.item_count - 1)
	spawn_pick.item_selected.connect(
		func(i: int) -> void: edited.emit(WorldOps.set_city_place(_doc, id, current, spawns[i]))
	)
	_inspector.add_child(_row(tr("UI_WORLD_SPAWN"), spawn_pick))
	if _editable:
		_inspector.add_child(
			_delete_button(func() -> void: edited.emit(WorldOps.remove_city(_doc, id)))
		)


func _road_inspector(a: String, b: String) -> void:
	var index := WorldOps.find_road(_doc, a, b)
	var r := _road_data(index)
	_inspector.add_child(_title("%s — %s" % [_city_title(a), _city_title(b)]))
	var days := SpinBox.new()
	days.min_value = 1
	days.max_value = WorldOps.MAX_DAYS
	days.value = JsonRead.get_int(r, "days", DEFAULT_DAYS)
	days.editable = _editable
	days.value_changed.connect(
		func(v: float) -> void: edited.emit(WorldOps.set_road_days(_doc, a, b, int(v)))
	)
	_inspector.add_child(_row(tr("UI_WORLD_DAYS"), days))
	if _editable:
		_inspector.add_child(
			_delete_button(func() -> void: edited.emit(WorldOps.remove_road(_doc, a, b)))
		)


func _city_data(id: String) -> Dictionary:
	for raw: Variant in WorldOps.cities(_doc):
		var c: Dictionary = raw
		if JsonRead.get_str(c, "id") == id:
			return c
	return {}


func _road_data(index: int) -> Dictionary:
	if index < 0:
		return {}
	var list := WorldOps.roads(_doc)
	var r: Dictionary = list[index]
	return r


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _delete_button(handler: Callable) -> Button:
	var b := Button.new()
	b.text = tr("UI_ED_DELETE")
	b.pressed.connect(handler)
	return b
