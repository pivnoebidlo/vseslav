class_name Party
extends RefCounted
## Герои между боями (ADR-0024, ADR-0027): инвентарь и состояние (раны, кости хитов,
## заряды) каждого персонажа по его id. Сохраняется отдельно от боя.

const FORMAT := 2
## Предел отряда (ADR-0038).
const MAX_MEMBERS := 6

var inventories: Dictionary[String, Inventory] = {}
var states: Dictionary[String, HeroState] = {}
## Кто сейчас в отряде, по порядку (ADR-0042); у остальных инвентарь и раны хранятся.
var members: Array[String] = []


## Партия по умолчанию: инвентари из данных персонажей, все здоровы.
static func from_db(db: RulesDb) -> Party:
	var party := Party.new()
	var ids := db.characters.keys()
	ids.sort()
	for key: Variant in ids:
		var id := str(key)
		party.inventories[id] = Inventory.from_dict(
			JsonRead.get_dict(db.characters[id], "inventory")
		)
		party.states[id] = HeroState.new()
		party._init_progress(db, id)
		if party.members.size() < MAX_MEMBERS:
			party.members.append(id)
	return party


## Принимает в отряд; false — уже в отряде, нет такого или отряд полон.
func join(character_id: String) -> bool:
	if members.has(character_id) or not inventories.has(character_id):
		return false
	if members.size() >= MAX_MEMBERS:
		return false
	members.append(character_id)
	return true


## Отпускает из отряда; последнего не отпустить.
func leave(character_id: String) -> bool:
	if not members.has(character_id) or members.size() <= 1:
		return false
	members.erase(character_id)
	return true


## Начальный состав из модуля (start.party); неизвестные id пропускаются.
func set_members(ids: Array[String]) -> void:
	var picked: Array[String] = []
	for id in ids:
		if inventories.has(id) and not picked.has(id) and picked.size() < MAX_MEMBERS:
			picked.append(id)
	if not picked.is_empty():
		members = picked


## Копия инвентаря героя для сборки бойца; null — героя нет.
func inventory_copy(character_id: String) -> Inventory:
	if not inventories.has(character_id):
		return null
	return Inventory.from_dict(inventories[character_id].to_dict())


func state_of(character_id: String) -> HeroState:
	if not states.has(character_id):
		states[character_id] = HeroState.new()
	return states[character_id]


## Боец героя с его снаряжением и состоянием (для экранов и отдыха); null — героя нет.
func build_hero(db: RulesDb, character_id: String) -> Combatant:
	if not db.characters.has(character_id) or not inventories.has(character_id):
		return null
	var errors: Array[String] = []
	var c := CombatantBuilder.from_character(
		db, character_data(db, character_id), errors, inventory_copy(character_id)
	)
	state_of(character_id).apply_to(c)
	return c


## После победы: снаряжение и состояние героев — как у их бойцов (брошенное и выпитое
## потрачено, раны и заряды остаются); упавшие встают с 1 хитом.
func take_from_combat(state: CombatState) -> void:
	for c in state.sorted_combatants():
		if c.inventory == null or not inventories.has(c.template):
			continue
		inventories[c.template] = Inventory.from_dict(c.inventory.to_dict())
		var before := state_of(c.template)
		var after := HeroState.from_combatant(c, before.hit_dice_spent, true)
		after.level = before.level
		after.xp = before.xp
		states[c.template] = after


## Данные персонажа с его нынешним уровнем (для сборки бойца).
func character_data(db: RulesDb, character_id: String) -> Dictionary:
	var data: Dictionary = db.characters[character_id].duplicate()
	if state_of(character_id).level > 0:
		data["level"] = state_of(character_id).level
	return data


## Уровень героя: повышенный или из данных.
func level_of(db: RulesDb, character_id: String) -> int:
	var state := state_of(character_id)
	if state.level > 0:
		return state.level
	var data: Dictionary = db.characters.get(character_id, {})
	return clampi(JsonRead.get_int(data, "level", 1), 1, Progression.LEVEL_CAP)


## Опыт всем, кто в отряде (каждому полностью, ADR-0043).
func give_xp(amount: int) -> void:
	if amount <= 0:
		return
	for id in members:
		state_of(id).xp += amount


func can_level_up(db: RulesDb, character_id: String) -> bool:
	var state := state_of(character_id)
	return Progression.can_level_up(db, level_of(db, character_id), state.xp)


## Повышает уровень на один; false — опыта не хватает или предел. Новые хиты
## приходят сразу (раны остаются ранами), кость хитов — тоже.
func level_up(db: RulesDb, character_id: String) -> bool:
	if not inventories.has(character_id) or not can_level_up(db, character_id):
		return false
	var state := state_of(character_id)
	state.level = level_of(db, character_id) + 1
	return true


## Опыт за победу: сумма xp существ противника из данных.
static func combat_xp(db: RulesDb, state: CombatState) -> int:
	var total := 0
	var heroes := ""
	for c in state.sorted_combatants():
		if c.player:
			heroes = c.team
			break
	for c in state.sorted_combatants():
		if c.team != heroes and db.creatures.has(c.template):
			total += maxi(JsonRead.get_int(db.creatures[c.template], "xp"), 0)
	return total


## Уровень и опыт из данных, если ещё не заданы (новый герой или старое сохранение).
func _init_progress(db: RulesDb, character_id: String) -> void:
	var state := state_of(character_id)
	if state.level <= 0:
		state.level = level_of(db, character_id)
	state.xp = maxi(state.xp, Progression.xp_for(db, state.level))


func to_dict() -> Dictionary:
	var heroes := {}
	var ids := inventories.keys()
	ids.sort()
	for key: Variant in ids:
		var id := str(key)
		heroes[id] = inventories[id].to_dict()
		heroes[id]["state"] = state_of(id).to_dict()
	return {"format": FORMAT, "heroes": heroes, "members": members.duplicate()}


## Сохранённая партия поверх партии по умолчанию: герои, которых нет в данных,
## отбрасываются; неверные инвентари (неизвестные предметы и т. п.) — тоже.
## Формат 1 (без состояния) читается; чужой формат — партия по умолчанию.
static func from_dict(data: Dictionary, db: RulesDb, errors: Array[String] = []) -> Party:
	var party := from_db(db)
	var format := JsonRead.get_int(data, "format")
	if format != FORMAT and format != 1:
		return party
	var heroes := JsonRead.get_dict(data, "heroes")
	for id: String in party.inventories:
		if not heroes.has(id):
			continue
		var raw: Variant = heroes[id]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var hero_data: Dictionary = raw
		var inv := Inventory.from_dict(hero_data)
		var problems: Array[String] = []
		inv.validate(db, id, problems)
		if problems.is_empty():
			party.inventories[id] = inv
		else:
			errors.append_array(problems)
		party.states[id] = HeroState.from_dict(JsonRead.get_dict(hero_data, "state"))
		party._init_progress(db, id)
	# Без состава (старые сохранения) — все по умолчанию.
	if data.has("members"):
		party.set_members(JsonRead.get_str_array(data, "members"))
	return party
