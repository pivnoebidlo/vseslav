extends Node3D
## Исследование в реальном времени (ADR-0029, набросок): партия ходит по области кликом,
## спутники идут следом, клик по жителю — подойти и поговорить. Мир здесь не
## детерминирован (SPEC §3.1); путь ищет Pathfinder ядра по сетке области.

const CELL := BattleGrid.CELL_SIZE_M
const WALK_SPEED := 3.6
const FOLLOW_GAP := 1.3
const TRAIL_STEP := 0.2
const CAMERA_ZOOM := 0.95
## Цель взгляда чуть ниже ведущего по экрану: внизу открывается окно разговора.
const LOOK_SHIFT := Vector3(0.0, 0.0, 2.2)
const CAMERA_LAG := 6.0
const HOUSE_HEIGHT := 2.1
const FENCE_HEIGHT := 0.6

## Флаги мира живут, пока запущена игра (сохранение — позже).
static var flags := WorldFlags.new()

var _content: ModuleContent
var _area: AreaMap
var _figures: FigureCatalog
var _camera := ArenaCamera.new()
var _world := Node3D.new()
var _heroes: Array[UnitView] = []
var _npcs: Dictionary[String, UnitView] = {}
## Оставшиеся точки пути ведущего.
var _path: Array[Vector3] = []
## След ведущего (последняя точка — ближе всего к нему): по нему идут спутники.
var _trail: Array[Vector3] = []
## Куда смотрит камера (плавно догоняет ведущего).
var _look := Vector3.ZERO
## Идёт ли спутник (чтобы не перезапускать анимацию каждый кадр).
var _walking: Array[bool] = []
var _talk_to := ""
var _hovered := ""
var _dialog := DialogPanel.new()
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
	_setup_ui()
	var start := _content.start()
	_area = _content.area(JsonRead.get_str(start, "area"))
	if _area == null:
		_hint.text = tr("UI_EXPLORE_NO_START")
		for err in _content.errors:
			push_error(err)
		return
	_title.text = tr(_area.title_key)
	_build_area()
	_spawn_npcs()
	var spawn: Vector2i = _area.spawns.get(JsonRead.get_str(start, "spawn"), Vector2i.ZERO)
	_spawn_party(spawn)
	_look = _look_target()
	_camera.focus(_look, CAMERA_ZOOM)


func _process(delta: float) -> void:
	if _heroes.is_empty():
		return
	_move_leader(delta)
	_move_companions(delta)
	_look = _look.lerp(_look_target(), minf(1.0, delta * CAMERA_LAG))
	_camera.focus(_look)


# --- Ввод ---------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if _dialog.is_open() or _heroes.is_empty():
		return
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_camera.handle_input(event)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_set_hovered(_npc_under(motion.position))
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var npc := _npc_under(click.position)
		if npc != "":
			_go_talk(npc)
		else:
			_go_to(_cell_under(click.position))


func _npc_under(screen_pos: Vector2) -> String:
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to)
	)
	if hit.is_empty():
		return ""
	var collider: Object = hit["collider"]
	var id := str(collider.get_meta("unit_id", ""))
	return id if _npcs.has(id) else ""


## Клетка земли под курсором (пересечение луча с плоскостью y = 0).
func _cell_under(screen_pos: Vector2) -> Vector2i:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector2i(-1, -1)
	var p := origin + dir * (-origin.y / dir.y)
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))


func _set_hovered(id: String) -> void:
	if id == _hovered:
		return
	if _npcs.has(_hovered):
		_npcs[_hovered].set_hovered(false)
	_hovered = id
	if _npcs.has(id):
		_npcs[id].set_hovered(true)


# --- Ходьба -------------------------------------------------------------------


func _go_to(cell: Vector2i) -> void:
	_talk_to = ""
	_follow(_area.path(_leader_cell(), cell))


func _go_talk(npc_id: String) -> void:
	var npc := _area.get_npc(npc_id)
	if AreaMap.is_next_to(_leader_cell(), npc.at):
		_path.clear()
		_talk_to = npc_id
		_arrived()
		return
	var p := _area.approach(_leader_cell(), npc_id)
	if p.found():
		_talk_to = npc_id
		_follow(p)


func _follow(p: PathResult) -> void:
	if not p.found():
		return
	_path.clear()
	for cell in p.cells:
		_path.append(_cell_pos(Vector2i(cell.x, cell.z)))
	_leader().walk(true)


func _move_leader(delta: float) -> void:
	if _path.is_empty():
		return
	var leader := _leader()
	var step := WALK_SPEED * delta
	while step > 0.0 and not _path.is_empty():
		var to := _path[0]
		var d := leader.position.distance_to(to)
		leader.face(to)
		if d <= step:
			leader.position = to
			step -= d
			_path.pop_front()
		else:
			leader.position += (to - leader.position) / d * step
			step = 0.0
		_record_trail(leader.position)
	if _path.is_empty():
		leader.walk(false)
		_arrived()


func _record_trail(at: Vector3) -> void:
	if _trail.is_empty() or _trail[-1].distance_to(at) >= TRAIL_STEP:
		_trail.append(at)
		if _trail.size() > 200:
			_trail.pop_front()


## Каждый спутник держится на своём расстоянии позади ведущего по его следу.
func _move_companions(delta: float) -> void:
	for i in range(1, _heroes.size()):
		var hero := _heroes[i]
		var target := _trail_point(FOLLOW_GAP * i)
		var d := hero.position.distance_to(target)
		var moving := d > 0.05
		if moving:
			hero.face(target)
			hero.position = hero.position.move_toward(target, WALK_SPEED * 1.15 * delta)
		if moving != _walking[i]:
			_walking[i] = moving
			hero.walk(moving)


## Точка следа на расстоянии [param back] от ведущего.
func _trail_point(back: float) -> Vector3:
	var prev := _leader().position
	var left := back
	for i in range(_trail.size() - 1, -1, -1):
		var d := prev.distance_to(_trail[i])
		if d >= left:
			return prev.lerp(_trail[i], left / d)
		left -= d
		prev = _trail[i]
	return prev


func _arrived() -> void:
	if _talk_to == "":
		return
	var npc_id := _talk_to
	_talk_to = ""
	var npc := _area.get_npc(npc_id)
	var view := _npcs[npc_id]
	_leader().face(view.position)
	view.face(_leader().position)
	if npc.dialog == "" or not _content.dialogs.has(npc.dialog):
		return
	_set_hovered("")
	_dialog.open(
		tr(npc.name_key), DialogRunner.start(npc.dialog, _content.dialogs[npc.dialog], flags)
	)


## Камера следит за ведущим, но не уходит далеко за край области.
func _look_target() -> Vector3:
	var p := _leader().position + LOOK_SHIFT
	var margin := 4.0 * CELL
	p.x = clampf(p.x, margin, maxf(margin, (_area.width() - 1) * CELL - margin))
	p.z = clampf(p.z, margin, maxf(margin, (_area.depth() - 1) * CELL - margin * 0.5))
	return p


func _leader() -> UnitView:
	return _heroes[0]


func _leader_cell() -> Vector2i:
	var p := _leader().position
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)


# --- Участники ----------------------------------------------------------------


func _spawn_party(at: Vector2i) -> void:
	var party := PartyStore.load_party(_content.rules)
	var ids: Array[String] = []
	ids.assign(party.inventories.keys())
	ids.sort()
	for i in ids.size():
		var view := _add_person(ids[i], "party", ids[i], _name_of(ids[i]))
		view.place(_cell_pos(at) - Vector3(FOLLOW_GAP * i, 0.0, 0.0))
		view.face(view.position + Vector3.RIGHT)
		_heroes.append(view)
		_walking.append(false)
	for i in range(ids.size() * 4, -1, -1):
		_trail.append(_cell_pos(at) - Vector3(TRAIL_STEP * i, 0.0, 0.0))


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


# --- Область ------------------------------------------------------------------


func _build_area() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(_area.width() * CELL, _area.depth() * CELL)
	ground.mesh = plane
	ground.position = Vector3(
		(_area.width() - 1) * CELL / 2.0, 0.0, (_area.depth() - 1) * CELL / 2.0
	)
	ground.material_override = _material(Color(0.42, 0.52, 0.3))
	_world.add_child(ground)
	var road := _material(Color(0.55, 0.47, 0.34))
	var wall := _material(Color(0.47, 0.34, 0.22))
	var roof := _material(Color(0.36, 0.3, 0.2))
	var trunk := _material(Color(0.35, 0.25, 0.16))
	var crown := _material(Color(0.2, 0.36, 0.2))
	var fence := _material(Color(0.5, 0.4, 0.27))
	for z in _area.depth():
		for x in _area.width():
			var c := Vector2i(x, z)
			match _area.tile(c):
				AreaMap.ROAD:
					_box(c, Vector3(CELL, 0.02, CELL), 0.01, road)
				AreaMap.BUILDING:
					_box(c, Vector3(CELL, HOUSE_HEIGHT, CELL), HOUSE_HEIGHT / 2.0, wall)
					_box(c, Vector3(CELL * 1.08, 0.35, CELL * 1.08), HOUSE_HEIGHT + 0.17, roof)
				AreaMap.TREE:
					_tree(c, trunk, crown)
				AreaMap.FENCE:
					_fence(c, fence)


func _box(c: Vector2i, size: Vector3, y: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = _cell_pos(c) + Vector3(0.0, y, 0.0)
	_world.add_child(m)


## Дерево: ствол и конус кроны; размер чуть разный по клетке, чтобы лес не был ровным.
func _tree(c: Vector2i, trunk: Material, crown: Material) -> void:
	var s := 0.8 + float((c.x * 7 + c.y * 13) % 5) * 0.1
	var t := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.16
	cyl.height = 1.0 * s
	t.mesh = cyl
	t.material_override = trunk
	t.position = _cell_pos(c) + Vector3(0.0, 0.5 * s, 0.0)
	_world.add_child(t)
	var k := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.75 * s
	cone.height = 2.2 * s
	k.mesh = cone
	k.material_override = crown
	k.position = _cell_pos(c) + Vector3(0.0, 1.0 * s + 1.1 * s, 0.0)
	_world.add_child(k)


## Плетень: вдоль соседних плетней (по горизонтали или по вертикали).
func _fence(c: Vector2i, mat: Material) -> void:
	var along_x := (
		_area.tile(c + Vector2i.LEFT) == AreaMap.FENCE
		or _area.tile(c + Vector2i.RIGHT) == AreaMap.FENCE
	)
	var along_z := (
		_area.tile(c + Vector2i.UP) == AreaMap.FENCE
		or _area.tile(c + Vector2i.DOWN) == AreaMap.FENCE
	)
	if along_x or not along_z:
		_box(c, Vector3(CELL, FENCE_HEIGHT, 0.12), FENCE_HEIGHT / 2.0, mat)
	if along_z:
		_box(c, Vector3(0.12, FENCE_HEIGHT, CELL), FENCE_HEIGHT / 2.0, mat)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


# --- Интерфейс ----------------------------------------------------------------


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_hint.text = tr("UI_EXPLORE_HINT")
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(360, 0)
	box.add_child(_hint)
	var menu := Button.new()
	menu.text = tr("UI_MENU")
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file(MainMenu.SCENE))
	box.add_child(menu)
	layer.add_child(_dialog)
