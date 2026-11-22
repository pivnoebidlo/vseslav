class_name CombatSession
extends Node
## Пошаговый бой поверх любой сцены (арена или карта, ADR-0032): ход ИИ, команды
## игрока, вопросы о реакциях, анимации событий, броски кубиков, журнал, панель хода
## и инициатива. Представление только отображает CombatState и передаёт команды ядру
## (SPEC §6.2). Поле — CombatBoard, фигуры — UnitView, которые даёт хозяин сцены.

## Бой закончен (после анимаций). [param winner] — сторона-победитель.
signal ended(winner: String)
## Строка хода и подсказка — хозяин сцены показывает их у себя.
signal status_changed(turn_text: String, hint_text: String)
## Начался ход участника — например, навести на него камеру.
signal turn_started(combatant_id: String)

const AI_STEP_DELAY := 0.3
const MOVE_STEP_TIME := 0.22
const NO_CELL := ActionResolver.NO_CELL
const WARN := Color(1.0, 0.75, 0.4)

## За партию тоже играет ИИ и не спрашивает о реакциях (дымовая проверка).
var autoplay := false
## Показывать кубики (в дымовых проверках — нет).
var dice_enabled := true
var state: CombatState
var units: Dictionary[String, UnitView] = {}
var board: CombatBoard

var _selected: ActionDef = null
var _busy := false
var _active := false
var _hovered_id := ""
var _winner_team := ""
var _path_preview := PathPreview.new()
var _ui := Control.new()
var _preview := Label.new()
# Виджеты с текстом создаются в setup(): к этому времени язык уже выбран.
var _initiative: InitiativeBar
var _actions: ActionBar
var _log: CombatLogPanel
var _reaction_dialog: ReactionDialog
var _dice: DiceRoll


## Интерфейс боя — в [param layer]; клетки — [param p_board]; путь под курсором —
## в [param world].
func setup(layer: CanvasLayer, p_board: CombatBoard, world: Node3D) -> void:
	board = p_board
	_initiative = InitiativeBar.new()
	_actions = ActionBar.new()
	_log = CombatLogPanel.new()
	_reaction_dialog = ReactionDialog.new()
	_dice = DiceRoll.new()
	world.add_child(_path_preview)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_initiative.anchor_left = 1.0
	_initiative.anchor_right = 1.0
	_initiative.offset_left = -640
	_initiative.offset_right = -12
	_initiative.offset_top = 12
	_initiative.alignment = FlowContainer.ALIGNMENT_END
	_ui.add_child(_initiative)
	# Низ экрана: журнал слева, панель хода справа. Контейнер на весь экран
	# пропускает мышь к полю, а сам считает размеры панелей.
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bottom)
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
	_actions.item_pressed.connect(_on_item_pressed)
	bottom.add_child(_actions)
	_reaction_dialog.anchor_left = 0.5
	_reaction_dialog.anchor_right = 0.5
	_reaction_dialog.offset_left = -220
	_reaction_dialog.offset_right = 220
	_reaction_dialog.offset_top = 120
	_ui.add_child(_reaction_dialog)
	_preview.add_theme_color_override("font_outline_color", Color.BLACK)
	_preview.add_theme_constant_override("outline_size", 6)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_ui.add_child(_preview)
	_ui.add_child(_dice)


## Начать бой: события начала (инициатива), затем ходы до хода игрока.
func start(p_state: CombatState) -> void:
	state = p_state
	_selected = null
	_active = true
	var events := state.start()
	_refresh()
	await play_events(events)
	await run()


## Продолжить загруженный бой.
func resume(p_state: CombatState) -> void:
	state = p_state
	_selected = null
	_active = true
	await run()


## Бой больше не принимает ввод (сцена ушла из боя).
func stop() -> void:
	_active = false
	_selected = null
	_preview.visible = false
	_path_preview.clear()
	if board != null:
		board.clear()


func is_active() -> bool:
	return _active


func is_busy() -> bool:
	return _busy


## Можно ли сохраниться посреди боя: ход игрока, ничего не происходит.
func can_save() -> bool:
	return state != null and not _busy and not state.ended and _is_player_turn()


func show_ui(on: bool) -> void:
	_ui.visible = on


func write(text: String, color: Color = Color.WHITE) -> void:
	_log.write(text, color)


func clear_log() -> void:
	_log.clear()


func hide_preview() -> void:
	_preview.visible = false


# --- Ход боя ------------------------------------------------------------------


## Передаёт ход ИИ, пока не настанет ход игрока или бой не закончится.
func run() -> void:
	_busy = true
	_refresh()
	while _active and not state.ended and not _is_player_turn():
		await get_tree().create_timer(AI_STEP_DELAY).timeout
		var cmd := CombatAi.next_command(state)
		await _execute(cmd)
	_busy = false
	_refresh()
	if _active and state.ended:
		_active = false
		_path_preview.clear()
		ended.emit(_winner_team)


func _is_player_turn() -> bool:
	var current := state.current()
	return not autoplay and current != null and current.player


## Проверяет и применяет команду. Возвращает true, если команда выполнена.
func _execute(cmd: CombatCommand) -> bool:
	var err := cmd.validate(state)
	if err != "":
		write(tr(err), WARN)
		return false
	await _ask_reactions(cmd)
	await play_events(cmd.apply(state))
	return true


## Пробные прогоны команды на копии состояния: пока встречается реакция персонажа
## игрока без ответа — спрашиваем и дописываем ответ в команду (ADR-0023).
func _ask_reactions(cmd: CombatCommand) -> void:
	if autoplay:
		return
	while true:
		var probe := CombatState.from_dict(state.to_dict(), state.grid)
		cmd.apply(probe)
		var prompt := probe.reactions.first_unanswered()
		if prompt == null:
			return
		var accepted: bool = await _ask_reaction(prompt)
		cmd.reactions.append(accepted)


func _ask_reaction(prompt: ReactionPrompt) -> bool:
	var reactor := state.get_combatant(prompt.reactor)
	var target := state.get_combatant(prompt.target)
	var source := state.get_combatant(prompt.source)
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
			detail = CombatHints.preview_text(state, reactor, strike, target)
	else:
		text = CombatLogFormat.tr_fmt("UI_REACT_PROTECTION", names)
		detail = tr("UI_REACT_PROTECTION_DETAIL")
		yes = tr("UI_REACT_PROTECT")
	detail += ("\n" if detail != "" else "") + tr("UI_REACT_ONCE")
	for id: String in [prompt.reactor, prompt.target, prompt.source]:
		if units.has(id):
			units[id].set_hovered(true)
	_preview.visible = false
	_reaction_dialog.ask(text, detail, yes, tr("UI_REACT_SKIP"))
	var accepted: bool = await _reaction_dialog.answered
	for id: String in [prompt.reactor, prompt.target, prompt.source]:
		if units.has(id):
			units[id].set_hovered(id == _hovered_id)
	return accepted


func _player_command(cmd: CombatCommand) -> void:
	if _busy:
		return
	_busy = true
	_selected = null
	_preview.visible = false
	_path_preview.clear()
	await _execute(cmd)
	_busy = false
	await run()


# --- Ввод ---------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not _active or state == null:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_cancel_selection()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_hover(motion.position)
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		if click.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_selection()
		elif click.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(click.position)


func _on_left_click(screen_pos: Vector2) -> void:
	if _busy or state.ended or not _is_player_turn():
		return
	var hit := _raycast(screen_pos)
	var actor := state.current()
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
		return state.get_combatant(str(hit["unit_id"]))
	if hit.has("column"):
		var column: Vector2i = hit["column"]
		return state.combatant_at(column)
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


func _auto_attack(actor: Combatant, target: Combatant) -> void:
	var best := CombatHints.best_attack(state, actor, target)
	if best == null:
		write(tr(ActionResolver.ERR_OUT_OF_RANGE), WARN)
		return
	_player_command(UseActionCommand.new(actor.id, best.id, target.id))


func _on_action_pressed(action_id: String) -> void:
	if _busy or not _is_player_turn():
		return
	var actor := state.current()
	var action := actor.get_action(action_id)
	if _selected == action:
		_cancel_selection()
		return
	if action.target == ActionDef.TARGET_SELF:
		_player_command(UseActionCommand.new(actor.id, action.id, actor.id))
		return
	_selected = action
	_refresh()


func _on_item_pressed(item_id: String, op: String) -> void:
	if _busy or not _is_player_turn():
		return
	_cancel_selection()
	_player_command(ItemCommand.new(state.current().id, item_id, op))


func _on_end_turn() -> void:
	if _busy or state.ended or not _is_player_turn():
		return
	_player_command(EndTurnCommand.new(state.current().id))


func _cancel_selection() -> void:
	if _selected == null:
		return
	_selected = null
	_preview.visible = false
	_refresh()


## Наведение мыши: путь, предпросмотр атаки или области, сведения об участнике.
func _on_hover(screen_pos: Vector2) -> void:
	if _busy:
		_preview.visible = false
		_path_preview.clear()
		return
	var hit := _raycast(screen_pos)
	var unit := _hit_unit(hit)
	var cell := _hit_cell(hit, unit)
	_set_hovered(unit.id if unit != null else "")
	var lines: PackedStringArray = []
	var actor := state.current()
	var area: Array[Vector2i] = []
	var player := _is_player_turn() and actor != null and not state.ended
	if player:
		var walk_to := cell if _selected == null and unit == null else NO_CELL
		_path_preview.show_combat(state, actor, walk_to, board.position_of)
		if _selected != null:
			lines.append_array(
				CombatHints.selected_preview(state, actor, _selected, unit, cell, area)
			)
		elif unit != null and unit.team != actor.team:
			var best := CombatHints.best_attack(state, actor, unit)
			if best != null:
				lines.append(CombatHints.preview_text(state, actor, best, unit))
	else:
		_path_preview.clear()
	board.paint_area(area)
	if unit != null:
		lines.append(CombatHints.unit_info(state, unit))
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
	if units.has(_hovered_id):
		units[_hovered_id].set_hovered(false)
	_hovered_id = id
	if units.has(id):
		units[id].set_hovered(true)


## Луч из камеры: {"unit_id": ...} (участник этого боя), {"column": ...} или {}.
func _raycast(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit["collider"]
	var unit_id := str(collider.get_meta("unit_id", ""))
	if unit_id != "" and state.get_combatant(unit_id) != null:
		return {"unit_id": unit_id}
	if collider.has_meta("column"):
		return {"column": collider.get_meta("column")}
	var at: Vector3 = hit["position"]
	var cell := board.column_at(at)
	return {"column": cell} if cell != NO_CELL else {}


# --- События → анимация, кубики и лог -------------------------------------------


func play_events(events: Array[CombatEvent]) -> void:
	for e in events:
		match e.type:
			CombatEvent.MOVED:
				await _animate_move(e)
			CombatEvent.ACTION:
				await _animate_action(e)
			CombatEvent.ATTACK:
				await _roll_attack(e)
				await _animate_attack(e)
			CombatEvent.SAVE:
				await _roll_save(e)
			CombatEvent.TURN_STARTED:
				turn_started.emit(JsonRead.get_str(e.data, "id"))
			CombatEvent.COMBAT_ENDED:
				_winner_team = JsonRead.get_str(e.data, "winner")
				_celebrate(_winner_team)
		var line := CombatLogFormat.line(state, e)
		if line.text != "":
			write(line.text, line.color)
	_refresh()


func _roll_attack(e: CombatEvent) -> void:
	if not dice_enabled or autoplay:
		return
	var d := e.data
	var actor := state.get_combatant(JsonRead.get_str(d, "id"))
	var target := state.get_combatant(JsonRead.get_str(d, "target"))
	var action := actor.get_action(JsonRead.get_str(d, "action")) if actor != null else null
	var bonus := JsonRead.get_int(d, "bonus")
	var total := JsonRead.get_int(d, "total")
	var hit := JsonRead.get_bool(d, "hit")
	var outcome := "UI_DICE_MISS"
	if JsonRead.get_bool(d, "critical"):
		outcome = "UI_DICE_CRIT"
	elif hit:
		outcome = "UI_DICE_HIT"
	var title := (
		tr("UI_DICE_ATTACK")
		. format(
			{
				"name": CombatLogFormat.display_name(actor),
				"target": CombatLogFormat.display_name(target),
				"action": tr(action.name_key) if action != null else "",
			}
		)
	)
	var text := (
		tr("UI_DICE_VS_AC")
		. format(
			{
				"natural": total - bonus,
				"mod": DiceText.modifier(bonus),
				"total": total,
				"ac": JsonRead.get_int(d, "target_ac"),
				"outcome": tr(outcome),
			}
		)
	)
	_dice.play(title, _rolls(d), total - bonus, text, hit == (actor != null and actor.player))
	await _dice.finished


func _roll_save(e: CombatEvent) -> void:
	var d := e.data
	if not dice_enabled or autoplay or JsonRead.get_bool(d, "auto_fail"):
		return
	var saver := state.get_combatant(JsonRead.get_str(d, "id"))
	var mod := JsonRead.get_int(d, "modifier")
	var total := JsonRead.get_int(d, "total")
	var success := JsonRead.get_bool(d, "success")
	var title := (
		tr("UI_DICE_SAVE")
		. format(
			{
				"name": CombatLogFormat.display_name(saver),
				"ability": tr("ABIL_" + JsonRead.get_str(d, "ability").to_upper()),
			}
		)
	)
	var text := (
		tr("UI_DICE_VS_DC")
		. format(
			{
				"natural": total - mod,
				"mod": DiceText.modifier(mod),
				"total": total,
				"dc": JsonRead.get_int(d, "dc"),
				"outcome": tr("UI_DICE_SUCCESS" if success else "UI_DICE_FAIL"),
			}
		)
	)
	_dice.play(title, _rolls(d), total - mod, text, success == (saver != null and saver.player))
	await _dice.finished


func _rolls(d: Dictionary) -> Array[int]:
	var rolls: Array[int] = []
	for r: Variant in JsonRead.get_array(d, "rolls"):
		rolls.append(JsonRead.to_int(r))
	return rolls


func _animate_move(e: CombatEvent) -> void:
	var id := JsonRead.get_str(e.data, "id")
	if not units.has(id):
		return
	var view := units[id]
	board.clear()
	view.walk(true)
	for cell: Variant in JsonRead.get_array(e.data, "path"):
		var xyz: Array = cell
		var column := Vector2i(JsonRead.to_int(xyz[0]), JsonRead.to_int(xyz[2]))
		var to := board.position_of(column)
		view.face(to)
		var tween := create_tween()
		tween.tween_property(view, "position", to, MOVE_STEP_TIME)
		await tween.finished
		view.place(to)
	view.walk(false)


## Удар или выстрел: поворот к цели, анимация, вздрагивание цели при попадании.
func _animate_attack(e: CombatEvent) -> void:
	var actor := state.get_combatant(JsonRead.get_str(e.data, "id"))
	var target_id := JsonRead.get_str(e.data, "target")
	if actor == null or not units.has(actor.id) or not units.has(target_id):
		return
	var view := units[actor.id]
	var target_view := units[target_id]
	view.face(target_view.position)
	var action := actor.get_action(JsonRead.get_str(e.data, "action"))
	var role := "melee"
	if action != null and action.attack_type == ActionDef.RANGED:
		role = "throw" if action.consumes else "ranged"
	await get_tree().create_timer(view.play(role)).timeout
	if JsonRead.get_bool(e.data, "hit"):
		target_view.flash()


## Заговоры и умения (атаки анимирует _animate_attack): поворот к цели или точке.
func _animate_action(e: CombatEvent) -> void:
	var actor := state.get_combatant(JsonRead.get_str(e.data, "id"))
	if actor == null or not units.has(actor.id):
		return
	var action := actor.get_action(JsonRead.get_str(e.data, "action"))
	if action == null or action.special != "":
		return
	if action.kind == ActionDef.KIND_ATTACK or action.kind == ActionDef.KIND_MULTI:
		return
	var view := units[actor.id]
	var target_id := JsonRead.get_str(e.data, "target")
	if action.target == ActionDef.TARGET_POINT:
		var cell := JsonRead.to_vec2i(e.data.get("cell", []))
		view.face(board.position_of(cell))
	elif units.has(target_id) and target_id != actor.id:
		view.face(units[target_id].position)
	var helpful := (
		action.kind == ActionDef.KIND_HEAL
		or action.target == ActionDef.TARGET_ALLY
		or action.target == ActionDef.TARGET_SELF
	)
	await get_tree().create_timer(view.play("support" if helpful else "cast")).timeout


func _celebrate(winner: String) -> void:
	for c in state.combatants:
		if c.team == winner and c.is_alive() and units.has(c.id):
			units[c.id].play("victory")


## В начале боя каждый смотрит на середину противников.
func face_enemies() -> void:
	for c in state.combatants:
		var sum := Vector3.ZERO
		var count := 0
		for other in state.combatants:
			if other.team != c.team:
				sum += board.position_of(other.column)
				count += 1
		if count > 0 and units.has(c.id):
			units[c.id].face(sum / count)


func _refresh() -> void:
	if state == null:
		return
	for c in state.combatants:
		if units.has(c.id):
			units[c.id].refresh(CombatLogFormat.display_name(c), c)
			units[c.id].set_active(not state.ended and c == state.current())
	_initiative.refresh(state)
	var current := state.current()
	var player := _active and not _busy and not state.ended and _is_player_turn()
	_actions.refresh(state, current, player, _selected.id if _selected != null else "")
	board.clear()
	if current == null:
		return
	var turn := CombatLogFormat.tr_fmt(
		"UI_ROUND_TURN",
		{"round": state.round_number, "name": CombatLogFormat.display_name(current)}
	)
	if not player:
		status_changed.emit(turn, "" if state.ended else tr("UI_AI_TURN"))
		return
	if _selected != null:
		var hint_key := "UI_TARGET_ENEMY"
		if _selected.target == ActionDef.TARGET_ALLY:
			hint_key = "UI_TARGET_ALLY"
		elif _selected.target == ActionDef.TARGET_POINT:
			hint_key = "UI_TARGET_POINT"
		status_changed.emit(
			turn,
			CombatLogFormat.tr_fmt(
				"UI_TARGETING", {"action": tr(_selected.name_key), "hint": tr(hint_key)}
			)
		)
		board.paint(
			Area.burst(state.grid, current.column, _selected.max_range()), CombatBoard.Paint.RANGE
		)
		return
	status_changed.emit(turn, tr("UI_HINT"))
	var reach_cells: Array[Vector2i] = []
	for column: Vector2i in MoveCommand.reachable_for(state, current):
		reach_cells.append(column)
	board.paint(reach_cells, CombatBoard.Paint.REACH)
