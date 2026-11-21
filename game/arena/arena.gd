extends Node3D
## Тестовые бои этапа 1. Представление только отображает CombatState и передаёт
## команды ядру (SPEC §6.2): ход, перемещение, выбор действия и цели, предпросмотр.
##
## Аргументы командной строки (после `--`):
##   --arena=NAME      doroga | polyana | pogost (по умолчанию doroga)
##   --seed=N          фиксированный seed боя
##   --autoplay        за партию тоже играет ИИ (дымовая проверка)
##   --screenshot=PATH сохранить снимок экрана по окончании боя (или через 25 с) и выйти
##   --lang=ru|en      язык интерфейса (по умолчанию русский; меню настроек — позже)

const ARENAS: Array[String] = ["doroga", "polyana", "pogost"]
const ARENA_DIR := "res://modules/spike/arenas"
const MODULE_DIRS: Array[String] = ["res://modules/base", "res://modules/spike"]
const RULES_DIR := "res://modules/base/rules"
const MODELS_DIR := "res://modules/base/models"
const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/arena_combat.json"
const CELL := BattleGrid.CELL_SIZE_M
const LEVEL_HEIGHT := 0.75
const WALL_HEIGHT := 2.4
const LOW_OBSTACLE_HEIGHT := 0.6
const AI_STEP_DELAY := 0.3
const MOVE_STEP_TIME := 0.22
const SCREENSHOT_TIMEOUT := 25.0
const CAMERA_OFFSET := Vector3(0.0, 14.0, 10.0)
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.3
const ZOOM_STEP := 0.1
const PAN_STEP := 0.75
const PAN_DRAG_SPEED := 0.02
const DEFAULT_LANG := "ru"
const NO_CELL := ActionResolver.NO_CELL

var _arena := "doroga"
var _arena_data: Dictionary = {}
var _db: RulesDb
var _figures: FigureCatalog
var _state: CombatState
var _world: Node3D
var _camera: Camera3D = null
var _camera_target := Vector3.ZERO
var _zoom := 1.0
var _tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _units: Dictionary[String, UnitView] = {}
var _highlighted: Array[Vector2i] = []
var _area_cells: Array[Vector2i] = []
var _selected: ActionDef = null
var _busy := false
var _autoplay := false
var _seed_override := -1
var _screenshot_path := ""
var _lang := DEFAULT_LANG

var _mat_floor := StandardMaterial3D.new()
var _mat_high := StandardMaterial3D.new()
var _mat_wall := StandardMaterial3D.new()
var _mat_low := StandardMaterial3D.new()
var _mat_reach := StandardMaterial3D.new()
var _mat_range := StandardMaterial3D.new()
var _mat_area := StandardMaterial3D.new()

var _title := Label.new()
var _turn_label := Label.new()
var _hint := Label.new()
var _arena_select := OptionButton.new()
var _initiative := InitiativeBar.new()
var _actions := ActionBar.new()
var _preview := Label.new()
var _log: CombatLogPanel
var _reaction_dialog: ReactionDialog
var _hovered_id := ""


func _ready() -> void:
	_parse_args()
	TranslationServer.set_locale(_lang)
	for dir in MODULE_DIRS:
		ModuleLocales.load_module(dir)
	_db = RulesDb.load_dir(RULES_DIR)
	_figures = FigureCatalog.load_dir(MODELS_DIR, RigProfile.load_all())
	_setup_materials()
	_setup_environment()
	_setup_ui()
	_world = Node3D.new()
	add_child(_world)
	for err in _db.errors:
		push_error(err)
		_write(CombatLogFormat.tr_fmt("LOG_DATA_ERROR", {"error": err}), CombatLogFormat.COLOR_BAD)
	if _screenshot_path != "":
		get_tree().create_timer(SCREENSHOT_TIMEOUT).timeout.connect(_take_screenshot_and_quit)
	_load_arena(_arena)
	_new_combat()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			_autoplay = true
		elif arg.begins_with("--arena="):
			var name := arg.trim_prefix("--arena=")
			if ARENAS.has(name):
				_arena = name
		elif arg.begins_with("--seed="):
			_seed_override = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--lang="):
			_lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")


func _load_arena(name: String) -> void:
	_arena = name
	_arena_data = ArenaLoader.read_file(ARENA_DIR.path_join(name + ".json"))
	_title.text = tr(JsonRead.get_str(_arena_data, "title_key"))
	_arena_select.select(ARENAS.find(name))


# --- Построение сцены ---------------------------------------------------------


func _setup_materials() -> void:
	_mat_floor.albedo_color = Color(0.42, 0.5, 0.3)
	_mat_high.albedo_color = Color(0.55, 0.5, 0.38)
	_mat_wall.albedo_color = Color(0.35, 0.3, 0.27)
	_mat_low.albedo_color = Color(0.5, 0.38, 0.24)
	_glow(_mat_reach, Color(0.55, 0.7, 0.45), Color(0.15, 0.25, 0.1))
	_glow(_mat_range, Color(0.5, 0.55, 0.75), Color(0.1, 0.12, 0.25))
	_glow(_mat_area, Color(0.85, 0.45, 0.35), Color(0.35, 0.1, 0.05))


func _glow(mat: StandardMaterial3D, albedo: Color, emission: Color) -> void:
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.7, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _setup_camera(grid: BattleGrid) -> void:
	var center := Vector3((grid.width - 1) * CELL / 2.0, 0.0, (grid.depth - 1) * CELL / 2.0)
	var camera := Camera3D.new()
	camera.name = "Camera"
	_world.add_child(camera)
	camera.fov = 50.0
	# Цель взгляда смещена к камере, чтобы поле не уходило под лог внизу экрана.
	_camera_target = center + Vector3(-1.5, 0.0, 2.0)
	_camera = camera
	_zoom = 1.1
	_place_camera()
	camera.current = true


func _pan_by_key(keycode: Key) -> void:
	match keycode:
		KEY_A, KEY_LEFT:
			_pan(Vector3(-PAN_STEP, 0.0, 0.0))
		KEY_D, KEY_RIGHT:
			_pan(Vector3(PAN_STEP, 0.0, 0.0))
		KEY_W, KEY_UP:
			_pan(Vector3(0.0, 0.0, -PAN_STEP))
		KEY_S, KEY_DOWN:
			_pan(Vector3(0.0, 0.0, PAN_STEP))


func _pan(delta: Vector3) -> void:
	if _state == null:
		return
	var grid := _state.grid
	var size := Vector3(grid.width * CELL, 0.0, grid.depth * CELL)
	_camera_target = (_camera_target + delta).clamp(-size * 0.25, size * 1.25)
	_place_camera()


## Камера смотрит на поле сверху-спереди; колесо мыши приближает и отдаляет,
## WASD, стрелки и средняя кнопка мыши двигают.
func _place_camera() -> void:
	if _camera == null:
		return
	_camera.position = _camera_target + CAMERA_OFFSET * _zoom
	_camera.look_at(_camera_target)


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

	var arena_row := HBoxContainer.new()
	box.add_child(arena_row)
	var arena_label := Label.new()
	arena_label.text = tr("UI_ARENA")
	arena_row.add_child(arena_label)
	for name in ARENAS:
		var data := ArenaLoader.read_file(ARENA_DIR.path_join(name + ".json"))
		_arena_select.add_item(tr(JsonRead.get_str(data, "title_key")))
	_arena_select.item_selected.connect(_on_arena_selected)
	arena_row.add_child(_arena_select)

	_initiative.anchor_left = 1.0
	_initiative.anchor_right = 1.0
	_initiative.offset_left = -640
	_initiative.offset_right = -12
	_initiative.offset_top = 12
	_initiative.alignment = FlowContainer.ALIGNMENT_END
	layer.add_child(_initiative)

	# Низ экрана: журнал слева, панель хода справа. Контейнер на весь экран
	# пропускает мышь к полю, а сам считает размеры панелей.
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bottom)
	_log = CombatLogPanel.new()
	_log.custom_minimum_size = Vector2(500, 0)
	_log.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(_log)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)
	_actions.custom_minimum_size = Vector2(520, 0)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_END
	_actions.action_pressed.connect(_on_action_pressed)
	_actions.end_turn_pressed.connect(_on_end_turn)
	bottom.add_child(_actions)

	_reaction_dialog = ReactionDialog.new()
	_reaction_dialog.anchor_left = 0.5
	_reaction_dialog.anchor_right = 0.5
	_reaction_dialog.offset_left = -220
	_reaction_dialog.offset_right = 220
	_reaction_dialog.offset_top = 120
	layer.add_child(_reaction_dialog)

	_preview.add_theme_color_override("font_outline_color", Color.BLACK)
	_preview.add_theme_constant_override("outline_size", 6)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	layer.add_child(_preview)


func _add_button(parent: Container, key: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = tr(key)
	button.pressed.connect(handler)
	parent.add_child(button)


func _rebuild_world() -> void:
	for child in _world.get_children():
		child.queue_free()
	_tiles.clear()
	_units.clear()
	_highlighted.clear()
	_area_cells.clear()
	var grid := _state.grid
	_setup_camera(grid)
	for z in grid.depth:
		for x in grid.width:
			_add_tile(grid, Vector2i(x, z))
	for c in _state.combatants:
		var view := UnitView.new()
		_world.add_child(view)
		var entry := _figures.entry(_template_id(c.id))
		view.setup(c.id, c.team, entry, _figures.instantiate(entry))
		view.place(_column_position(c.column))
		_units[c.id] = view
	for err in _figures.errors:
		push_error(err)
		_write(CombatLogFormat.tr_fmt("LOG_DATA_ERROR", {"error": err}), CombatLogFormat.COLOR_BAD)
	_figures.errors.clear()
	_face_enemies()
	_refresh()


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


## В начале боя каждый смотрит на середину противников.
func _face_enemies() -> void:
	for c in _state.combatants:
		var sum := Vector3.ZERO
		var count := 0
		for other in _state.combatants:
			if other.team != c.team:
				sum += _column_position(other.column)
				count += 1
		if count > 0:
			_units[c.id].face(sum / count)


func _add_tile(grid: BattleGrid, column: Vector2i) -> void:
	var blocked := grid.is_blocked(column)
	var low := grid.is_low_obstacle(column)
	var top := grid.level_at(column) * LEVEL_HEIGHT
	if blocked:
		top = LOW_OBSTACLE_HEIGHT if low else WALL_HEIGHT
	var height := top + 0.3
	var size := Vector3(CELL * 0.96, height, CELL * 0.96)

	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	tile.mesh = box
	tile.position = Vector3(column.x * CELL, top - height / 2.0, column.y * CELL)
	_world.add_child(tile)

	if blocked:
		tile.material_override = _mat_low if low else _mat_wall
		return
	_tiles[column] = tile
	_reset_tile(column)

	var body := StaticBody3D.new()
	body.set_meta("column", column)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	tile.add_child(body)


func _reset_tile(column: Vector2i) -> void:
	var high := _state.grid.level_at(column) > 0
	_tiles[column].material_override = _mat_high if high else _mat_floor


func _column_position(column: Vector2i) -> Vector3:
	var level := _state.grid.level_at(column)
	return Vector3(column.x * CELL, level * LEVEL_HEIGHT, column.y * CELL)


# --- Ход боя ------------------------------------------------------------------


func _new_combat() -> void:
	var seed_value := _seed_override if _seed_override >= 0 else randi()
	var errors: Array[String] = []
	_state = ArenaLoader.new_combat(_arena_data, seed_value, _db, errors)
	_log.clear()
	for err in errors:
		_write(CombatLogFormat.tr_fmt("LOG_DATA_ERROR", {"error": err}), CombatLogFormat.COLOR_BAD)
	_selected = null
	var events := _state.start()
	_rebuild_world()
	await _play_events(events)
	await _continue()


## Передаёт ход ИИ, пока не настанет ход игрока или бой не закончится.
func _continue() -> void:
	_busy = true
	_refresh()
	while not _state.ended and not _is_player_turn():
		await get_tree().create_timer(AI_STEP_DELAY).timeout
		var cmd := CombatAi.next_command(_state)
		await _execute(cmd)
	_busy = false
	_refresh()
	if _state.ended and _screenshot_path != "":
		await get_tree().create_timer(0.5).timeout
		_take_screenshot_and_quit()


func _is_player_turn() -> bool:
	var current := _state.current()
	return not _autoplay and current != null and current.player


## Проверяет и применяет команду. Возвращает true, если команда выполнена.
func _execute(cmd: CombatCommand) -> bool:
	var err := cmd.validate(_state)
	if err != "":
		_write(tr(err), Color(1.0, 0.75, 0.4))
		return false
	await _ask_reactions(cmd)
	await _play_events(cmd.apply(_state))
	return true


## Пробные прогоны команды на копии состояния: пока встречается реакция персонажа
## игрока без ответа — спрашиваем и дописываем ответ в команду (ADR-0023).
func _ask_reactions(cmd: CombatCommand) -> void:
	if _autoplay:
		return
	while true:
		var probe := CombatState.from_dict(_state.to_dict(), _state.grid)
		cmd.apply(probe)
		var prompt := probe.reactions.first_unanswered()
		if prompt == null:
			return
		var accepted: bool = await _ask_reaction(prompt)
		cmd.reactions.append(accepted)


func _ask_reaction(prompt: ReactionPrompt) -> bool:
	var reactor := _state.get_combatant(prompt.reactor)
	var target := _state.get_combatant(prompt.target)
	var source := _state.get_combatant(prompt.source)
	var names := {
		"reactor": CombatLogFormat.display_name(reactor),
		"target": CombatLogFormat.display_name(target),
		"source": CombatLogFormat.display_name(source),
	}
	var text := ""
	var detail := ""
	var yes := ""
	if prompt.kind == ReactionPrompt.OPPORTUNITY:
		text = CombatLogFormat.tr_fmt("UI_REACT_OPPORTUNITY", names)
		yes = tr("UI_REACT_STRIKE")
		var strike := MoveCommand.opportunity_action(reactor)
		if strike != null:
			detail = _preview_text(reactor, strike, target)
	else:
		text = CombatLogFormat.tr_fmt("UI_REACT_PROTECTION", names)
		detail = tr("UI_REACT_PROTECTION_DETAIL")
		yes = tr("UI_REACT_PROTECT")
	detail += ("\n" if detail != "" else "") + tr("UI_REACT_ONCE")
	for id: String in [prompt.reactor, prompt.target, prompt.source]:
		if _units.has(id):
			_units[id].set_hovered(true)
	_preview.visible = false
	_reaction_dialog.ask(text, detail, yes, tr("UI_REACT_SKIP"))
	var accepted: bool = await _reaction_dialog.answered
	for id: String in [prompt.reactor, prompt.target, prompt.source]:
		if _units.has(id):
			_units[id].set_hovered(id == _hovered_id)
	return accepted


func _player_command(cmd: CombatCommand) -> void:
	if _busy:
		return
	_busy = true
	_selected = null
	_preview.visible = false
	await _execute(cmd)
	_busy = false
	await _continue()


# --- Ввод ---------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null:
		if key.pressed and key.keycode == KEY_ESCAPE:
			_cancel_selection()
		elif key.pressed:
			_pan_by_key(key.keycode)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(Vector3(-motion.relative.x, 0.0, -motion.relative.y) * PAN_DRAG_SPEED * _zoom)
			return
		_on_hover(motion.position)
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		if click.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(ZOOM_MIN, _zoom - ZOOM_STEP)
			_place_camera()
		elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(ZOOM_MAX, _zoom + ZOOM_STEP)
			_place_camera()
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_selection()
		elif click.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(click.position)


func _on_left_click(screen_pos: Vector2) -> void:
	if _busy or _state.ended or not _is_player_turn():
		return
	var hit := _raycast(screen_pos)
	var actor := _state.current()
	var target := _hit_unit(hit)
	var cell := _hit_cell(hit, target)
	if _selected != null:
		_use_selected(actor, target, cell)
		return
	if target != null and target.team != actor.team:
		_auto_attack(actor, target)
	elif target == null and cell != NO_CELL:
		_player_command(MoveCommand.new(actor.id, cell))


func _hit_unit(hit: Dictionary) -> Combatant:
	if hit.has("unit_id"):
		return _state.get_combatant(str(hit["unit_id"]))
	if hit.has("column"):
		var column: Vector2i = hit["column"]
		return _state.combatant_at(column)
	return null


func _hit_cell(hit: Dictionary, unit: Combatant) -> Vector2i:
	if unit != null:
		return unit.column
	if hit.has("column"):
		var column: Vector2i = hit["column"]
		return column
	return NO_CELL


func _use_selected(actor: Combatant, target: Combatant, cell: Vector2i) -> void:
	var target_id := ""
	if _selected.target != ActionDef.TARGET_POINT:
		if target == null:
			return
		target_id = target.id
	_player_command(UseActionCommand.new(actor.id, _selected.id, target_id, cell))


## Лучшая доступная атака стоимостью «действие» по цели; null — нечем достать.
func _best_attack(actor: Combatant, target: Combatant) -> ActionDef:
	var best: ActionDef = null
	var best_value := -1
	for action in actor.actions:
		if action.kind != ActionDef.KIND_ATTACK and action.kind != ActionDef.KIND_MULTI:
			continue
		if action.cost != ActionDef.COST_ACTION:
			continue
		if ActionResolver.validate(_state, actor, action, target.id, NO_CELL) != "":
			continue
		var value := CombatAi.attack_value(_state, actor, action, target)
		# Расходуемое оружие — только если оно заметно лучше.
		if action.resource != "":
			value -= CombatAi.SCALE
		if value > best_value:
			best = action
			best_value = value
	return best


func _auto_attack(actor: Combatant, target: Combatant) -> void:
	var best := _best_attack(actor, target)
	if best == null:
		_write(tr(ActionResolver.ERR_OUT_OF_RANGE), Color(1.0, 0.75, 0.4))
		return
	_player_command(UseActionCommand.new(actor.id, best.id, target.id))


func _on_action_pressed(action_id: String) -> void:
	if _busy or not _is_player_turn():
		return
	var actor := _state.current()
	var action := actor.get_action(action_id)
	if _selected == action:
		_cancel_selection()
		return
	if action.target == ActionDef.TARGET_SELF:
		_player_command(UseActionCommand.new(actor.id, action.id, actor.id))
		return
	_selected = action
	_refresh()


func _cancel_selection() -> void:
	if _selected == null:
		return
	_selected = null
	_preview.visible = false
	_refresh()


## Наведение мыши: предпросмотр атаки или области, сведения об участнике.
func _on_hover(screen_pos: Vector2) -> void:
	if _state == null or _busy:
		_preview.visible = false
		return
	var hit := _raycast(screen_pos)
	var unit := _hit_unit(hit)
	var cell := _hit_cell(hit, unit)
	_set_hovered(unit.id if unit != null else "")
	var lines: PackedStringArray = []
	var actor := _state.current()
	_paint_area([])
	if _is_player_turn() and actor != null and not _state.ended:
		if _selected != null:
			lines.append_array(_selected_preview(actor, unit, cell))
		elif unit != null and unit.team != actor.team:
			var best := _best_attack(actor, unit)
			if best != null:
				lines.append(_preview_text(actor, best, unit))
	if unit != null:
		lines.append(_unit_info(unit))
	_preview.visible = not lines.is_empty()
	_preview.text = "\n".join(lines)
	# Прижимаем подсказку к краям экрана.
	var size := _preview.get_minimum_size()
	var view := get_viewport().get_visible_rect().size
	var pos := screen_pos + Vector2(18, 12)
	pos.x = minf(pos.x, view.x - size.x - 8)
	pos.y = minf(pos.y, view.y - size.y - 8)
	_preview.position = pos.max(Vector2(8, 8))


func _set_hovered(id: String) -> void:
	if id == _hovered_id:
		return
	if _units.has(_hovered_id):
		_units[_hovered_id].set_hovered(false)
	_hovered_id = id
	if _units.has(id):
		_units[id].set_hovered(true)


func _selected_preview(actor: Combatant, unit: Combatant, cell: Vector2i) -> PackedStringArray:
	var lines: PackedStringArray = []
	if _selected.target == ActionDef.TARGET_POINT:
		if cell == NO_CELL:
			return lines
		var err := ActionResolver.validate(_state, actor, _selected, "", cell)
		if err != "":
			lines.append(tr(err))
			return lines
		var cells: Array[Vector2i] = []
		if _selected.area == ActionDef.AREA_CONE:
			cells = Area.cone(_state.grid, actor.column, cell, _selected.area_size)
		else:
			cells = Area.burst(_state.grid, cell, _selected.area_size)
		_paint_area(cells)
		var names: PackedStringArray = []
		var ally_hit := false
		for t in ActionResolver.targets_in_area(_state, actor, _selected, cell):
			var p := ActionPreview.for_target(_state, actor, _selected, t, cell)
			names.append(
				(
					"%s %d%%%s"
					% [
						CombatLogFormat.display_name(t),
						p.chance,
						CombatLogFormat.cover_text(p.cover)
					]
				)
			)
			if t.team == actor.team:
				ally_hit = true
		lines.append(tr(_selected.name_key))
		lines.append(CombatLogFormat.tr_fmt("UI_PREVIEW_AREA", {"names": ", ".join(names)}))
		if ally_hit:
			lines.append(tr("UI_PREVIEW_AREA_ALLY"))
		return lines
	if unit == null:
		return lines
	var err := ActionResolver.validate(_state, actor, _selected, unit.id, NO_CELL)
	if err != "":
		lines.append(tr(err))
		return lines
	lines.append(_preview_text(actor, _selected, unit))
	return lines


func _preview_text(actor: Combatant, action: ActionDef, target: Combatant) -> String:
	var p := ActionPreview.for_target(_state, actor, action, target)
	var name := tr(action.name_key)
	var text := name
	match action.kind:
		ActionDef.KIND_ATTACK, ActionDef.KIND_MULTI:
			text = CombatLogFormat.tr_fmt(
				"UI_PREVIEW_ATTACK",
				{
					"action": name,
					"chance": p.chance,
					"min": p.damage_min,
					"max": p.damage_max,
					"crit": p.crit_max
				}
			)
		ActionDef.KIND_SAVE:
			var key := "UI_PREVIEW_SAVE" if p.damage_max > 0 else "UI_PREVIEW_SAVE_NODMG"
			text = CombatLogFormat.tr_fmt(
				key,
				{
					"action": name,
					"chance": p.chance,
					"dc": p.target_number,
					"min": p.damage_min,
					"max": p.damage_max
				}
			)
		ActionDef.KIND_HEAL:
			text = CombatLogFormat.tr_fmt(
				"UI_PREVIEW_HEAL", {"action": name, "min": p.heal_min, "max": p.heal_max}
			)
	text += CombatLogFormat.cover_text(p.cover)
	text += CombatLogFormat.reasons(p.mods.to_dict())
	if not p.defenses.is_empty():
		var defs: PackedStringArray = []
		for d in p.defenses:
			defs.append(tr("DEF_" + d.to_upper()))
		text += "\n" + CombatLogFormat.tr_fmt("UI_DEFENSES", {"list": ", ".join(defs)})
	return text


func _unit_info(c: Combatant) -> String:
	var text := CombatLogFormat.tr_fmt(
		"UI_UNIT_INFO",
		{
			"name": CombatLogFormat.display_name(c),
			"hp": c.hp,
			"max": c.max_hp,
			"ac": _state.effective_ac(c)
		}
	)
	var conds: PackedStringArray = []
	for cond in c.conditions:
		conds.append(CombatLogFormat.condition_name(cond.id))
	if not conds.is_empty():
		text += " · " + ", ".join(conds)
	return text


## Луч из камеры: возвращает {"unit_id": ...} или {"column": ...} или {}.
func _raycast(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit["collider"]
	if collider.has_meta("unit_id"):
		return {"unit_id": collider.get_meta("unit_id")}
	if collider.has_meta("column"):
		return {"column": collider.get_meta("column")}
	return {}


# --- События → анимация и лог -------------------------------------------------


func _play_events(events: Array[CombatEvent]) -> void:
	for e in events:
		match e.type:
			CombatEvent.MOVED:
				await _animate_move(e)
			CombatEvent.ACTION:
				await _animate_action(e)
			CombatEvent.ATTACK:
				await _animate_attack(e)
			CombatEvent.COMBAT_ENDED:
				_celebrate(JsonRead.get_str(e.data, "winner"))
		var line := CombatLogFormat.line(_state, e)
		if line.text != "":
			_write(line.text, line.color)
	_refresh()


func _animate_move(e: CombatEvent) -> void:
	var view := _units[JsonRead.get_str(e.data, "id")]
	_clear_highlight()
	view.walk(true)
	for cell: Variant in JsonRead.get_array(e.data, "path"):
		var xyz: Array = cell
		var column := Vector2i(JsonRead.to_int(xyz[0]), JsonRead.to_int(xyz[2]))
		var to := _column_position(column)
		view.face(to)
		var tween := create_tween()
		tween.tween_property(view, "position", to, MOVE_STEP_TIME)
		await tween.finished
		view.place(to)
	view.walk(false)


## Удар или выстрел: поворот к цели, анимация, вздрагивание цели при попадании.
func _animate_attack(e: CombatEvent) -> void:
	var actor := _state.get_combatant(JsonRead.get_str(e.data, "id"))
	var target_id := JsonRead.get_str(e.data, "target")
	if actor == null or not _units.has(actor.id) or not _units.has(target_id):
		return
	var view := _units[actor.id]
	var target_view := _units[target_id]
	view.face(target_view.position)
	var action := actor.get_action(JsonRead.get_str(e.data, "action"))
	var role := "melee"
	if action != null and action.attack_type == ActionDef.RANGED:
		role = "throw" if action.resource.begins_with("item_") else "ranged"
	await get_tree().create_timer(view.play(role)).timeout
	if JsonRead.get_bool(e.data, "hit"):
		target_view.flash()


## Заговоры и умения (атаки анимирует _animate_attack): поворот к цели или точке.
func _animate_action(e: CombatEvent) -> void:
	var actor := _state.get_combatant(JsonRead.get_str(e.data, "id"))
	if actor == null or not _units.has(actor.id):
		return
	var action := actor.get_action(JsonRead.get_str(e.data, "action"))
	if action == null or action.special != "":
		return
	if action.kind == ActionDef.KIND_ATTACK or action.kind == ActionDef.KIND_MULTI:
		return
	var view := _units[actor.id]
	var target_id := JsonRead.get_str(e.data, "target")
	if action.target == ActionDef.TARGET_POINT:
		var cell := JsonRead.to_vec2i(e.data.get("cell", []))
		view.face(_column_position(cell))
	elif _units.has(target_id) and target_id != actor.id:
		view.face(_units[target_id].position)
	var helpful := (
		action.kind == ActionDef.KIND_HEAL
		or action.target == ActionDef.TARGET_ALLY
		or action.target == ActionDef.TARGET_SELF
	)
	await get_tree().create_timer(view.play("support" if helpful else "cast")).timeout


func _celebrate(winner: String) -> void:
	for c in _state.combatants:
		if c.team == winner and c.is_alive() and _units.has(c.id):
			_units[c.id].play("victory")


func _refresh() -> void:
	for c in _state.combatants:
		if _units.has(c.id):
			_units[c.id].refresh(CombatLogFormat.display_name(c), c)
			_units[c.id].set_active(not _state.ended and c == _state.current())
	_initiative.refresh(_state)
	var current := _state.current()
	var player := not _busy and not _state.ended and _is_player_turn()
	_actions.refresh(_state, current, player, _selected.id if _selected != null else "")
	_clear_highlight()
	if current == null:
		return
	_turn_label.text = CombatLogFormat.tr_fmt(
		"UI_ROUND_TURN",
		{"round": _state.round_number, "name": CombatLogFormat.display_name(current)}
	)
	if not player:
		_hint.text = "" if _state.ended else tr("UI_AI_TURN")
		return
	if _selected != null:
		var hint_key := "UI_TARGET_ENEMY"
		if _selected.target == ActionDef.TARGET_ALLY:
			hint_key = "UI_TARGET_ALLY"
		elif _selected.target == ActionDef.TARGET_POINT:
			hint_key = "UI_TARGET_POINT"
		_hint.text = CombatLogFormat.tr_fmt(
			"UI_TARGETING", {"action": tr(_selected.name_key), "hint": tr(hint_key)}
		)
		_paint(Area.burst(_state.grid, current.column, _selected.max_range()), _mat_range)
		return
	_hint.text = tr("UI_HINT")
	var reach_cells: Array[Vector2i] = []
	for column: Vector2i in MoveCommand.reachable_for(_state, current):
		reach_cells.append(column)
	_paint(reach_cells, _mat_reach)


func _paint(cells: Array[Vector2i], mat: StandardMaterial3D) -> void:
	for column in cells:
		if _tiles.has(column):
			_tiles[column].material_override = mat
			_highlighted.append(column)


## Подсветка области под курсором поверх подсветки дальности.
func _paint_area(cells: Array[Vector2i]) -> void:
	for column in _area_cells:
		if not _tiles.has(column):
			continue
		if _highlighted.has(column):
			_tiles[column].material_override = _mat_range if _selected != null else _mat_reach
		else:
			_reset_tile(column)
	_area_cells = cells.duplicate()
	for column in cells:
		if _tiles.has(column):
			_tiles[column].material_override = _mat_area


func _clear_highlight() -> void:
	for column in _highlighted:
		if _tiles.has(column):
			_reset_tile(column)
	_highlighted.clear()
	_area_cells.clear()


func _write(text: String, color: Color = Color.WHITE) -> void:
	_log.write(text, color)


# --- Кнопки -------------------------------------------------------------------


func _on_end_turn() -> void:
	if _busy or _state.ended or not _is_player_turn():
		return
	_player_command(EndTurnCommand.new(_state.current().id))


func _on_save() -> void:
	if _busy:
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	var data := {"arena": _arena, "combat": _state.to_dict()}
	file.store_string(JSON.stringify(data, "  ", true))
	file.close()
	_write(tr("LOG_SAVED"), CombatLogFormat.COLOR_GOOD)


func _on_load() -> void:
	if _busy:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_write(tr("LOG_NO_SAVE"), Color(1.0, 0.75, 0.4))
		return
	var data: Dictionary = parsed
	var arena := JsonRead.get_str(data, "arena")
	if not ARENAS.has(arena):
		_write(tr("LOG_NO_SAVE"), Color(1.0, 0.75, 0.4))
		return
	_load_arena(arena)
	var loaded := CombatState.from_dict(
		JsonRead.get_dict(data, "combat"), ArenaLoader.grid_from(_arena_data)
	)
	if loaded == null:
		_write(tr("LOG_NO_SAVE"), Color(1.0, 0.75, 0.4))
		return
	_state = loaded
	_selected = null
	_rebuild_world()
	_write(tr("LOG_LOADED"), CombatLogFormat.COLOR_GOOD)
	await _continue()


func _on_restart() -> void:
	if _busy:
		return
	_new_combat()


func _on_arena_selected(index: int) -> void:
	if _busy:
		_arena_select.select(ARENAS.find(_arena))
		return
	_load_arena(ARENAS[index])
	_new_combat()


func _take_screenshot_and_quit() -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(_screenshot_path)
	print("Screenshot saved: %s" % _screenshot_path)
	get_tree().quit()
