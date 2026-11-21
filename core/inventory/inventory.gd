class_name Inventory
extends RefCounted
## Снаряжение и мешок одного героя (ADR-0024, docs/rules/items.md):
## доспех, две руки, пояс на [constant BELT_SIZE] мест, мешок и кошелёк в кунах.
## Все операции возвращают пустую строку или ключ ошибки и ничего не меняют при ошибке.

const SLOT_ARMOR := "armor"
const SLOT_MAIN := "main_hand"
const SLOT_OFF := "off_hand"
const SLOTS: Array[String] = [SLOT_ARMOR, SLOT_MAIN, SLOT_OFF]
const BELT_SIZE := 4
## Грузоподъёмность SRD 5.2 (средний размер): нести — Сила × 15 фунтов,
## тащить — Сила × 30; вес хранится в десятых долях фунта.
const CARRY_PER_STR := 150
const DRAG_PER_STR := 300

const ERR_UNKNOWN_ITEM := "err_item_unknown"
const ERR_NOT_HERE := "err_item_not_here"
const ERR_WRONG_SLOT := "err_item_wrong_slot"
const ERR_HANDS_BUSY := "err_item_hands_busy"
const ERR_BELT_FULL := "err_item_belt_full"
const ERR_NOT_FOR_BELT := "err_item_not_for_belt"
const ERR_TOO_HEAVY := "err_item_too_heavy"
const ERR_NO_MONEY := "err_item_no_money"

var armor: String = ""
var main_hand: String = ""
var off_hand: String = ""
var belt: Array[ItemStack] = []
var bag: Array[ItemStack] = []
var purse: int = 0

# --- Свойства предметов ---------------------------------------------------------


static func _item(db: RulesDb, item_id: String) -> Dictionary:
	if not db.items.has(item_id):
		return {}
	return db.items[item_id]


static func item_type(db: RulesDb, item_id: String) -> String:
	return JsonRead.get_str(_item(db, item_id), "type")


static func has_property(db: RulesDb, item_id: String, prop: String) -> bool:
	return JsonRead.get_str_array(_item(db, item_id), "properties").has(prop)


## Вес одного предмета в десятых долях фунта (в данных — фунты, можно с половинами).
static func item_weight(db: RulesDb, item_id: String) -> int:
	var raw: Variant = _item(db, item_id).get("weight", 0)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return 0
	# Перевод при чтении данных: половины фунта точны в двоичной записи.
	var pounds: float = raw
	return maxi(roundi(pounds * 10.0), 0)


static func item_price(db: RulesDb, item_id: String) -> int:
	return maxi(JsonRead.get_int(_item(db, item_id), "price"), 0)


## На пояс — только то, что пригодится в бою: оружие и расходники.
static func fits_belt(db: RulesDb, item_id: String) -> bool:
	var t := item_type(db, item_id)
	return t == "weapon" or t == "consumable"


# --- Запросы --------------------------------------------------------------------


func slot_item(slot: String) -> String:
	match slot:
		SLOT_ARMOR:
			return armor
		SLOT_MAIN:
			return main_hand
		SLOT_OFF:
			return off_hand
	return ""


## Сколько таких предметов всего: в руках, на доспехе, на поясе и в мешке.
func count_of(item_id: String) -> int:
	var n := _count_in(bag, item_id) + _count_in(belt, item_id)
	for slot in SLOTS:
		if slot_item(slot) == item_id:
			n += 1
	return n


func belt_count(item_id: String) -> int:
	return _count_in(belt, item_id)


func bag_count(item_id: String) -> int:
	return _count_in(bag, item_id)


## Общий вес в десятых долях фунта.
func weight(db: RulesDb) -> int:
	var total := 0
	for slot in SLOTS:
		total += item_weight(db, slot_item(slot))
	for s in belt:
		total += item_weight(db, s.item) * s.count
	for s in bag:
		total += item_weight(db, s.item) * s.count
	return total


static func carry_limit(strength: int) -> int:
	return maxi(strength, 0) * CARRY_PER_STR


static func drag_limit(strength: int) -> int:
	return maxi(strength, 0) * DRAG_PER_STR


func two_handed_in_main(db: RulesDb) -> bool:
	return main_hand != "" and has_property(db, main_hand, "two_handed")


# --- Изменения ------------------------------------------------------------------


## Кладёт предметы в мешок (стопкой с такими же).
func add(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	_add_to(bag, item_id, count)


## Убирает [param count] предметов из мешка, затем с пояса. false — столько нет.
func remove(item_id: String, count: int = 1) -> bool:
	if bag_count(item_id) + belt_count(item_id) < count:
		return false
	var from_bag := mini(bag_count(item_id), count)
	_take_from(bag, item_id, from_bag)
	_take_from(belt, item_id, count - from_bag)
	return true


## Надеть или взять в руку предмет из мешка или с пояса. Прежний предмет слота — в мешок.
func equip(db: RulesDb, item_id: String, slot: String) -> String:
	if not db.items.has(item_id):
		return ERR_UNKNOWN_ITEM
	if bag_count(item_id) + belt_count(item_id) <= 0:
		return ERR_NOT_HERE
	var err := _check_slot(db, item_id, slot)
	if err != "":
		return err
	if bag_count(item_id) > 0:
		_take_from(bag, item_id, 1)
	else:
		_take_from(belt, item_id, 1)
	var previous := slot_item(slot)
	if previous != "":
		_add_to(bag, previous, 1)
	_set_slot(slot, item_id)
	return ""


## Снять предмет из слота в мешок.
func unequip(slot: String) -> String:
	var item_id := slot_item(slot)
	if item_id == "":
		return ERR_NOT_HERE
	_set_slot(slot, "")
	_add_to(bag, item_id, 1)
	return ""


## Переложить все такие предметы из мешка на пояс.
func to_belt(db: RulesDb, item_id: String) -> String:
	if not fits_belt(db, item_id):
		return ERR_NOT_FOR_BELT
	var n := bag_count(item_id)
	if n <= 0:
		return ERR_NOT_HERE
	if belt_count(item_id) == 0 and belt.size() >= BELT_SIZE:
		return ERR_BELT_FULL
	_take_from(bag, item_id, n)
	_add_to(belt, item_id, n)
	return ""


## Снять стопку с пояса в мешок.
func from_belt(item_id: String) -> String:
	var n := belt_count(item_id)
	if n <= 0:
		return ERR_NOT_HERE
	_take_from(belt, item_id, n)
	_add_to(bag, item_id, n)
	return ""


## Передать предметы из мешка другому герою (в его мешок). Получатель должен
## суметь это хотя бы тащить: вес не больше Силы × 30.
func give(
	db: RulesDb, item_id: String, count: int, other: Inventory, other_strength: int
) -> String:
	if count <= 0 or bag_count(item_id) < count:
		return ERR_NOT_HERE
	var added := item_weight(db, item_id) * count
	if other.weight(db) + added > drag_limit(other_strength):
		return ERR_TOO_HEAVY
	_take_from(bag, item_id, count)
	other.add(item_id, count)
	return ""


func give_money(kuny: int, other: Inventory) -> String:
	if kuny <= 0 or kuny > purse:
		return ERR_NO_MONEY
	purse -= kuny
	other.purse += kuny
	return ""


# --- Проверка и запись ----------------------------------------------------------


## Ошибки данных: неизвестные предметы, не тот слот, переполненный пояс.
func validate(db: RulesDb, owner_id: String, errors: Array[String]) -> void:
	for slot in SLOTS:
		var item_id := slot_item(slot)
		if item_id == "":
			continue
		if not db.items.has(item_id):
			errors.append("%s: unknown item '%s'" % [owner_id, item_id])
			continue
		var err := _check_slot(db, item_id, slot)
		if err != "":
			errors.append("%s: %s cannot go to %s (%s)" % [owner_id, item_id, slot, err])
	if belt.size() > BELT_SIZE:
		errors.append("%s: belt holds at most %d stacks" % [owner_id, BELT_SIZE])
	for s in belt:
		if not db.items.has(s.item):
			errors.append("%s: unknown item '%s'" % [owner_id, s.item])
		elif not fits_belt(db, s.item):
			errors.append("%s: %s cannot go on the belt" % [owner_id, s.item])
	for s in bag:
		if not db.items.has(s.item):
			errors.append("%s: unknown item '%s'" % [owner_id, s.item])


func to_dict() -> Dictionary:
	var d := {"belt": _stacks_to_array(belt), "bag": _stacks_to_array(bag), "purse": purse}
	for slot in SLOTS:
		if slot_item(slot) != "":
			d[slot] = slot_item(slot)
	return d


static func from_dict(data: Dictionary) -> Inventory:
	var inv := Inventory.new()
	inv.armor = JsonRead.get_str(data, SLOT_ARMOR)
	inv.main_hand = JsonRead.get_str(data, SLOT_MAIN)
	inv.off_hand = JsonRead.get_str(data, SLOT_OFF)
	for v: Variant in JsonRead.get_array(data, "belt"):
		var s := ItemStack.from_value(v)
		if s != null:
			_add_to(inv.belt, s.item, s.count)
	for v: Variant in JsonRead.get_array(data, "bag"):
		var s := ItemStack.from_value(v)
		if s != null:
			_add_to(inv.bag, s.item, s.count)
	inv.purse = maxi(JsonRead.get_int(data, "purse"), 0)
	return inv


# --- Внутреннее -----------------------------------------------------------------


func _check_slot(db: RulesDb, item_id: String, slot: String) -> String:
	var t := item_type(db, item_id)
	var fits := false
	var hands_busy := false
	match slot:
		SLOT_ARMOR:
			fits = t == "armor"
		SLOT_MAIN:
			fits = t == "weapon"
			hands_busy = has_property(db, item_id, "two_handed") and off_hand != ""
		SLOT_OFF:
			fits = t == "shield" or (t == "weapon" and has_property(db, item_id, "light"))
			hands_busy = two_handed_in_main(db)
	if not fits:
		return ERR_WRONG_SLOT
	return ERR_HANDS_BUSY if hands_busy else ""


func _set_slot(slot: String, item_id: String) -> void:
	match slot:
		SLOT_ARMOR:
			armor = item_id
		SLOT_MAIN:
			main_hand = item_id
		SLOT_OFF:
			off_hand = item_id


static func _count_in(stacks: Array[ItemStack], item_id: String) -> int:
	for s in stacks:
		if s.item == item_id:
			return s.count
	return 0


static func _add_to(stacks: Array[ItemStack], item_id: String, count: int) -> void:
	if count <= 0:
		return
	for s in stacks:
		if s.item == item_id:
			s.count += count
			return
	stacks.append(ItemStack.new(item_id, count))


static func _take_from(stacks: Array[ItemStack], item_id: String, count: int) -> void:
	if count <= 0:
		return
	for i in stacks.size():
		if stacks[i].item == item_id:
			stacks[i].count -= count
			if stacks[i].count <= 0:
				stacks.remove_at(i)
			return


static func _stacks_to_array(stacks: Array[ItemStack]) -> Array:
	var result: Array = []
	for s in stacks:
		result.append(s.to_value())
	return result
