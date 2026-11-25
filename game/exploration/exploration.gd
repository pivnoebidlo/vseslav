class_name Exploration
extends Node3D
## Исследование в реальном времени (ADR-0029, ADR-0030): клик по земле — выбранный герой
## идёт туда, сцепленные спутники следом; клик по жителю — подойти и поговорить.
## Героя выбирают по портрету, по фигуре или Tab; путь под курсором виден всегда,
## сетка клеток включается кнопкой или G. Мир здесь не детерминирован (SPEC §3.1);
## путь ищет Pathfinder ядра по сетке области. Когда срабатывает энкаунтер, мир
## замирает и на участке карты идёт пошаговый бой (CombatSession, ADR-0032).

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
const SCENE := "res://game/exploration/exploration.tscn"


## Герой на карте и его путь.
class Walker:
	extends RefCounted
	var view: UnitView
	var path: Array[Vector3] = []
	var walking := false


## Флаги мира и включённая сетка живут, пока запущена игра (сохранение — позже).
static var flags := WorldFlags.new()
## Броски вне боя (проверки в диалогах) — через Rng ядра; seed на сессию.
static var rng := Rng.new(randi())
## Содержимое открытых сундуков: "<область>.<id>" → мешок (ADR-0034).
static var chests: Dictionary = {}

var _content: ModuleContent
var _screens := PartyScreens.new()
var _session := CombatSession.new()
var _board := CombatBoard.new()
## Противники на карте: id участника → фигура (у живых — до победы над энкаунтером).
var _foes: Dictionary[String, UnitView] = {}
var _encounter: Encounter = null
var _hero_cells: Array[Vector2i] = []
## Куда смотрит камера в бою (чей ход).
var _combat_focus := ""
var _game_over := GameOverPanel.new()
var _map_points := MapPoints.new()
var _journal: JournalPanel
## Куда идёт выбранный герой: "exit:<id>" или "chest:<id>" (MapPoints).
var _going_to := ""
var _area: AreaMap
var _figures: FigureCatalog
var _camera := MapCamera.new()
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
var _events := EventPlayer.new()
var _runner: DialogRunner = null
var _dice := DiceRoll.new()
var _party_bar := PartyBar.new()
var _side := SideMenu.new()
var _menu := GameMenu.new()
var _title := Label.new()
var _hint := Label.new()


func _ready() -> void:
	GameSettings.ensure_loaded()
	_content = ModuleLoader.load_all()
	ModuleLocales.apply(_content.locales)
	_figures = FigureCatalog.from_content(_content, RigProfile.load_all())
	var env := SceneEnv.add_to(self)
	add_child(_world)
	_world.add_child(_camera)
	_camera.current = true
	_world.add_child(_path_preview)
	_world.add_child(_board)
	add_child(_session)
	ExplorationUi.setup(self)
	var start := _content.start()
	var save := _take_save()
	var area_id := save.area if save != null else JsonRead.get_str(start, "area")
	_area = _content.area(area_id)
	if _area == null:
		_hint.text = tr("UI_EXPLORE_NO_START")
		for err in _content.errors:
			push_error(err)
		return
	_title.text = tr(_area.title_key)
	if _area.interior:
		SceneEnv.make_interior(env)
	_area_view.build(
		_area, PropCatalog.from_content(_content), SurfaceCatalog.from_content(_content)
	)
	_area_view.set_grid_visible(GameSettings.show_grid)
	_world.add_child(_area_view)
	_map_points.build(_area)
	_world.add_child(_map_points)
	_spawn_npcs()
	_spawn_foes()
	var spawn: Vector2i = _area.spawns.get(JsonRead.get_str(start, "spawn"), Vector2i.ZERO)
	var cells: Dictionary[String, Vector2i] = {}
	if save != null and not save.heroes.is_empty():
		cells = save.heroes
	elif save != null:
		cells = _cells_at_spawn(save.spawn)
	_spawn_party(spawn, cells)
	if save != null:
		_restore_group(save)
	_look = _look_target()
	_camera.focus(_look, CAMERA_ZOOM)
	if save != null and save.mode == GameSave.MODE_COMBAT:
		_resume_combat(save)
	else:
		_fire_events(AreaMap.AreaEvent.ON_ENTER_AREA, _leader_cell())


func _process(delta: float) -> void:
	if _heroes.is_empty():
		return
	if _in_combat():
		_look = _look.lerp(_combat_look(), minf(1.0, delta * CAMERA_LAG))
		_camera.focus(_look)
		return
	var followers := _group.followers()
	for id in _group.ids:
		if not followers.has(id):
			_advance(_heroes[id], delta, id == _group.selected)
	for i in followers.size():
		_follow_trail(_heroes[followers[i]], FOLLOW_GAP * (i + 1), delta)
	_look = _look.lerp(_look_target(), minf(1.0, delta * CAMERA_LAG))
	_camera.focus(_look)
	_check_encounters()


# --- Ввод ---------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var pressed := key != null and key.pressed and not key.echo
	if pressed and key.keycode == KEY_ESCAPE and not _in_combat():
		_toggle_menu()
		return
	if _input_blocked():
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_camera.handle_input(event)
		return
	if pressed and _save_key(key.keycode):
		return
	if _in_combat():
		return
	if pressed:
		_on_key(key.keycode)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_hover(motion.position)
	elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_on_click(button.position)


## F5 и F9 работают и в бою; true — клавиша обработана.
func _save_key(keycode: Key) -> bool:
	if keycode == KEY_F5:
		_quick_save()
	elif keycode == KEY_F9:
		_load_latest()
	else:
		return false
	return true


## Окно, разговор, событие на экране — карта не слушает мышь и клавиши.
func _input_blocked() -> bool:
	if _menu.is_open() or _dialog.is_open() or _screens.is_open():
		return true
	return _heroes.is_empty() or _events.is_busy()


func _on_key(keycode: Key) -> void:
	match keycode:
		KEY_G:
			_set_grid(not _area_view.is_grid_visible())
		KEY_TAB:
			_select(_group.next_id())
		KEY_C:
			_open_window("hero")
		KEY_I:
			_open_window("items")
		KEY_J:
			_open_window("journal")
		KEY_R:
			_open_window("rest")


func _on_hover(screen_pos: Vector2) -> void:
	var id := _unit_under(screen_pos)
	_set_hovered(id)
	_map_points.set_hovered(id.trim_prefix("@") if id.begins_with("@") else "")
	if id.begins_with("@"):
		_preview(_point_path(id.trim_prefix("@")))
	elif _npcs.has(id):
		_preview(_area.approach(_leader_cell(), id, _foe_cells()))
	elif id != "":
		_path_preview.clear()
	else:
		_preview(_area.path(_leader_cell(), _cell_under(screen_pos), _foe_cells()))


func _on_click(screen_pos: Vector2) -> void:
	var id := _unit_under(screen_pos)
	_going_to = ""
	if _heroes.has(id):
		_select(id)
	elif id.begins_with("@"):
		_go_point(id.trim_prefix("@"))
	elif _npcs.has(id):
		_go_talk(id)
	else:
		_talk_to = ""
		_walk_leader(_area.path(_leader_cell(), _cell_under(screen_pos), _foe_cells()))
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
	if collider.has_meta("point"):
		return "@" + str(collider.get_meta("point"))
	return str(collider.get_meta("unit_id", ""))


## Клетка земли под курсором: луч по рельефу (слой земли), мимо — плоскость y = 0.
func _cell_under(screen_pos: Vector2) -> Vector2i:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 300.0)
	query.collision_mask = AreaView.TERRAIN_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var at: Vector3 = hit["position"]
		return _cell_of(at)
	if absf(dir.y) < 0.001:
		return Vector2i(-1, -1)
	return _cell_of(origin + dir * (-origin.y / dir.y))


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
	if id == "" or id == _group.selected or _in_combat():
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
	GameSettings.show_grid = on
	GameSettings.save()
	_area_view.set_grid_visible(on)


## Портреты: вне боя — хиты партии; в бою — хиты бойцов и рамка у того, чей ход.
func _refresh_bar() -> void:
	var hp: Dictionary[String, Vector2i] = {}
	var combat := _in_combat() and _session.state != null
	for id in _group.ids:
		if combat:
			var c := _session.state.get_combatant(id)
			if c != null:
				hp[id] = Vector2i(c.hp, c.max_hp)
		else:
			var hero := _screens.party.build_hero(_content.rules, id)
			hp[id] = Vector2i(hero.hp, hero.max_hp)
	_party_bar.refresh(_group, _names, hp, combat, _combat_focus)


# --- Ходьба -------------------------------------------------------------------


func _go_talk(npc_id: String) -> void:
	var npc := _area.get_npc(npc_id)
	_talk_to = npc_id
	if AreaMap.is_next_to(_leader_cell(), npc.at):
		_leader().path.clear()
		_arrived()
		return
	var p := _area.approach(_leader_cell(), npc_id, _foe_cells())
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
		var p := _area.path(_cell_of(w.view.position), _cell_of(to), _foe_cells())
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
	if _going_to != "":
		_reach_point()
		return
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
	_talk(npc.dialog, tr(npc.name_key), npc_id if _screens.market.order.has(npc_id) else "")


## Разговор: контекст событий (ADR-0042); [param merchant_id] — купец, кнопка «Торг» (ADR-0049).
func _talk(dialog_id: String, speaker: String, merchant_id: String = "") -> void:
	if not _content.dialogs.has(dialog_id):
		_events.resume()
		return
	_runner = DialogRunner.start(dialog_id, _content.dialogs[dialog_id], flags, _event_ctx())
	_dialog.open(
		speaker, _runner, _names[_group.selected], _abilities(_group.selected), merchant_id
	)


func _event_ctx() -> EventContext:
	var ctx := EventContext.new(flags, _screens.party, _content.rules)
	ctx.receiver = _group.selected
	return ctx


## Действия вне диалога (победа, сундук, событие): применить и исполнить запросы.
func _run_actions(actions: Array) -> void:
	var ctx := _event_ctx()
	EventActions.run(actions, ctx)
	_quests_updated(ctx.quests)
	_events.play(ctx.take_requests())


func _fire_events(on: String, cell: Vector2i) -> void:
	var due := AreaEvents.due(_area, on, cell, flags)
	if due.is_empty():
		return
	var ctx := _event_ctx()
	for ev in due:
		AreaEvents.fire(_area, ev, ctx)
	_quests_updated(ctx.quests)
	_events.play(ctx.take_requests())


func _on_dialog_finished() -> void:
	if _runner != null:
		_events.play(_runner.take_requests())
		_runner = null
	_events.resume()


## Очередь событий пуста: жители по условиям, состав отряда (принят или отпущен —
## сцена пересобирается на том же месте).
func _on_events_finished() -> void:
	_refresh_npcs()
	if _screens.party.members != _group.ids and not _in_combat():
		_screens.save()
		var s := _make_save()
		SaveStore.pending = s
		Loading.change_scene(self, SCENE)


## Характеристики героя для проверок в разговоре.
func _abilities(character_id: String) -> Abilities:
	var errors: Array[String] = []
	var data := _content.rules.characters[character_id]
	return CombatantBuilder.from_character(_content.rules, data, errors).abilities


## Смещение взгляда к камере с учётом её поворота.
func _shift() -> Vector3:
	return LOOK_SHIFT.rotated(Vector3.UP, _camera.get_yaw())


## Камера следит за выбранным, но не уходит далеко за край области.
func _look_target() -> Vector3:
	var p := _leader().view.position + _shift()
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
	return AreaView.cell_pos(_area, c)


# --- Участники ----------------------------------------------------------------


## Герои — в клетках [param cells] (из сохранения) или цепочкой у точки [param at].
func _spawn_party(at: Vector2i, cells: Dictionary[String, Vector2i] = {}) -> void:
	var ids: Array[String] = _screens.party.members.duplicate()
	_group = PartyGroup.new(ids)
	var taken: Dictionary[Vector2i, bool] = {}
	for c: Vector2i in cells.values():
		taken[c] = true
	var near: Vector2i = cells.values()[0] if not cells.is_empty() else at
	for i in ids.size():
		var w := Walker.new()
		_names[ids[i]] = _name_of(ids[i])
		w.view = _add_person(ids[i], "party", ids[i], _names[ids[i]])
		w.view.place(_cell_pos(at) - Vector3(FOLLOW_GAP * i, 0.0, 0.0))
		if cells.has(ids[i]):
			w.view.place(_cell_pos(cells[ids[i]]))
		elif not cells.is_empty():
			# Новичок отряда встаёт рядом с остальными.
			var spot := Encounter.nearest_free(_area.grid, near, taken)
			taken[spot] = true
			w.view.place(_cell_pos(spot))
		w.view.face(w.view.position + Vector3.RIGHT)
		_heroes[ids[i]] = w
	for i in range(ids.size() * 8, -1, -1):
		_trail.append(_cell_pos(at) - Vector3(TRAIL_STEP * i, 0.0, 0.0))
	_leader().view.set_active(true)
	_refresh_bar()


func _spawn_npcs() -> void:
	for npc in AreaEvents.present_npcs(_area, flags):
		var view := _add_person(npc.id, "village", npc.look, tr(npc.name_key))
		view.place(_cell_pos(npc.at))
		view.face(view.position + Vector3.BACK)
		_npcs[npc.id] = view


## Жители по условиям (ADR-0042): ушедшие исчезают, пришедшие появляются.
func _refresh_npcs() -> void:
	var present: Dictionary[String, bool] = {}
	for npc in AreaEvents.present_npcs(_area, flags):
		present[npc.id] = true
		if not _npcs.has(npc.id):
			var view := _add_person(npc.id, "village", npc.look, tr(npc.name_key))
			view.place(_cell_pos(npc.at))
			_npcs[npc.id] = view
	for id: String in _npcs.keys():
		if not present.has(id):
			_npcs[id].queue_free()
			_npcs.erase(id)


## Противники энкаунтеров, над которыми ещё не победили, стоят на своих местах.
func _spawn_foes() -> void:
	for e in _area.encounters:
		if e.is_done(flags):
			continue
		for c in e.combatants:
			var creature := JsonRead.get_str(c, "creature")
			var name := _creature_name(creature)
			var view := _add_person(
				JsonRead.get_str(c, "id"), JsonRead.get_str(c, "team"), creature, name
			)
			view.place(_cell_pos(e.cell_of(c)))
			view.face(view.position + Vector3.BACK)
			_foes[JsonRead.get_str(c, "id")] = view


func _creature_name(creature: String) -> String:
	if not _content.rules.creatures.has(creature):
		return creature
	return tr(JsonRead.get_str(_content.rules.creatures[creature], "name_key"))


## Клетки живых противников на карте — их обходят.
func _foe_cells() -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for e in _area.encounters:
		if not e.is_done(flags):
			for c in e.combatants:
				cells[e.cell_of(c)] = true
	return cells


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


# --- Бой на карте (ADR-0032) ---------------------------------------------------


func _in_combat() -> bool:
	return _encounter != null


## Срабатывает ли энкаунтер — проверяется, только когда кто-то из героев сменил клетку.
func _check_encounters() -> void:
	var cells: Array[Vector2i] = []
	for id in _group.ids:
		cells.append(_cell_of(_heroes[id].view.position))
	if cells == _hero_cells:
		return
	_hero_cells = cells
	_fire_events(AreaMap.AreaEvent.ON_ENTER_ZONE, _leader_cell())
	_fire_events(AreaMap.AreaEvent.ON_TRIGGER_ENTERED, _leader_cell())
	if _in_combat():
		return
	for e in _area.encounters:
		if not e.is_done(flags) and e.triggered(_area, cells):
			_start_combat(e)
			return


func _start_combat(e: Encounter) -> void:
	# Перед боем — автосохранение: при поражении можно начать бой заново.
	SaveStore.write(_make_save(), SaveStore.AUTO)
	_encounter = e
	_talk_to = ""
	_path_preview.clear()
	_set_hovered("")
	for id in _group.ids:
		var w := _heroes[id]
		w.path.clear()
		_set_walking(w, false)
	var heroes: Dictionary[String, Vector2i] = {}
	for id in _group.ids:
		heroes[id] = _cell_of(_heroes[id].view.position)
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(
		e.arena_data(_area, heroes), randi(), _content.rules, errors, _screens.party
	)
	for err in errors:
		push_error(err)
	await _enter_combat(e, state, true)
	_session.write(tr("LOG_GAME_AUTOSAVED"), CombatLogFormat.COLOR_INFO)
	await _session.start(state)


## Поле, фигуры и интерфейс боя для [param state]; [param animate] — герои
## перебегают в свои клетки, иначе ставятся сразу (загрузка).
func _enter_combat(e: Encounter, state: CombatState, animate: bool) -> void:
	_encounter = e
	_set_combat_ui(true)
	_board.build(state.grid, e.battle.position)
	_session.units.clear()
	for id in _group.ids:
		_session.units[id] = _heroes[id].view
	for c in e.combatants:
		var foe_id := JsonRead.get_str(c, "id")
		_session.units[foe_id] = _foes[foe_id]
	_area_view.set_grid_visible(true)
	_session.show_ui(true)
	_session.clear_log()
	_session.write(tr("LOG_ENCOUNTER"), CombatLogFormat.COLOR_INFO)
	# Герои встают в клетки поля боя (SPEC §3.2).
	if animate:
		var tween := create_tween().set_parallel(true)
		for c in state.combatants:
			if _session.units.has(c.id):
				var to := _board.position_of(c.column)
				tween.tween_property(_session.units[c.id], "position", to, 0.35)
		await tween.finished
	for c in state.combatants:
		if _session.units.has(c.id):
			_session.units[c.id].place(_board.position_of(c.column))
	_session.state = state
	_session.face_enemies()
	_combat_focus = ""


func _resume_combat(save: GameSave) -> void:
	var e := _area.get_encounter(save.encounter)
	if e == null:
		return
	var none: Dictionary[String, Vector2i] = {}
	var grid := ArenaLoader.grid_from(e.arena_data(_area, none))
	var state := CombatState.from_dict(save.combat, grid)
	if state == null:
		return
	await _enter_combat(e, state, false)
	_session.write(tr("LOG_LOADED"), CombatLogFormat.COLOR_GOOD)
	await _session.resume(state)


func _on_combat_status(turn: String, hint: String) -> void:
	_title.text = turn
	_hint.text = hint
	_refresh_bar()


func _on_combat_ended(winner: String) -> void:
	var state := _session.state
	_session.stop()
	if winner != Encounter.TEAM_PARTY:
		_session.show_ui(false)
		_game_over.open()
		_game_over.set_can_load(SaveStore.has_any())
		return
	flags.set_flag(_encounter.won_flag(), true)
	_run_actions(_encounter.on_won)
	# Добыча, траты и раны — в партию (ADR-0026, ADR-0027).
	_screens.after_combat(state)
	for c in _encounter.combatants:
		_foes.erase(JsonRead.get_str(c, "id"))
	for id in _group.ids:
		var hero := _screens.party.build_hero(_content.rules, id)
		_heroes[id].view.refresh(_names[id], hero)
		_heroes[id].view.show_as_person(_names[id])
		_heroes[id].view.set_active(id == _group.selected)
	_encounter = null
	_session.show_ui(false)
	_area_view.set_grid_visible(GameSettings.show_grid)
	_set_combat_ui(false)
	_title.text = tr(_area.title_key)
	_hint.text = tr("UI_EXPLORE_HINT")
	_trail = [_leader().view.position]
	_hero_cells.clear()


## В бою камера следит за тем, чей ход.
func _combat_look() -> Vector3:
	var view: UnitView = _session.units.get(_combat_focus, null)
	if view == null:
		return _look
	return view.position + _shift()


# --- Выходы, сундуки, журнал (ADR-0034) ------------------------------------------


## Путь к точке: на клетку выхода или к соседней с сундуком клетке.
func _point_path(key: String) -> PathResult:
	if MapPoints.kind_of(key) == MapPoints.EXIT:
		var x := _area.get_exit(MapPoints.id_of(key))
		return _area.path(_leader_cell(), x.at, _foe_cells())
	var box := _area.get_container(MapPoints.id_of(key))
	return _area.approach_cell(_leader_cell(), box.at, _foe_cells())


func _go_point(key: String) -> void:
	_talk_to = ""
	_going_to = key
	var p := _point_path(key)
	if p.found():
		_walk_leader(p)
	else:
		_reach_point()


## Выбранный герой дошёл: на выходе — переход, у сундука — открыть.
func _reach_point() -> void:
	var key := _going_to
	_going_to = ""
	var cell := _leader_cell()
	if MapPoints.kind_of(key) == MapPoints.EXIT:
		var x := _area.get_exit(MapPoints.id_of(key))
		if cell == x.at:
			_travel(x)
		return
	var box := _area.get_container(MapPoints.id_of(key))
	if AreaMap.is_next_to(cell, box.at):
		_open_chest(box)


## Переход в другую область: сохранение с точкой появления и пересоздание сцены.
func _travel(x: AreaMap.Exit) -> void:
	var s := _make_save()
	s.area = x.to_area
	s.heroes.clear()
	s.spawn = x.to_spawn
	SaveStore.write(s, SaveStore.AUTO)
	SaveStore.pending = s
	Loading.change_scene(self, SCENE)


## Перенос событием: как выход, но в любую область и точку.
func _teleport(area_id: String, spawn: String) -> void:
	var x := AreaMap.Exit.new()
	x.to_area = area_id
	x.to_spawn = spawn
	_travel(x)


func _item_name(item_id: String) -> String:
	var item: Dictionary = _content.rules.items.get(item_id, {})
	return tr(JsonRead.get_str(item, "name_key", item_id))


func _cells_at_spawn(spawn: String) -> Dictionary[String, Vector2i]:
	var ids: Array[String] = []
	ids.assign(_screens.party.inventories.keys())
	ids.sort()
	var spots := _area.spawn_cells(spawn, ids.size())
	var cells: Dictionary[String, Vector2i] = {}
	for i in ids.size():
		cells[ids[i]] = spots[i]
	return cells


## Сундук: при первом открытии — его действия (стадия квеста); содержимое делят герои,
## что не взяли — остаётся в сундуке.
func _open_chest(box: AreaMap.Chest) -> void:
	_leader().view.face(_cell_pos(box.at))
	var key := "%s.%s" % [_area.id, box.id]
	if not chests.has(key):
		chests[key] = box.contents.duplicate(true)
		_run_actions(box.on_open)
	var stored: Dictionary = chests[key]
	var pile := Inventory.from_dict(stored)
	if pile.purse == 0 and pile.bag.is_empty():
		_notify(tr("LOG_CHEST_EMPTY"))
		return
	_screens.open_chest(box.name_key, pile, _group.ids)
	await _screens.loot_finished
	chests[key] = pile.to_dict()


func _quests_updated(quests: Array[String]) -> void:
	for id in quests:
		if _content.quests.has(id):
			var title := tr(JsonRead.get_str(_content.quests[id], "title_key"))
			_notify(tr("LOG_JOURNAL_UPDATED").format({"title": title}))


# --- Сохранения (ADR-0032) -----------------------------------------------------


## Новая игра или сохранение, выбранное в меню / по F9; применяет флаги, партию и RNG.
## Возвращает сохранение (клетки героев, бой) или null.
func _take_save() -> GameSave:
	var save := SaveStore.pending
	SaveStore.pending = null
	if SaveStore.new_game:
		SaveStore.new_game = false
		flags = WorldFlags.new()
		chests = {}
		_screens.party = Party.from_db(_content.rules)
		_screens.party.set_members(JsonRead.get_str_array(_content.start(), "party"))
		_screens.save()
		return null
	if save == null:
		return null
	var errors: Array[String] = []
	save.check(_content, errors)
	if not errors.is_empty():
		_hint.text = tr(errors[0])
		return null
	flags = save.flags
	chests = save.containers.duplicate(true)
	_screens.party = Party.from_dict(save.party, _content.rules, errors)
	_screens.save()
	if not save.rng.is_empty():
		rng = Rng.from_dict(save.rng)
	return save


func _restore_group(save: GameSave) -> void:
	for id in _group.ids:
		if not save.chained.get(id, true):
			_group.toggle_chain(id)
	if _heroes.has(save.selected):
		_leader().view.set_active(false)
		_group.select(save.selected)
		_leader().view.set_active(true)
	_trail = [_leader().view.position]
	_refresh_bar()


func _make_save() -> GameSave:
	var s := GameSave.new()
	for m in _content.modules:
		if not m.start.is_empty():
			s.module_id = m.id
			s.module_version = m.version
	s.area = _area.id
	for id in _group.ids:
		s.heroes[id] = _cell_of(_heroes[id].view.position)
		s.chained[id] = _group.is_chained(id)
	s.selected = _group.selected
	s.flags = WorldFlags.from_dict(flags.to_dict())
	s.party = _screens.party.to_dict()
	s.rng = rng.to_dict()
	s.containers = chests.duplicate(true)
	if _in_combat():
		s.mode = GameSave.MODE_COMBAT
		s.encounter = _encounter.id
		s.combat = _session.state.to_dict()
	return s


func _quick_save() -> void:
	if _dialog.is_open() or (_in_combat() and not _session.can_save()):
		_notify(tr("LOG_SAVE_NOT_NOW"))
		return
	SaveStore.write(_make_save(), SaveStore.QUICK)
	_notify(tr("LOG_GAME_SAVED"))


func _load_latest() -> void:
	var errors: Array[String] = []
	var save := SaveStore.latest(errors)
	if save == null:
		_notify(tr(errors[0] if not errors.is_empty() else "LOG_NO_SAVE"))
		return
	SaveStore.pending = save
	Loading.change_scene(self, SCENE)


func _notify(text: String) -> void:
	if _in_combat():
		_session.write(text, CombatLogFormat.COLOR_INFO)
	else:
		_hint.text = text


# --- Интерфейс (ExplorationUi) ---------------------------------------------------


func _open_window(id: String) -> void:
	ExplorationUi.open_window(self, id)


func _toggle_menu() -> void:
	ExplorationUi.toggle_menu(self)


func _set_combat_ui(on: bool) -> void:
	ExplorationUi.set_combat_ui(self, on)
