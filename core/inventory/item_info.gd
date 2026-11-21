class_name ItemInfo
extends RefCounted
## Свойства предметов из данных правил и грузоподъёмность (docs/rules/items.md).

## Грузоподъёмность SRD 5.2 (средний размер): нести — Сила × 15 фунтов,
## тащить — Сила × 30; вес хранится в десятых долях фунта.
const CARRY_PER_STR := 150
const DRAG_PER_STR := 300


static func _item(db: RulesDb, item_id: String) -> Dictionary:
	if not db.items.has(item_id):
		return {}
	return db.items[item_id]


static func item_type(db: RulesDb, item_id: String) -> String:
	return JsonRead.get_str(_item(db, item_id), "type")


static func has_property(db: RulesDb, item_id: String, prop: String) -> bool:
	return JsonRead.get_str_array(_item(db, item_id), "properties").has(prop)


## Вес одного предмета в десятых долях фунта (в данных — фунты, можно с половинами).
static func weight(db: RulesDb, item_id: String) -> int:
	var raw: Variant = _item(db, item_id).get("weight", 0)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return 0
	# Перевод при чтении данных: половины фунта точны в двоичной записи.
	var pounds: float = raw
	return maxi(roundi(pounds * 10.0), 0)


static func price(db: RulesDb, item_id: String) -> int:
	return maxi(JsonRead.get_int(_item(db, item_id), "price"), 0)


## На пояс — только то, что пригодится в бою: оружие и расходники.
static func fits_belt(db: RulesDb, item_id: String) -> bool:
	var t := item_type(db, item_id)
	return t == "weapon" or t == "consumable"


static func carry_limit(strength: int) -> int:
	return maxi(strength, 0) * CARRY_PER_STR


static func drag_limit(strength: int) -> int:
	return maxi(strength, 0) * DRAG_PER_STR
