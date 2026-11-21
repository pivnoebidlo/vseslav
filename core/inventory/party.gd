class_name Party
extends RefCounted
## Снаряжение героев между боями (ADR-0024): инвентарь каждого персонажа по его id.
## Сохраняется отдельно от боя; после боя потраченное списывается.

const FORMAT := 1

var inventories: Dictionary[String, Inventory] = {}


## Партия по умолчанию: инвентари из данных персонажей.
static func from_db(db: RulesDb) -> Party:
	var party := Party.new()
	var ids := db.characters.keys()
	ids.sort()
	for key: Variant in ids:
		var id := str(key)
		party.inventories[id] = Inventory.from_dict(
			JsonRead.get_dict(db.characters[id], "inventory")
		)
	return party


## Копия инвентаря героя для сборки бойца; null — героя нет.
func inventory_copy(character_id: String) -> Inventory:
	if not inventories.has(character_id):
		return null
	return Inventory.from_dict(inventories[character_id].to_dict())


## После боя: инвентари героев — как у их бойцов (брошенное и выпитое потрачено).
func take_from_combat(state: CombatState) -> void:
	for c in state.sorted_combatants():
		if c.inventory != null and inventories.has(c.template):
			inventories[c.template] = Inventory.from_dict(c.inventory.to_dict())


func to_dict() -> Dictionary:
	var heroes := {}
	var ids := inventories.keys()
	ids.sort()
	for key: Variant in ids:
		var id := str(key)
		heroes[id] = inventories[id].to_dict()
	return {"format": FORMAT, "heroes": heroes}


## Сохранённая партия поверх партии по умолчанию: герои, которых нет в данных,
## отбрасываются; неверные инвентари (неизвестные предметы и т. п.) — тоже.
## Чужой формат — партия по умолчанию.
static func from_dict(data: Dictionary, db: RulesDb, errors: Array[String] = []) -> Party:
	var party := from_db(db)
	if JsonRead.get_int(data, "format") != FORMAT:
		return party
	var heroes := JsonRead.get_dict(data, "heroes")
	for id: String in party.inventories:
		if not heroes.has(id):
			continue
		var raw: Variant = heroes[id]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var inv_data: Dictionary = raw
		var inv := Inventory.from_dict(inv_data)
		var problems: Array[String] = []
		inv.validate(db, id, problems)
		if problems.is_empty():
			party.inventories[id] = inv
		else:
			errors.append_array(problems)
	return party
