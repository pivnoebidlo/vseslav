extends Node3D
## Исследование в реальном времени (ADR-0029, ADR-0030): клик по земле — выбранный герой
## идёт туда, сцепленные спутники следом; клик по жителю — подойти и поговорить.
## Героя выбирают по портрету, по фигуре или Tab; путь под курсором виден всегда,
## сетка клеток включается кнопкой или G. Мир здесь не детерминирован (SPEC §3.1);
## путь ищет Pathfinder ядра по сетке области.

const CELL := BattleGrid.CELL_SIZE_M
const WALK_SPEED := 3.6
const FOLLOW_GAP := 1.3
## Дальше этого спутник догоняет по пути в обход препятствий, а не напрямую.
const CATCH_UP := 2.5 * CELL
const TRAIL_STEP := 0.2
const TRAIL_MAX := 300
const CAMERA_ZOOM := 0.95
## Цель взгляда чуть ниже героя по экрану: внизу открывается окно разговора.
const LOOK_SHIFT := Vector3(0.0, 0.0, 2.2)
const CAMERA_LAG := 6.0


## Герой на карте и его путь.
class Walker:
	extends RefCounted
	var view: UnitView
	var path: Array[Vector3] = []
	var walking := false


## Флаги мира и включённая сетка живут, пока запущена игра (сохранение — позже).
static var flags := WorldFlags.new()
static var grid_on := false

var _content: ModuleContent
var _area: AreaMap
var _figures: FigureCatalog
var _camera := ArenaCamera.new()
var _world := Node3D.new()
var _area_view := AreaView.new()
var _path_preview := PathPreview.new()
var _group := PartyGroup.new()
var _heroes: Dictionary[String, Walker] = {}
var _names: Dictionary[String, String] = {}
var _npcs: Dictionary[String, UnitView] = {}
## След выбранного героя (последняя точка — ближе всего к нему): по нему идут спутники.
var _trail: Array[Vector3] = []
var _look := Vector3.ZERO
var _talk_to := ""
var _hovered := ""
var _dialog := DialogPanel.new()
var _party_bar := PartyBar.new()
var _grid_button := CheckButton.new()
var _title := Label.new()
var _hint := Label.new()


func _ready() -> void:
	_content = ModuleLoader.load_all()
	ModuleLocales.apply(_content.locales)
	_figures = FigureCatalog.from_content(_content, RigProfile.load_all())
	SceneEnv.add_to(self)
	add_child(_world)
	_world.add_child(_camera)
	_camera.current = true
	_world.add_child(_path_preview)
	_setup_ui()
	var start := _content.start()
	_area = _content.area(JsonRead.get_str(start, "area"))
	if _area == null:
		_hint.text = tr("UI_EXPLORE_NO_START")
		for err in _content.errors:
			push_error(err)
		return
	_title.text = tr(_area.title_key)
	_area_view.build(_area)
	_area_view.set_grid_visible(grid_on)
	_world.add_child(_area_view)
	_spawn_npcs()
	var spawn: Vector2i = _area.spawns.get(JsonRead.get_str(start, "spawn"), Vector2i.ZERO)
	_spawn_party(spawn)
	_look = _look_target()
	_camera.focus(_look, CAMERA_ZOOM)


func _process(delta: float) -> void:
	if _heroes.is_empty():
		return
	var followers := _group.followers()
	for id in _group.ids:
		if not followers.has(id):
			_advance(_heroes[id], delta, id == _group.selected)
	for i in followers.size():
		_follow_trail(_heroes[followers[i]], FOLLOW_GAP * (i + 1), delta)
	_look = _look.lerp(_look_target(), minf(1.0, delta * CAMERA_LAG))
	_camera.focus(_look)


# --- Ввод ---------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if _dialog.is_open() or _heroes.is_empty():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		_on_key(key.keycode)
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_camera.handle_input(event)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_hover(motion.position)
	elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_on_click(button.position)


func _on_key(keycode: Key) -> void:
	match keycode:
		KEY_G:
			_set_grid(not _area_view.is_grid_visible())
		KEY_TAB:
			_select(_group.next_id())


func _on_hover(screen_pos: Vector2) -> void:
	var id := _unit_under(screen_pos)
	_set_hovered(id)
	if _npcs.has(id):
		_preview(_area.approach(_leader_cell(), id))
	elif id != "":
		_path_preview.clear()
	else:
		_preview(_area.path(_leader_cell(), _cell_under(screen_pos)))


func _on_click(screen_pos: Vector2) -> void:
	var id := _unit_under(screen_pos)
	if _heroes.has(id):
		_select(id)
	elif _npcs.has(id):
		_go_talk(id)
	else:
		_talk_to = ""
		_walk_leader(_area.path(_leader_cell(), _cell_under(screen_pos)))
	_path_preview.clear()


func _unit_under(screen_pos: Vector2) -> String:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to)
	)
	if hit.is_empty():
		return ""
	var collider: Object = hit["collider"]
	return str(collider.get_meta("unit_id", ""))


## Клетка земли под курсором (пересечение луча с плоскостью y = 0).
func _cell_under(screen_pos: Vector2) -> Vector2i:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector2i(-1, -1)
	var p := origin + dir * (-origin.y / dir.y)
	return _cell_of(p)


func _set_hovered(id: String) -> void:
	if id == _hovered:
		return
	var old := _view_of(_hovered)
	if old != null:
		old.set_hovered(false)
	_hovered = id
	var view := _view_of(id)
	if view != null:
		view.set_hovered(true)


func _view_of(id: String) -> UnitView:
	if _npcs.has(id):
		return _npcs[id]
	if _heroes.has(id):
		return _heroes[id].view
	return null


func _preview(p: PathResult) -> void:
	if not p.found():
		_path_preview.clear()
		return
	var points: Array[Vector3] = [_leader().view.position]
	points.append_array(_points(p))
	_path_preview.show_points(points)


# --- Выбор и группа -------------------------------------------------------------


func _select(id: String) -> void:
	if id == "" or id == _group.selected:
		return
	_leader().view.set_active(false)
	_group.select(id)
	_leader().view.set_active(true)
	_talk_to = ""
	_trail = [_leader().view.position]
	_refresh_bar()


func _toggle_chain(id: String) -> void:
	_group.toggle_chain(id)
	if id == _group.selected:
		_trail = [_leader().view.position]
	_refresh_bar()


func _set_grid(on: bool) -> void:
	grid_on = on
	_area_view.set_grid_visible(on)
	_grid_button.set_pressed_no_signal(on)


func _refresh_bar() -> void:
	_party_bar.refresh(_group, _names)


# --- Ходьба -------------------------------------------------------------------


func _go_talk(npc_id: String) -> void:
	var npc := _area.get_npc(npc_id)
	_talk_to = npc_id
	if AreaMap.is_next_to(_leader_cell(), npc.at):
		_leader().path.clear()
		_arrived()
		return
	var p := _area.approach(_leader_cell(), npc_id)
	if p.found():
		_walk_leader(p)
	else:
		_talk_to = ""


func _walk_leader(p: PathResult) -> void:
	if p.found():
		_leader().path = _points(p)


func _points(p: PathResult) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for cell in p.cells:
		points.append(_cell_pos(Vector2i(cell.x, cell.z)))
	return points


## Шаг по своему пути. [param leading] — выбранный герой: оставляет след и по
## приходе начинает разговор.
func _advance(w: Walker, delta: float, leading: bool) -> void:
	if w.path.is_empty():
		return
	var step := WALK_SPEED * delta
	while step > 0.0 and not w.path.is_empty():
		var to := w.path[0]
		var d := w.view.position.distance_to(to)
		w.view.face(to)
		if d <= step:
			w.view.position = to
			step -= d
			w.path.pop_front()
		else:
			w.view.position += (to - w.view.position) / d * step
			step = 0.0
		if leading:
			_record_trail(w.view.position)
	_set_walking(w, not w.path.is_empty())
	if w.path.is_empty() and leading:
		_arrived()


## Спутник держится на расстоянии [param gap] позади выбранного по его следу; если
## отстал далеко (его только что прицепили), догоняет по пути в обход препятствий.
func _follow_trail(w: Walker, gap: float, delta: float) -> void:
	var target: Variant = _trail_point(gap)
	if target == null:
		_advance(w, delta, false)
		if w.path.is_empty():
			_set_walking(w, false)
		return
	var to: Vector3 = target
	# Догоняет по пути; путь пересчитывается, когда цель ушла от его конца.
	if not w.path.is_empty() and w.path[-1].distance_to(to) < 2.0 * CELL:
		_advance(w, delta, false)
		return
	w.path.clear()
	var d := w.view.position.distance_to(to)
	if d > CATCH_UP:
		var p := _area.path(_cell_of(w.view.position), _cell_of(to))
		if p.found():
			w.path = _points(p)
			_advance(w, delta, false)
			return
	var moving := d > 0.05
	if moving:
		w.view.face(to)
		w.view.position = w.view.position.move_toward(to, WALK_SPEED * 1.15 * delta)
	_set_walking(w, moving)


func _set_walking(w: Walker, on: bool) -> void:
	if on != w.walking:
		w.walking = on
		w.view.walk(on)


func _record_trail(at: Vector3) -> void:
	if _trail.is_empty() or _trail[-1].distance_to(at) >= TRAIL_STEP:
		_trail.append(at)
		if _trail.size() > TRAIL_MAX:
			_trail.pop_front()


## Точка следа на расстоянии [param back] от выбранного; null — след ещё короче
## (выбранный только начал идти, спутник стоит на месте).
func _trail_point(back: float) -> Variant:
	var prev := _leader().view.position
	var left := back
	for i in range(_trail.size() - 1, -1, -1):
		var d := prev.distance_to(_trail[i])
		if d >= left:
			return prev.lerp(_trail[i], left / d)
		left -= d
		prev = _trail[i]
	return null


func _arrived() -> void:
	if _talk_to == "":
		return
	var npc_id := _talk_to
	_talk_to = ""
	var npc := _area.get_npc(npc_id)
	var view := _npcs[npc_id]
	_leader().view.face(view.position)
	view.face(_leader().view.position)
	if npc.dialog == "" or not _content.dialogs.has(npc.dialog):
		return
	_set_hovered("")
	_path_preview.clear()
	var runner := DialogRunner.start(npc.dialog, _content.dialogs[npc.dialog], flags)
	_dialog.open(tr(npc.name_key), runner)


## Камера следит за выбранным, но не уходит далеко за край области.
func _look_target() -> Vector3:
	var p := _leader().view.position + LOOK_SHIFT
	var margin := 4.0 * CELL
	p.x = clampf(p.x, margin, maxf(margin, (_area.width() - 1) * CELL - margin))
	p.z = clampf(p.z, margin, maxf(margin, (_area.depth() - 1) * CELL - margin * 0.5))
	return p


func _leader() -> Walker:
	return _heroes[_group.selected]


func _leader_cell() -> Vector2i:
	return _cell_of(_leader().view.position)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)


# --- Участники ----------------------------------------------------------------


func _spawn_party(at: Vector2i) -> void:
	var party := PartyStore.load_party(_content.rules)
	var ids: Array[String] = []
	ids.assign(party.inventories.keys())
	ids.sort()
	_group = PartyGroup.new(ids)
	for i in ids.size():
		var w := Walker.new()
		_names[ids[i]] = _name_of(ids[i])
		w.view = _add_person(ids[i], "party", ids[i], _names[ids[i]])
		w.view.place(_cell_pos(at) - Vector3(FOLLOW_GAP * i, 0.0, 0.0))
		w.view.face(w.view.position + Vector3.RIGHT)
		_heroes[ids[i]] = w
	for i in range(ids.size() * 8, -1, -1):
		_trail.append(_cell_pos(at) - Vector3(TRAIL_STEP * i, 0.0, 0.0))
	_leader().view.set_active(true)
	_refresh_bar()


func _spawn_npcs() -> void:
	for npc in _area.npcs:
		var view := _add_person(npc.id, "village", npc.look, tr(npc.name_key))
		view.place(_cell_pos(npc.at))
		view.face(view.position + Vector3.BACK)
		_npcs[npc.id] = view


func _add_person(id: String, team: String, look: String, display_name: String) -> UnitView:
	var view := UnitView.new()
	_world.add_child(view)
	var entry := _figures.entry(look)
	view.setup(id, team, entry, _figures.instantiate(entry))
	view.show_as_person(display_name)
	return view


func _name_of(character_id: String) -> String:
	if not _content.rules.characters.has(character_id):
		return character_id
	return tr(JsonRead.get_str(_content.rules.characters[character_id], "name_key"))


# --- Интерфейс ----------------------------------------------------------------


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	column.add_theme_constant_override("separation", 10)
	layer.add_child(column)
	var panel := PanelContainer.new()
	column.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_hint.text = tr("UI_EXPLORE_HINT")
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(360, 0)
	box.add_child(_hint)
	var row := HBoxContainer.new()
	box.add_child(row)
	var menu := Button.new()
	menu.text = tr("UI_MENU")
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file(MainMenu.SCENE))
	row.add_child(menu)
	_grid_button.text = tr("UI_GRID")
	_grid_button.focus_mode = Control.FOCUS_NONE
	_grid_button.set_pressed_no_signal(grid_on)
	_grid_button.toggled.connect(_set_grid)
	row.add_child(_grid_button)
	column.add_child(_party_bar)
	_party_bar.hero_selected.connect(_select)
	_party_bar.chain_toggled.connect(_toggle_chain)
	layer.add_child(_dialog)
