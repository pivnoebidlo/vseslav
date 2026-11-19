extends Node3D
## Сцена спайка этапа 0: пошаговый бой на тестовой арене.
## Представление только отображает CombatState и передаёт команды ядру (SPEC §6.2).
##
## Аргументы командной строки (после `--`):
##   --seed=N          фиксированный seed боя
##   --autoplay        за партию тоже играет ИИ (дымовая проверка)
##   --screenshot=PATH сохранить снимок экрана по окончании боя (или через 20 с) и выйти
##   --lang=ru|en      язык интерфейса (по умолчанию русский; меню настроек — позже)

const ARENA_PATH := "res://modules/spike/arenas/doroga.json"
const RULES_DIR := "res://modules/base/rules"
const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/spike_combat.json"
const PLAYER_TEAM := "party"
const CELL := BattleGrid.CELL_SIZE_M
const LEVEL_HEIGHT := 0.75
const AI_STEP_DELAY := 0.3
const MOVE_STEP_TIME := 0.12
const SCREENSHOT_TIMEOUT := 20.0
const DEFAULT_LANG := "ru"

var _arena_data: Dictionary = {}
var _db: RulesDb
var _state: CombatState
var _world: Node3D
var _tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _units: Dictionary[String, UnitView] = {}
var _reachable: Dictionary[Vector2i, int] = {}
var _busy := false
var _autoplay := false
var _seed_override := -1
var _screenshot_path := ""
var _lang := DEFAULT_LANG

var _mat_floor := StandardMaterial3D.new()
var _mat_high := StandardMaterial3D.new()
var _mat_wall := StandardMaterial3D.new()
var _mat_reach := StandardMaterial3D.new()

var _turn_label := Label.new()
var _move_label := Label.new()
var _log := RichTextLabel.new()


func _ready() -> void:
	_parse_args()
	TranslationServer.set_locale(_lang)
	_arena_data = ArenaLoader.read_file(ARENA_PATH)
	_db = RulesDb.load_dir(RULES_DIR)
	for err in _db.errors:
		push_error(err)
	_setup_materials()
	_setup_environment()
	_setup_ui()
	_world = Node3D.new()
	add_child(_world)
	if _screenshot_path != "":
		get_tree().create_timer(SCREENSHOT_TIMEOUT).timeout.connect(_take_screenshot_and_quit)
	_new_combat()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			_autoplay = true
		elif arg.begins_with("--seed="):
			_seed_override = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--lang="):
			_lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")


# --- Построение сцены ---------------------------------------------------------


func _setup_materials() -> void:
	_mat_floor.albedo_color = Color(0.42, 0.5, 0.3)
	_mat_high.albedo_color = Color(0.55, 0.5, 0.38)
	_mat_wall.albedo_color = Color(0.35, 0.3, 0.27)
	_mat_reach.albedo_color = Color(0.55, 0.7, 0.45)
	_mat_reach.emission_enabled = true
	_mat_reach.emission = Color(0.15, 0.25, 0.1)


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
	# Цель взгляда смещена к камере, чтобы поле не уходило под лог внизу экрана.
	var target := center + Vector3(0.0, 0.0, 2.5)
	camera.position = target + Vector3(0.0, 12.5, 8.0)
	camera.look_at(target)
	camera.current = true


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = tr("ARENA_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	box.add_child(_turn_label)
	box.add_child(_move_label)
	var hint := Label.new()
	hint.text = tr("UI_HINT")
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_add_button(buttons, "UI_END_TURN", _on_end_turn)
	_add_button(buttons, "UI_SAVE", _on_save)
	_add_button(buttons, "UI_LOAD", _on_load)
	_add_button(buttons, "UI_RESTART", _on_restart)

	_log.scroll_following = true
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(520, 220)
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = 12
	_log.offset_top = -232
	_log.offset_right = 532
	_log.offset_bottom = -12
	var log_bg := PanelContainer.new()
	log_bg.anchor_top = 1.0
	log_bg.anchor_bottom = 1.0
	log_bg.offset_left = 8
	log_bg.offset_top = -236
	log_bg.offset_right = 536
	log_bg.offset_bottom = -8
	layer.add_child(log_bg)
	layer.add_child(_log)


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
	var grid := _state.grid
	_setup_camera(grid)
	for z in grid.depth:
		for x in grid.width:
			_add_tile(grid, Vector2i(x, z))
	for c in _state.combatants:
		var view := UnitView.new()
		_world.add_child(view)
		view.setup(c.id, c.team)
		view.position = _column_position(c.column)
		if not c.is_alive():
			view.set_dead()
		_units[c.id] = view
	_refresh_labels()


func _add_tile(grid: BattleGrid, column: Vector2i) -> void:
	var blocked := grid.is_blocked(column)
	var top := 2.4 if blocked else grid.level_at(column) * LEVEL_HEIGHT
	var height := top + 0.3
	var size := Vector3(CELL * 0.96, height, CELL * 0.96)

	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	tile.mesh = box
	tile.position = Vector3(column.x * CELL, top - height / 2.0, column.y * CELL)
	_world.add_child(tile)

	if blocked:
		tile.material_override = _mat_wall
		return
	_tiles[column] = tile
	_reset_tile_material(column)

	var body := StaticBody3D.new()
	body.set_meta("column", column)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	tile.add_child(body)


func _reset_tile_material(column: Vector2i) -> void:
	var high := _state.grid.level_at(column) > 0
	_tiles[column].material_override = _mat_high if high else _mat_floor


func _column_position(column: Vector2i) -> Vector3:
	var level := _state.grid.level_at(column)
	return Vector3(column.x * CELL, level * LEVEL_HEIGHT, column.y * CELL)


# --- Ход боя ------------------------------------------------------------------


func _new_combat() -> void:
	var seed_value := _seed_override if _seed_override >= 0 else randi()
	_state = ArenaLoader.new_combat(_arena_data, seed_value, _db)
	_log.clear()
	var events := _state.start()
	_rebuild_world()
	await _play_events(events)
	await _continue()


## Передаёт ход ИИ, пока не настанет ход игрока или бой не закончится.
func _continue() -> void:
	_busy = true
	while not _state.ended and not _is_player_turn():
		await get_tree().create_timer(AI_STEP_DELAY).timeout
		var cmd := CombatAi.next_command(_state)
		await _execute(cmd)
	_busy = false
	_refresh_labels()
	if _state.ended and _screenshot_path != "":
		await get_tree().create_timer(0.5).timeout
		_take_screenshot_and_quit()


func _is_player_turn() -> bool:
	return not _autoplay and _state.current().player


## Проверяет и применяет команду. Возвращает true, если команда выполнена.
func _execute(cmd: CombatCommand) -> bool:
	var err := cmd.validate(_state)
	if err != "":
		_write(tr(err), Color(1.0, 0.75, 0.4))
		return false
	await _play_events(cmd.apply(_state))
	return true


func _player_command(cmd: CombatCommand) -> void:
	if _busy:
		return
	_busy = true
	await _execute(cmd)
	_busy = false
	await _continue()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _busy or _state.ended or not _is_player_turn():
		return
	var hit := _raycast(click.position)
	var actor := _state.current()
	if hit.has("unit_id"):
		var target := _state.get_combatant(str(hit["unit_id"]))
		if target != null and target.team != actor.team:
			_attack(actor, target)
		return
	if hit.has("column"):
		var column: Vector2i = hit["column"]
		var occupant := _state.combatant_at(column)
		if occupant != null and occupant.team != actor.team:
			_attack(actor, occupant)
		elif occupant == null:
			_player_command(MoveCommand.new(actor.id, column))


## Атака по цели самым сильным доступным действием (выбор действия — в UI боя, этап 1).
func _attack(actor: Combatant, target: Combatant) -> void:
	var best: ActionDef = null
	for action in actor.actions:
		if action.kind != ActionDef.KIND_ATTACK and action.kind != ActionDef.KIND_MULTI:
			continue
		var err := ActionResolver.validate(_state, actor, action, target.id, ActionResolver.NO_CELL)
		if err != "":
			continue
		var value := CombatAi.attack_value(_state, actor, action, target)
		if best == null or value > CombatAi.attack_value(_state, actor, best, target):
			best = action
	if best == null:
		_write(tr(ActionResolver.ERR_OUT_OF_RANGE), Color(1.0, 0.75, 0.4))
		return
	_player_command(UseActionCommand.new(actor.id, best.id, target.id))


## Луч из камеры: возвращает {"unit_id": ...} или {"column": ...} или {}.
func _raycast(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
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
			CombatEvent.INITIATIVE:
				_log_initiative(e)
			CombatEvent.TURN_STARTED:
				var c := _state.get_combatant(str(e.data["id"]))
				_write(tr("LOG_TURN").format({"name": _display_name(c)}), Color(0.8, 0.85, 1.0))
			CombatEvent.MOVED:
				await _animate_move(e)
			CombatEvent.ATTACK:
				_log_attack(e)
			CombatEvent.DOWNED, CombatEvent.DIED:
				var downed := _state.get_combatant(str(e.data["id"]))
				_units[downed.id].set_dead()
				_write(tr("LOG_DOWNED").format({"name": _display_name(downed)}), Color(1, 0.5, 0.5))
			CombatEvent.DAMAGE:
				var hurt := _state.get_combatant(str(e.data["id"]))
				_write(
					tr("LOG_DAMAGE").format(
						{"name": _display_name(hurt), "amount": JsonRead.get_int(e.data, "amount")}
					)
				)
			CombatEvent.COMBAT_ENDED:
				var won := str(e.data["winner"]) == PLAYER_TEAM
				_write(tr("LOG_WIN") if won else tr("LOG_LOSS"), Color(1, 0.9, 0.4))
	_refresh_labels()


func _animate_move(e: CombatEvent) -> void:
	var c := _state.get_combatant(str(e.data["id"]))
	var view := _units[c.id]
	_clear_reachable()
	for cell: Variant in JsonRead.get_array(e.data, "path"):
		var xyz: Array = cell
		var column := Vector2i(JsonRead.to_int(xyz[0]), JsonRead.to_int(xyz[2]))
		var tween := create_tween()
		tween.tween_property(view, "position", _column_position(column), MOVE_STEP_TIME)
		await tween.finished
	var cost := JsonRead.get_int(e.data, "cost")
	_write(tr("LOG_MOVED").format({"name": _display_name(c), "cost": cost}))


func _log_initiative(e: CombatEvent) -> void:
	var parts: PackedStringArray = []
	for item: Variant in JsonRead.get_array(e.data, "order"):
		var entry: Dictionary = item
		var c := _state.get_combatant(JsonRead.get_str(entry, "id"))
		parts.append("%s (%d)" % [_display_name(c), JsonRead.get_int(entry, "total")])
	_write(tr("LOG_INITIATIVE").format({"order": ", ".join(parts)}))


func _log_attack(e: CombatEvent) -> void:
	var actor := _state.get_combatant(JsonRead.get_str(e.data, "id"))
	var target := _state.get_combatant(JsonRead.get_str(e.data, "target"))
	var args := {
		"name": _display_name(actor),
		"target": _display_name(target),
		"natural": JsonRead.get_int(e.data, "natural"),
		"total": JsonRead.get_int(e.data, "total"),
		"ac": JsonRead.get_int(e.data, "target_ac"),
	}
	if JsonRead.get_bool(e.data, "critical"):
		_write(tr("LOG_CRIT").format(args), Color(1, 0.8, 0.3))
	elif JsonRead.get_bool(e.data, "hit"):
		_write(tr("LOG_HIT").format(args))
	else:
		_write(tr("LOG_MISS").format(args), Color(0.7, 0.7, 0.7))
	if JsonRead.get_bool(e.data, "hit"):
		_units[target.id].flash()


func _refresh_labels() -> void:
	for c in _state.combatants:
		if _units.has(c.id):
			_units[c.id].set_info(_display_name(c), c.hp, c.max_hp)
			_units[c.id].set_active(not _state.ended and c == _state.current())
	var current := _state.current()
	if current == null:
		return
	_turn_label.text = tr("UI_ROUND_TURN").format(
		{"round": _state.round_number, "name": _display_name(current)}
	)
	var action := tr("UI_ACTION_READY") if _state.actions_left > 0 else tr("UI_ACTION_USED")
	_move_label.text = tr("UI_MOVE_ACTION").format({"move": _state.movement_left, "action": action})
	_clear_reachable()
	if not _busy and not _state.ended and _is_player_turn():
		_reachable = MoveCommand.reachable_for(_state, current)
		for column in _reachable:
			if _tiles.has(column):
				_tiles[column].material_override = _mat_reach


func _clear_reachable() -> void:
	for column in _reachable:
		if _tiles.has(column):
			_reset_tile_material(column)
	_reachable.clear()


## Имя для показа: «Разбойник 2» для id вида razboynik_2.
func _display_name(c: Combatant) -> String:
	var name := tr(c.name_key)
	var suffix := c.id.get_slice("_", c.id.get_slice_count("_") - 1)
	if c.id.get_slice_count("_") > 1 and suffix.is_valid_int():
		name += " " + suffix
	return name


func _write(text: String, color: Color = Color.WHITE) -> void:
	_log.push_color(color)
	_log.add_text(text)
	_log.pop()
	_log.newline()


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
	file.store_string(JSON.stringify(_state.to_dict(), "  ", true))
	file.close()
	_write(tr("LOG_SAVED"), Color(0.6, 1, 0.6))


func _on_load() -> void:
	if _busy:
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	if text == "":
		_write(tr("LOG_NO_SAVE"), Color(1.0, 0.75, 0.4))
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_write(tr("LOG_NO_SAVE"), Color(1.0, 0.75, 0.4))
		return
	var data: Dictionary = parsed
	var loaded := CombatState.from_dict(data, ArenaLoader.grid_from(_arena_data))
	if loaded == null:
		_write(tr("LOG_NO_SAVE"), Color(1.0, 0.75, 0.4))
		return
	_state = loaded
	_rebuild_world()
	_write(tr("LOG_LOADED"), Color(0.6, 1, 0.6))
	await _continue()


func _on_restart() -> void:
	if _busy:
		return
	_new_combat()


func _take_screenshot_and_quit() -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(_screenshot_path)
	print("Screenshot saved: %s" % _screenshot_path)
	get_tree().quit()
