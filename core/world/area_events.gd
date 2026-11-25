class_name AreaEvents
extends RefCounted
## Какие события области пора исполнить (ADR-0042). Чистая логика: игра спрашивает
## при входе в область и когда ведущий переходит в другую клетку.


## Флаг «событие уже было» (для однократных).
static func fired_flag(area_id: String, event_id: String) -> String:
	return "event.%s.%s" % [area_id, event_id]


## События [param on] (enter_area, enter_zone или trigger_entered), условия которых
## выполнены, а однократные ещё не срабатывали. Для зон — если [param cell] внутри
## зоны события; для триггеров — внутри зоны триггера [member AreaMap.AreaEvent.source].
## Порядок — как в файле области.
static func due(
	area: AreaMap, on: String, cell: Vector2i, flags: WorldFlags
) -> Array[AreaMap.AreaEvent]:
	var result: Array[AreaMap.AreaEvent] = []
	for ev in area.events:
		if ev.on != on:
			continue
		if on == AreaMap.AreaEvent.ON_ENTER_ZONE and not ev.zone.has_point(cell):
			continue
		if on == AreaMap.AreaEvent.ON_TRIGGER_ENTERED:
			var trigger := area.get_trigger(ev.source)
			if trigger == null or not trigger.zone.has_point(cell):
				continue
		if ev.once and flags.get_flag(fired_flag(area.id, ev.id)) == true:
			continue
		if not flags.all_match(ev.conditions):
			continue
		result.append(ev)
	return result


## Исполняет событие: отмечает однократное и применяет действия.
static func fire(area: AreaMap, ev: AreaMap.AreaEvent, ctx: EventContext) -> void:
	if ev.once:
		ctx.flags.set_flag(fired_flag(area.id, ev.id), true)
	EventActions.run(ev.actions, ctx)


## Жители, которые сейчас на месте (условия появления выполнены).
static func present_npcs(area: AreaMap, flags: WorldFlags) -> Array[AreaMap.Npc]:
	var result: Array[AreaMap.Npc] = []
	for npc in area.npcs:
		if flags.all_match(npc.conditions):
			result.append(npc)
	return result
