class_name MapCanvas
extends Control
## Карта области в редакторе, вид сверху (ADR-0041): клетки — текстура «пиксель на
## клетку» (256 × 256 рисуется мгновенно), поверх — объекты, жители, выходы, сундуки,
## точки появления, зоны боёв. Колесо — масштаб, правая или средняя кнопка — сдвиг.
## Кисть копит клетки мазка и отдаёт их одним сигналом (одна отмена на мазок).

signal stroke_finished(cells: Array[Vector2i])
signal cell_clicked(cell: Vector2i)
signal entity_picked(kind: String, index: int)
signal entity_dragged(kind: String, index: int, to: Vector2i)

const KIND_OBJECT := "objects"
const KIND_EXIT := "exits"
const KIND_CHEST := "containers"
const KIND_SPAWN := "spawns"
const KIND_NPC := "npcs"
const KIND_ENCOUNTER := "encounters"
const MIN_ZOOM := 3.0
const MAX_ZOOM := 40.0
const GRID_FROM_ZOOM := 10.0
const TILE_COLORS: Dictionary[String, Color] = {
	".": Color(0.36, 0.46, 0.27),
	",": Color(0.58, 0.47, 0.32),
	"#": Color(0.48, 0.3, 0.2),
	"T": Color(0.12, 0.3, 0.14),
	"=": Color(0.68, 0.56, 0.32),
	"+": Color(0.62, 0.62, 0.6),
}
const SELECT_COLOR := Color(1.0, 0.85, 0.35)

## Режим мыши: true — кисть (мазок), false — выбор и перетаскивание.
var brush_mode := false
var brush_size := 1
var zoom := 8.0
var offset := Vector2(20, 20)
var selected_kind := ""
var selected_index := -1

var _data: Dictionary = {}
var _size := Vector2i.ZERO
var _texture: ImageTexture
var _stroke: Dictionary[Vector2i, bool] = {}
var _painting := false
var _panning := false
var _drag_kind := ""
var _drag_index := -1
var _hover := Vector2i(-1, -1)


func _init() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


## Новые данные области (словарь из файла); карта перерисовывается.
func set_area(data: Dictionary) -> void:
	_data = data
	var rows := JsonRead.get_str_array(data, "map")
	var heights := JsonRead.get_str_array(data, "heights")
	_size = Vector2i(rows[0].length() if not rows.is_empty() else 0, rows.size())
	if _size.x == 0:
		_texture = null
		queue_redraw()
		return
	var img := Image.create_empty(_size.x, _size.y, false, Image.FORMAT_RGB8)
	for z in _size.y:
		for x in _size.x:
			var color: Color = TILE_COLORS.get(rows[z][x], Color.MAGENTA)
			if z < heights.size() and x < heights[z].length():
				color = color.lightened(heights[z][x].to_int() * 0.09)
			img.set_pixel(x, z, color)
	_texture = ImageTexture.create_from_image(img)
	queue_redraw()


## Показать всю карту в окне.
func fit_view() -> void:
	if _size.x == 0:
		return
	zoom = clampf(minf(size.x / _size.x, size.y / _size.y) * 0.95, MIN_ZOOM, MAX_ZOOM)
	offset = (size - Vector2(_size) * zoom) / 2.0
	queue_redraw()


func cell_at(pos: Vector2) -> Vector2i:
	var c := (pos - offset) / zoom
	return Vector2i(floori(c.x), floori(c.y))


func _cell_rect(c: Vector2i, cells: Vector2i = Vector2i.ONE) -> Rect2:
	return Rect2(offset + Vector2(c) * zoom, Vector2(cells) * zoom)


# --- Ввод ---------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_on_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_motion(motion)


func _on_button(b: InputEventMouseButton) -> void:
	if b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if b.pressed:
			var before := (b.position - offset) / zoom
			var factor := 1.15 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
			offset = b.position - before * zoom
			queue_redraw()
		accept_event()
		return
	if b.button_index == MOUSE_BUTTON_RIGHT or b.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = b.pressed
		accept_event()
		return
	if b.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := cell_at(b.position)
	if b.pressed:
		grab_focus()
		if brush_mode:
			_painting = true
			_stroke.clear()
			_add_stroke(cell)
		else:
			var hit := _entity_at(cell)
			if hit.is_empty():
				selected_kind = ""
				selected_index = -1
				cell_clicked.emit(cell)
			else:
				selected_kind = hit[0]
				selected_index = hit[1]
				_drag_kind = selected_kind
				_drag_index = selected_index
				entity_picked.emit(selected_kind, selected_index)
	else:
		if _painting:
			_painting = false
			var cells: Array[Vector2i] = []
			cells.assign(_stroke.keys())
			_stroke.clear()
			if not cells.is_empty():
				stroke_finished.emit(cells)
		elif _drag_kind != "" and cell != _entity_cell(_drag_kind, _drag_index):
			entity_dragged.emit(_drag_kind, _drag_index, cell)
		_drag_kind = ""
	queue_redraw()
	accept_event()


func _on_motion(m: InputEventMouseMotion) -> void:
	if _panning:
		offset += m.relative
		queue_redraw()
		return
	var cell := cell_at(m.position)
	if cell != _hover:
		_hover = cell
		if _painting:
			_add_stroke(cell)
		queue_redraw()


func _add_stroke(center: Vector2i) -> void:
	for c in AreaOps.brush(center, brush_size):
		if c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y:
			_stroke[c] = true


# --- Сущности на карте --------------------------------------------------------------


## [вид, индекс] того, что стоит в клетке; пусто — ничего. Сверху — мелкое.
func _entity_at(cell: Vector2i) -> Array:
	for kind: String in [KIND_NPC, KIND_CHEST, KIND_EXIT, KIND_OBJECT]:
		var list := JsonRead.get_array(_data, kind)
		for i in list.size():
			var e: Dictionary = list[i]
			if _footprint(kind, e).has_point(cell):
				return [kind, i]
	var spawns := JsonRead.get_dict(_data, KIND_SPAWN)
	var names: Array[String] = []
	names.assign(spawns.keys())
	names.sort()
	for i in names.size():
		if JsonRead.to_vec2i(spawns[names[i]]) == cell:
			return [KIND_SPAWN, i]
	var encounters := JsonRead.get_array(_data, KIND_ENCOUNTER)
	for i in encounters.size():
		var e: Dictionary = encounters[i]
		if Encounter.rect_of(JsonRead.get_array(e, "zone")).has_point(cell):
			return [KIND_ENCOUNTER, i]
	return []


func _entity_cell(kind: String, index: int) -> Vector2i:
	if kind == KIND_SPAWN:
		var spawns := JsonRead.get_dict(_data, KIND_SPAWN)
		var names: Array[String] = []
		names.assign(spawns.keys())
		names.sort()
		return JsonRead.to_vec2i(spawns[names[index]]) if index < names.size() else Vector2i(-1, -1)
	var list := JsonRead.get_array(_data, kind)
	if index < 0 or index >= list.size():
		return Vector2i(-1, -1)
	var e: Dictionary = list[index]
	if kind == KIND_ENCOUNTER:
		return Encounter.rect_of(JsonRead.get_array(e, "zone")).position
	return JsonRead.to_vec2i(e.get("at", [0, 0]))


static func _footprint(kind: String, e: Dictionary) -> Rect2i:
	var at := JsonRead.to_vec2i(e.get("at", [0, 0]))
	var size := Vector2i.ONE
	if kind == KIND_OBJECT and e.has("size"):
		size = JsonRead.to_vec2i(e["size"])
	return Rect2i(at, size)


# --- Рисование ----------------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07))
	if _texture == null:
		return
	draw_texture_rect(_texture, Rect2(offset, Vector2(_size) * zoom), false)
	if zoom >= GRID_FROM_ZOOM:
		_draw_grid()
	_draw_encounters()
	_draw_list(KIND_OBJECT, Color(0.85, 0.85, 0.95, 0.9))
	_draw_list(KIND_EXIT, Color(1.0, 0.8, 0.3))
	_draw_list(KIND_CHEST, Color(0.95, 0.6, 0.25))
	_draw_list(KIND_NPC, Color(0.5, 0.8, 1.0))
	_draw_spawns()
	for c: Vector2i in _stroke:
		draw_rect(_cell_rect(c), Color(1, 1, 1, 0.35))
	if _hover.x >= 0 and _hover.x < _size.x and _hover.y >= 0 and _hover.y < _size.y:
		var n := brush_size if brush_mode else 1
		var from := _hover - Vector2i((n - 1) / 2, (n - 1) / 2)
		draw_rect(_cell_rect(from, Vector2i(n, n)), Color(1, 1, 1, 0.8), false, 1.0)
		var font := get_theme_default_font()
		draw_string(font, Vector2(8, size.y - 8), "%d, %d" % [_hover.x, _hover.y])


func _draw_grid() -> void:
	var color := Color(0, 0, 0, 0.25)
	var from := cell_at(Vector2.ZERO).max(Vector2i.ZERO)
	var to := (cell_at(size) + Vector2i.ONE).min(_size)
	for x in range(from.x, to.x + 1):
		var px := offset.x + x * zoom
		draw_line(Vector2(px, offset.y + from.y * zoom), Vector2(px, offset.y + to.y * zoom), color)
	for z in range(from.y, to.y + 1):
		var pz := offset.y + z * zoom
		draw_line(Vector2(offset.x + from.x * zoom, pz), Vector2(offset.x + to.x * zoom, pz), color)


func _draw_list(kind: String, color: Color) -> void:
	var list := JsonRead.get_array(_data, kind)
	for i in list.size():
		var e: Dictionary = list[i]
		var rect := _cell_rect(_footprint(kind, e).position, _footprint(kind, e).size)
		var picked := kind == selected_kind and i == selected_index
		if kind == KIND_NPC or kind == KIND_CHEST:
			draw_circle(rect.get_center(), maxf(zoom * 0.4, 2.0), SELECT_COLOR if picked else color)
		else:
			draw_rect(rect.grow(-1.0), Color(color, 0.25))
			draw_rect(
				rect.grow(-1.0), SELECT_COLOR if picked else color, false, 2.0 if picked else 1.0
			)
		if zoom >= GRID_FROM_ZOOM and kind != KIND_OBJECT:
			var label := JsonRead.get_str(e, "id")
			draw_string(
				get_theme_default_font(), rect.position + Vector2(zoom, -2), label, 0, -1, 11
			)


func _draw_spawns() -> void:
	var spawns := JsonRead.get_dict(_data, KIND_SPAWN)
	var names: Array[String] = []
	names.assign(spawns.keys())
	names.sort()
	for i in names.size():
		var rect := _cell_rect(JsonRead.to_vec2i(spawns[names[i]]))
		var picked := selected_kind == KIND_SPAWN and i == selected_index
		var c := rect.get_center()
		var r := maxf(zoom * 0.45, 3.0)
		var color := SELECT_COLOR if picked else Color(0.4, 1.0, 0.5)
		draw_line(c + Vector2(-r, -r), c + Vector2(r, r), color, 2.0)
		draw_line(c + Vector2(-r, r), c + Vector2(r, -r), color, 2.0)


func _draw_encounters() -> void:
	var list := JsonRead.get_array(_data, KIND_ENCOUNTER)
	for i in list.size():
		var e: Dictionary = list[i]
		var picked := selected_kind == KIND_ENCOUNTER and i == selected_index
		var battle := Encounter.rect_of(JsonRead.get_array(e, "battle"))
		var zone := Encounter.rect_of(JsonRead.get_array(e, "zone"))
		draw_rect(_cell_rect(battle.position, battle.size), Color(0.9, 0.3, 0.3, 0.6), false, 1.0)
		var zone_color := SELECT_COLOR if picked else Color(1.0, 0.35, 0.3)
		draw_rect(_cell_rect(zone.position, zone.size), Color(zone_color, 0.12))
		draw_rect(_cell_rect(zone.position, zone.size), zone_color, false, 2.0)
		for raw: Variant in JsonRead.get_array(e, "combatants"):
			var foe: Dictionary = raw
			var at := JsonRead.to_vec2i(foe.get("at", [0, 0]))
			draw_circle(_cell_rect(at).get_center(), maxf(zoom * 0.35, 2.0), Color(1, 0.25, 0.2))
