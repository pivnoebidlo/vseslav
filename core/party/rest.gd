class_name Rest
extends RefCounted
## Короткий и длинный отдых между боями (ADR-0027, docs/rules/rest.md).
## Короткий: тратить кости хитов по одной (кость + Тел, минимум 1), затем заряды
## по правилу класса. Длинный: каждый съедает день еды; сытый восстанавливает все
## хиты и все кости хитов (SRD 5.2); заряды восстанавливаются у всех живых.

## Правила восстановления ресурса (поле класса `recharge`).
const SHORT := "short"
const SHORT_ONE := "short_one"
const LONG := "long"
const RECHARGES: Array[String] = [SHORT, SHORT_ONE, LONG]

const ERR_DEAD := "err_rest_dead"
const ERR_NO_DICE := "err_rest_no_dice"
const ERR_FULL := "err_rest_full_hp"


## Итог одной кости хитов.
class HitDie:
	extends RefCounted
	var error: String = ""
	var roll: int = 0
	var con: int = 0
	var healed: int = 0


static func hit_die_size(db: RulesDb, hero_id: String) -> int:
	return JsonRead.get_int(_class_of(db, hero_id), "hit_die", 8)


static func hit_dice_left(db: RulesDb, party: Party, hero_id: String) -> int:
	var hero := party.build_hero(db, hero_id)
	if hero == null:
		return 0
	return maxi(hero.level - party.state_of(hero_id).hit_dice_spent, 0)


## Потратить одну кость хитов на коротком отдыхе.
static func spend_hit_die(db: RulesDb, party: Party, hero_id: String, rng: Rng) -> HitDie:
	var result := HitDie.new()
	var hero := party.build_hero(db, hero_id)
	var state := party.state_of(hero_id)
	if hero == null or state.dead:
		result.error = ERR_DEAD
	elif hero.level - state.hit_dice_spent <= 0:
		result.error = ERR_NO_DICE
	elif state.damage <= 0:
		result.error = ERR_FULL
	if result.error != "":
		return result
	result.roll = rng.roll(hit_die_size(db, hero_id))
	result.con = hero.abilities.modifier(Abilities.CON)
	result.healed = mini(maxi(result.roll + result.con, 1), state.damage)
	state.damage -= result.healed
	state.hit_dice_spent += 1
	return result


## Конец короткого отдыха: заряды «short» — все, «short_one» — по одному.
static func finish_short(db: RulesDb, party: Party) -> void:
	for id: String in party.inventories:
		var state := party.state_of(id)
		if state.dead:
			continue
		for key: String in state.spent.keys():
			match recharge_of(db, id, key):
				SHORT:
					state.spent.erase(key)
				SHORT_ONE:
					state.spent[key] -= 1
					if state.spent[key] <= 0:
						state.spent.erase(key)


## Длинный отдых. Возвращает id героев, которым не хватило еды (по порядку id).
static func long_rest(db: RulesDb, party: Party) -> Array[String]:
	var hungry: Array[String] = []
	var ids: Array[String] = []
	ids.assign(party.inventories.keys())
	ids.sort()
	for id in ids:
		var state := party.state_of(id)
		if state.dead:
			continue
		state.spent.clear()
		if _eat(db, party, id, ids):
			state.damage = 0
			state.hit_dice_spent = 0
		else:
			hungry.append(id)
	return hungry


static func recharge_of(db: RulesDb, hero_id: String, resource: String) -> String:
	var rules := JsonRead.get_dict(_class_of(db, hero_id), "recharge")
	return JsonRead.get_str(rules, resource, LONG)


## Проверка данных класса: правила восстановления.
static func validate_class(cls: Dictionary, errors: Array[String]) -> void:
	var rules := JsonRead.get_dict(cls, "recharge")
	for key: Variant in rules:
		var value := str(rules[key])
		if not RECHARGES.has(value):
			errors.append(
				"%s: unknown recharge '%s' for %s" % [JsonRead.get_str(cls, "id"), value, key]
			)


## Съесть день еды: из своего мешка, иначе у товарищей (по порядку id).
static func _eat(db: RulesDb, party: Party, hero_id: String, ids: Array[String]) -> bool:
	var order: Array[String] = [hero_id]
	for id in ids:
		if id != hero_id:
			order.append(id)
	for id in order:
		for s in party.inventories[id].bag:
			if not db.items.has(s.item):
				continue
			var item: Dictionary = db.items[s.item]
			if JsonRead.get_bool(item, "food"):
				party.inventories[id].remove(s.item, 1)
				return true
	return false


static func _class_of(db: RulesDb, hero_id: String) -> Dictionary:
	if not db.characters.has(hero_id):
		return {}
	var data: Dictionary = db.characters[hero_id]
	var class_id := JsonRead.get_str(data, "class")
	if not db.classes.has(class_id):
		return {}
	return db.classes[class_id]
