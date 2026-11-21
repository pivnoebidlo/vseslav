class_name Loot
extends RefCounted
## Добыча после победы (ADR-0026): всё, что было на павших противниках (`carries`),
## плюс случайная добыча из их таблицы (`loot`: деньги формулой, вещи с шансом в %),
## плюс половина брошенного героями метательного оружия. Делят вручную.


## Куча добычи (мешок и кошелёк) после боя [param state]; пустая, если победили не герои.
## [param before] — снаряжение партии до боя (сколько метательного было),
## [param rng] — отдельный генератор, чтобы не трогать состояние боя.
static func collect(state: CombatState, db: RulesDb, before: Party, rng: Rng) -> Inventory:
	var pile := Inventory.new()
	var heroes := _player_team(state)
	if heroes == "" or state.winner != heroes:
		return pile
	for c in state.sorted_combatants():
		if c.team == heroes or c.is_standing() or not db.creatures.has(c.template):
			continue
		var data: Dictionary = db.creatures[c.template]
		for v: Variant in JsonRead.get_array(data, "carries"):
			var s := ItemStack.from_value(v)
			if s != null:
				pile.add(s.item, s.count)
		_roll_table(JsonRead.get_dict(data, "loot"), pile, rng)
	_recover_thrown(state, before, pile)
	return pile


## Проверка данных существа: вещи при нём и таблица добычи.
static func validate_creature(db: RulesDb, data: Dictionary, errors: Array[String]) -> void:
	var id := JsonRead.get_str(data, "id")
	for v: Variant in JsonRead.get_array(data, "carries"):
		var s := ItemStack.from_value(v)
		if s == null or not db.items.has(s.item):
			errors.append("%s: carries unknown item %s" % [id, str(v)])
	var table := JsonRead.get_dict(data, "loot")
	var money := JsonRead.get_str(table, "money")
	if money != "" and not Formula.parse(money).is_valid():
		errors.append("%s: bad loot money formula '%s'" % [id, money])
	for v: Variant in JsonRead.get_array(table, "items"):
		if typeof(v) != TYPE_DICTIONARY:
			errors.append("%s: loot item is not an object" % id)
			continue
		var entry: Dictionary = v
		var item_id := JsonRead.get_str(entry, "item")
		var chance := JsonRead.get_int(entry, "chance", 100)
		if not db.items.has(item_id):
			errors.append("%s: loot has unknown item '%s'" % [id, item_id])
		if chance < 1 or chance > 100 or JsonRead.get_int(entry, "count", 1) < 1:
			errors.append("%s: loot '%s' needs chance 1..100 and count >= 1" % [id, item_id])


static func _roll_table(table: Dictionary, pile: Inventory, rng: Rng) -> void:
	var money := JsonRead.get_str(table, "money")
	if money != "":
		var vars: Dictionary[String, int] = {}
		pile.purse += maxi(Formula.parse(money).roll(rng, vars), 0)
	for v: Variant in JsonRead.get_array(table, "items"):
		var entry: Dictionary = v
		if rng.roll(100) <= JsonRead.get_int(entry, "chance", 100):
			pile.add(JsonRead.get_str(entry, "item"), JsonRead.get_int(entry, "count", 1))


## Половина брошенного метательного оружия (вниз) находится на поле боя.
static func _recover_thrown(state: CombatState, before: Party, pile: Inventory) -> void:
	for c in state.sorted_combatants():
		if c.inventory == null or not before.inventories.has(c.template):
			continue
		var seen: Array[String] = []
		for a in c.actions:
			if not a.consumes or a.kind != ActionDef.KIND_ATTACK or seen.has(a.item):
				continue
			seen.append(a.item)
			var thrown := (
				before.inventories[c.template].count_of(a.item) - c.inventory.count_of(a.item)
			)
			pile.add(a.item, IntMath.floor_div(maxi(thrown, 0), 2))


## Команда персонажей игрока; пусто — таких нет.
static func _player_team(state: CombatState) -> String:
	for c in state.sorted_combatants():
		if c.player:
			return c.team
	return ""
