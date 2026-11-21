class_name Party
extends RefCounted
## Герои между боями (ADR-0024, ADR-0027): инвентарь и состояние (раны, кости хитов,
## заряды) каждого персонажа по его id. Сохраняется отдельно от боя.

const FORMAT := 2

var inventories: Dictionary[String, Inventory] = {}
var states: Dictionary[String, HeroState] = {}


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
	return party


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
		db, db.characters[character_id], errors, inventory_copy(character_id)
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
		var before := state_of(c.template).hit_dice_spent
		states[c.template] = HeroState.from_combatant(c, before, true)


func to_dict() -> Dictionary:
	var heroes := {}
	var ids := inventories.keys()
	ids.sort()
	for key: Variant in ids:
		var id := str(key)
		heroes[id] = inventories[id].to_dict()
		heroes[id]["state"] = state_of(id).to_dict()
	return {"format": FORMAT, "heroes": heroes}


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
	return party
