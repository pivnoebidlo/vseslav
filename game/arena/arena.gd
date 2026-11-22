extends Node3D
## Тестовые бои этапа 1: рельеф арены, кнопки (сохранить, загрузить, заново,
## снаряжение, торг, отдых), выбор арены. Сам бой ведёт CombatSession (ADR-0032).
##
## Аргументы командной строки (после `--`):
##   --arena=NAME      арена из загруженных модулей: doroga | polyana | pogost (по умолчанию doroga)
##   --seed=N          фиксированный seed боя
##   --autoplay        за партию тоже играет ИИ (дымовая проверка)
##   --screenshot=PATH сохранить снимок экрана по окончании боя (или через 25 с) и выйти
##   --lang=ru|en      язык интерфейса (по умолчанию русский; меню настроек — позже)
## Без аргументов арена открывается из главного меню (game/menu), с аргументами — сразу.

const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/arena_combat.json"
const CELL := BattleGrid.CELL_SIZE_M
const LEVEL_HEIGHT := CombatBoard.LEVEL_HEIGHT
const WALL_HEIGHT := 2.4
const LOW_OBSTACLE_HEIGHT := 0.6
const SCREENSHOT_TIMEOUT := 25.0
const DEFAULT_LANG := "ru"
const WARN := CombatSession.WARN

var _arena := "doroga"
var _arena_data: Dictionary = {}
var _content: ModuleContent
var _db: RulesDb
var _arenas: Array[String] = []
var _figures: FigureCatalog
var _screens := PartyScreens.new()
var _session := CombatSession.new()
var _board := CombatBoard.new()
var _world: Node3D
var _terrain := Node3D.new()
var _autoplay := false
var _seed_override := -1
var _screenshot_path := ""
var _lang := DEFAULT_LANG

var _mat_floor := StandardMaterial3D.new()
var _mat_high := StandardMaterial3D.new()
var _mat_wall := StandardMaterial3D.new()
var _mat_low := StandardMaterial3D.new()

var _title := Label.new()
var _turn_label := Label.new()
var _hint := Label.new()
var _arena_select := OptionButton.new()


func _ready() -> void:
	_parse_args()
	TranslationServer.set_locale(_lang)
	_content = ModuleLoader.load_all()
	ModuleLocales.apply(_content.locales)
	_db = _content.rules
	_arenas = _content.arena_ids()
	if not _arenas.has(_arena) and not _arenas.is_empty():
		_arena = _arenas[0]
	_figures = FigureCatalog.from_content(_content, RigProfile.load_all())
	_screens.setup(_db, _content.merchants_data())
	_screens.dry_run = _autoplay
	_setup_materials()
	SceneEnv.add_to(self)
	_world = Node3D.new()
	add_child(_world)
	_world.add_child(_terrain)
	_world.add_child(_board)
	add_child(_session)
	_session.autoplay = _autoplay
	_setup_ui()
	_session.status_changed.connect(_on_status)
	_session.ended.connect(_on_ended)
	for err in _content.errors:
		push_error(err)
		_session.write(
			CombatLogFormat.tr_fmt("LOG_DATA_ERROR", {"error": err}), CombatLogFormat.COLOR_BAD
		)
	if _screenshot_path != "":
		get_tree().create_timer(SCREENSHOT_TIMEOUT).timeout.connect(_take_screenshot_and_quit)
	if _arenas.is_empty():
		return
	_load_arena(_arena)
	_new_combat()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			_autoplay = true
		elif arg.begins_with("--arena="):
			_arena = arg.trim_prefix("--arena=")
		elif arg.begins_with("--seed="):
			_seed_override = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--lang="):
			_lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")


func _load_arena(name: String) -> void:
	_arena = name
	_arena_data = _content.arenas.get(name, {})
	_title.text = tr(JsonRead.get_str(_arena_data, "title_key"))
	_arena_select.select(_arenas.find(name))


func _unhandled_input(event: InputEvent) -> void:
	var camera := get_viewport().get_camera_3d() as ArenaCamera
	if camera != null:
		camera.handle_input(event)


# --- Построение сцены ---------------------------------------------------------


func _setup_materials() -> void:
	_mat_floor.albedo_color = Color(0.42, 0.5, 0.3)
	_mat_high.albedo_color = Color(0.55, 0.5, 0.38)
	_mat_wall.albedo_color = Color(0.35, 0.3, 0.27)
	_mat_low.albedo_color = Color(0.5, 0.38, 0.24)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_session.setup(layer, _board, _world)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	box.add_child(_turn_label)
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(430, 0)
	box.add_child(_hint)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_add_button(buttons, "UI_SAVE", _on_save)
	_add_button(buttons, "UI_LOAD", _on_load)
	_add_button(buttons, "UI_RESTART", _on_restart)
	_add_button(buttons, "UI_EQUIPMENT", _on_equipment)
	_add_button(buttons, "UI_TRADE", _on_trade)
	_add_button(buttons, "UI_REST", _on_rest)

	var arena_row := HBoxContainer.new()
	box.add_child(arena_row)
	var arena_label := Label.new()
	arena_label.text = tr("UI_ARENA")
	arena_row.add_child(arena_label)
	for name in _arenas:
		var data := _content.arenas[name]
		_arena_select.add_item(tr(JsonRead.get_str(data, "title_key")))
	_arena_select.item_selected.connect(_on_arena_selected)
	arena_row.add_child(_arena_select)
	_add_button(arena_row, "UI_MENU", _on_menu)

	_screens.changed.connect(_on_party_changed)
	_screens.message.connect(
		func(text: String) -> void: _session.write(text, CombatLogFormat.COLOR_GOOD)
	)
	layer.add_child(_screens)


func _add_button(parent: Container, key: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = tr(key)
	button.pressed.connect(handler)
	parent.add_child(button)


## Рельеф, клетки боя, камера и фигуры участников заново.
func _rebuild_world(state: CombatState) -> void:
	for child in _terrain.get_children():
		child.queue_free()
	for id: String in _session.units:
		_session.units[id].queue_free()
	_session.units.clear()
	var grid := state.grid
	var camera := ArenaCamera.new()
	_terrain.add_child(camera)
	camera.frame(grid.width, grid.depth, CELL)
	camera.current = true
	for z in grid.depth:
		for x in grid.width:
			_add_tile(grid, Vector2i(x, z))
	_board.build(grid)
	for c in state.combatants:
		var view := UnitView.new()
		_world.add_child(view)
		var entry := _figures.entry(_template_id(c.id))
		view.setup(c.id, c.team, entry, _figures.instantiate(entry))
		view.place(_board.position_of(c.column))
		_session.units[c.id] = view
	for err in _figures.errors:
		push_error(err)
		_session.write(
			CombatLogFormat.tr_fmt("LOG_DATA_ERROR", {"error": err}), CombatLogFormat.COLOR_BAD
		)
	_figures.errors.clear()
	_session.state = state
	_session.face_enemies()


## Id персонажа или существа, из которого собран участник арены.
func _template_id(combatant_id: String) -> String:
	for raw: Variant in JsonRead.get_array(_arena_data, "combatants"):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		if JsonRead.get_str(entry, "id") == combatant_id:
			var character := JsonRead.get_str(entry, "character")
			return character if character != "" else JsonRead.get_str(entry, "creature")
	return ""


func _add_tile(grid: BattleGrid, column: Vector2i) -> void:
	var blocked := grid.is_blocked(column)
	var low := grid.is_low_obstacle(column)
	var top := grid.level_at(column) * LEVEL_HEIGHT
	if blocked:
		top = LOW_OBSTACLE_HEIGHT if low else WALL_HEIGHT
	var height := top + 0.3
	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL * 0.96, height, CELL * 0.96)
	tile.mesh = box
	tile.position = Vector3(column.x * CELL, top - height / 2.0, column.y * CELL)
	if blocked:
		tile.material_override = _mat_low if low else _mat_wall
	else:
		tile.material_override = _mat_high if grid.level_at(column) > 0 else _mat_floor
	_terrain.add_child(tile)


# --- Бой ----------------------------------------------------------------------


func _new_combat() -> void:
	var seed_value := _seed_override if _seed_override >= 0 else randi()
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(_arena_data, seed_value, _db, errors, _screens.party)
	_session.stop()
	_session.clear_log()
	_session.write(
		CombatLogFormat.tr_fmt("LOG_COMBAT_SEED", {"arena": _arena, "seed": str(seed_value)}),
		CombatLogFormat.COLOR_INFO
	)
	for err in errors:
		_session.write(
			CombatLogFormat.tr_fmt("LOG_DATA_ERROR", {"error": err}), CombatLogFormat.COLOR_BAD
		)
	_rebuild_world(state)
	await _session.start(state)


func _on_status(turn: String, hint: String) -> void:
	_turn_label.text = turn
	_hint.text = hint


func _on_ended(_winner: String) -> void:
	# Потраченное в бою (брошенное, выпитое) списывается из снаряжения партии.
	_screens.after_combat(_session.state)
	if _screenshot_path != "":
		await get_tree().create_timer(0.5).timeout
		_take_screenshot_and_quit()


# --- Кнопки -------------------------------------------------------------------


func _on_save() -> void:
	if _session.is_busy():
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	var data := {"arena": _arena, "combat": _session.state.to_dict()}
	file.store_string(JSON.stringify(data, "  ", true))
	file.close()
	_session.write(tr("LOG_SAVED"), CombatLogFormat.COLOR_GOOD)


func _on_load() -> void:
	if _session.is_busy():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_session.write(tr("LOG_NO_SAVE"), WARN)
		return
	var data: Dictionary = parsed
	var arena := JsonRead.get_str(data, "arena")
	if not _arenas.has(arena):
		_session.write(tr("LOG_NO_SAVE"), WARN)
		return
	_load_arena(arena)
	var loaded := CombatState.from_dict(
		JsonRead.get_dict(data, "combat"), ArenaLoader.grid_from(_arena_data)
	)
	if loaded == null:
		_session.write(tr("LOG_NO_SAVE"), WARN)
		return
	_session.stop()
	_rebuild_world(loaded)
	_session.write(tr("LOG_LOADED"), CombatLogFormat.COLOR_GOOD)
	await _session.resume(loaded)


func _on_equipment() -> void:
	if not _session.is_busy():
		_session.hide_preview()
		_screens.open_equipment(_session.state)


func _on_trade() -> void:
	if not _session.is_busy():
		_session.hide_preview()
		_screens.open_trade(_session.state)


func _on_rest() -> void:
	if _session.is_busy():
		return
	_session.hide_preview()
	if not _screens.open_rest(_session.state):
		_session.write(tr("LOG_REST_NOT_NOW"), WARN)


func _on_party_changed() -> void:
	if not _session.state.ended:
		_new_combat()


func _on_restart() -> void:
	if not _session.is_busy():
		_new_combat()


func _on_menu() -> void:
	if not _session.is_busy():
		get_tree().change_scene_to_file(MainMenu.SCENE)


func _on_arena_selected(index: int) -> void:
	if _session.is_busy():
		_arena_select.select(_arenas.find(_arena))
		return
	_load_arena(_arenas[index])
	_new_combat()


func _take_screenshot_and_quit() -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(_screenshot_path)
	print("Screenshot saved: %s" % _screenshot_path)
	get_tree().quit()
