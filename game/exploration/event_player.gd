class_name EventPlayer
extends PanelContainer
## Исполняет запросы событий в сцене исследования по порядку (ADR-0042). Сообщения
## показывает сам (окно с кнопкой «Дальше»), уведомления о вещах и составе — строкой
## подсказки; диалог, бой и перенос просит у сцены сигналами. После диалога сцена
## зовёт [method resume]; бой и перенос очередь заканчивают.

signal notice(text: String)
signal dialog_requested(dialog_id: String, speaker: String)
signal combat_requested(encounter_id: String)
signal teleport_requested(area_id: String, spawn: String)
## Очередь пуста: сцена обновляет жителей, отряд, журнал.
signal finished

## (id предмета) → название; (id персонажа) → имя.
var item_name: Callable
var hero_name: Callable

var _queue: Array[Dictionary] = []
var _waiting := false
var _text := Label.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.1, 0.09, 0.08, 0.97), UiStyle.ACTIVE.darkened(0.3), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -40
	custom_minimum_size = Vector2(620, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(580, 0)
	_text.add_theme_font_size_override("font_size", 18)
	box.add_child(_text)
	var next := Button.new()
	next.text = tr("UI_EV_NEXT")
	next.size_flags_horizontal = Control.SIZE_SHRINK_END
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(
		func() -> void:
			visible = false
			_waiting = false
			_next()
	)
	box.add_child(next)


## Идёт ли что-то (сообщение на экране или ждём конца диалога).
func is_busy() -> bool:
	return _waiting or not _queue.is_empty()


func play(requests: Array[Dictionary]) -> void:
	_queue.append_array(requests)
	if not _waiting:
		_next()


## Диалог, запрошенный событием, закончился — дальше по очереди.
func resume() -> void:
	if _waiting and not visible:
		_waiting = false
		_next()


func _next() -> void:
	while not _queue.is_empty():
		var r: Dictionary = _queue.pop_front()
		if r.has("notice"):
			notice.emit(_notice_text(r))
			continue
		match JsonRead.get_str(r, "action"):
			EventActions.MESSAGE:
				_text.text = tr(JsonRead.get_str(r, "text"))
				visible = true
				_waiting = true
				return
			EventActions.START_DIALOG:
				_waiting = true
				dialog_requested.emit(JsonRead.get_str(r, "dialog"), JsonRead.get_str(r, "speaker"))
				return
			EventActions.START_COMBAT:
				_queue.clear()
				combat_requested.emit(JsonRead.get_str(r, "encounter"))
				break
			EventActions.TELEPORT:
				_queue.clear()
				teleport_requested.emit(JsonRead.get_str(r, "area"), JsonRead.get_str(r, "spawn"))
				break
	finished.emit()


func _notice_text(r: Dictionary) -> String:
	match JsonRead.get_str(r, "notice"):
		EventActions.NOTICE_ITEM, EventActions.NOTICE_LOST:
			var key := (
				"LOG_EV_ITEM" if r["notice"] == EventActions.NOTICE_ITEM else "LOG_EV_ITEM_LOST"
			)
			var item := str(item_name.call(JsonRead.get_str(r, "item")))
			return CombatLogFormat.tr_fmt(
				key, {"item": item, "count": JsonRead.get_int(r, "count", 1)}
			)
		EventActions.NOTICE_MONEY:
			var kuny := JsonRead.get_int(r, "kuny")
			var key := "LOG_EV_MONEY" if kuny >= 0 else "LOG_EV_MONEY_LOST"
			return CombatLogFormat.tr_fmt(key, {"money": EquipmentScreen.money_text(absi(kuny))})
		EventActions.NOTICE_XP:
			return CombatLogFormat.tr_fmt("LOG_EV_XP", {"amount": JsonRead.get_int(r, "amount")})
		EventActions.NOTICE_JOINED, EventActions.NOTICE_LEFT:
			var key := (
				"LOG_EV_JOINED" if r["notice"] == EventActions.NOTICE_JOINED else "LOG_EV_LEFT"
			)
			return CombatLogFormat.tr_fmt(
				key, {"name": str(hero_name.call(JsonRead.get_str(r, "character")))}
			)
	return ""
