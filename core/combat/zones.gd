class_name Zones
extends RefCounted
## Длящиеся зоны заклинаний (ADR-0046), например Лунный столп: держатся, пока заклинатель
## сосредоточен. Кто входит в зону или заканчивает в ней свой ход, подвергается действию
## заклинания — не чаще раза за ход (SRD 5.2). Зону двигает действие с "zone_of".
## Зона в CombatState.zones: {"source", "action", "cell": [x, y], "size", "level", "hit": [id…]}.


## Новая зона на месте сотворения; прежняя зона того же заклинателя и заклинания уходит.
## [param already_hit] — по кому заклинание уже сработало при сотворении.
static func create(
	state: CombatState,
	caster: Combatant,
	action: ActionDef,
	cell: Vector2i,
	already_hit: Array[Combatant]
) -> void:
	remove(state, caster.id, action.id)
	var hit: Array = []
	for c in already_hit:
		hit.append(c.id)
	(
		state
		. zones
		. append(
			{
				"source": caster.id,
				"action": action.id,
				"cell": [cell.x, cell.y],
				"size": action.area_size,
				"level": maxi(action.cast_level, action.spell_level),
				"hit": hit,
			}
		)
	)


## Зона из сохранения: числа — целые, ключи — в том же порядке, что у новой.
static func from_dict(data: Dictionary) -> Dictionary:
	var cell := JsonRead.to_vec2i(data.get("cell", [0, 0]))
	var hit: Array = []
	hit.assign(JsonRead.get_str_array(data, "hit"))
	return {
		"source": JsonRead.get_str(data, "source"),
		"action": JsonRead.get_str(data, "action"),
		"cell": [cell.x, cell.y],
		"size": JsonRead.get_int(data, "size"),
		"level": JsonRead.get_int(data, "level"),
		"hit": hit,
	}


static func remove(state: CombatState, caster_id: String, action_id: String) -> void:
	var kept: Array[Dictionary] = []
	for z in state.zones:
		if JsonRead.get_str(z, "source") != caster_id or JsonRead.get_str(z, "action") != action_id:
			kept.append(z)
	state.zones = kept


## Зона заклинателя для заклинания [param action_id]; пусто — нет.
static func find(state: CombatState, caster_id: String, action_id: String) -> Dictionary:
	for z in state.zones:
		if (
			JsonRead.get_str(z, "source") == caster_id
			and JsonRead.get_str(z, "action") == action_id
		):
			return z
	return {}


static func cells(state: CombatState, zone: Dictionary) -> Array[Vector2i]:
	var center := JsonRead.to_vec2i(zone.get("cell", [0, 0]))
	return Area.burst(state.grid, center, JsonRead.get_int(zone, "size"))


## Клетки всех зон (для подсветки поля).
static func all_cells(state: CombatState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in state.zones:
		for c in cells(state, z):
			if not out.has(c):
				out.append(c)
	return out


## Новый ход — «раз за ход» начинается заново.
static func new_turn(state: CombatState) -> void:
	for z in state.zones:
		z["hit"] = []


## Участник закончил ход в зоне.
static func end_turn(state: CombatState, c: Combatant, events: Array[CombatEvent]) -> void:
	for z: Dictionary in state.zones.duplicate():
		if c.is_present() and cells(state, z).has(c.column):
			_hit(state, z, c, events)


## Участник шагнул из [param from] в [param to]: вошёл в зону — заклинание срабатывает.
static func entered(
	state: CombatState, c: Combatant, from: Vector2i, to: Vector2i, events: Array[CombatEvent]
) -> void:
	for z: Dictionary in state.zones.duplicate():
		var area := cells(state, z)
		if area.has(to) and not area.has(from):
			_hit(state, z, c, events)


## Зону передвинули в [param cell]: срабатывает по всем, кто в ней оказался.
static func move(
	state: CombatState, zone: Dictionary, cell: Vector2i, events: Array[CombatEvent]
) -> void:
	zone["cell"] = [cell.x, cell.y]
	for c in state.sorted_combatants():
		if c.is_present() and cells(state, zone).has(c.column):
			_hit(state, zone, c, events)


## Входит ли шаг из [param from] в [param to] в какую-нибудь зону.
static func entering(state: CombatState, from: Vector2i, to: Vector2i) -> bool:
	for z in state.zones:
		var area := cells(state, z)
		if area.has(to) and not area.has(from):
			return true
	return false


static func _hit(
	state: CombatState, zone: Dictionary, c: Combatant, events: Array[CombatEvent]
) -> void:
	var hit: Array = zone.get("hit", [])
	if hit.has(c.id):
		return
	var caster := state.get_combatant(JsonRead.get_str(zone, "source"))
	if caster == null or not caster.is_alive():
		return
	var base := caster.get_action(JsonRead.get_str(zone, "action"))
	if base == null:
		return
	hit.append(c.id)
	zone["hit"] = hit
	var action := base.cast_with(JsonRead.get_int(zone, "level", base.spell_level))
	var center := JsonRead.to_vec2i(zone.get("cell", [0, 0]))
	var targets: Array[Combatant] = [c]
	ActionResolver.save_on(state, caster, action, targets, center, events)
