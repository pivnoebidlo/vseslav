class_name Market
extends RefCounted
## Купцы модуля и их состояние между визитами (ADR-0025): что осталось в запасе,
## сколько денег. Исходные купцы — из данных модуля, сохранённое состояние — поверх.

const FORMAT := 1

var merchants: Dictionary[String, Merchant] = {}
## Порядок купцов как в данных.
var order: Array[String] = []


## Купцы из данных модуля ({"merchants": [...]}). Ошибки — в [param errors].
static func from_data(data: Dictionary, db: RulesDb, errors: Array[String] = []) -> Market:
	var market := Market.new()
	for raw: Variant in JsonRead.get_array(data, "merchants"):
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("merchant entry is not an object")
			continue
		var entry: Dictionary = raw
		var m := Merchant.from_dict(entry)
		var problems: Array[String] = []
		m.validate(db, problems)
		if not problems.is_empty() or market.merchants.has(m.id):
			errors.append_array(problems)
			if market.merchants.has(m.id):
				errors.append("duplicate merchant '%s'" % m.id)
			continue
		market.merchants[m.id] = m
		market.order.append(m.id)
	return market


func get_merchant(id: String) -> Merchant:
	return merchants.get(id, null)


## Состояние купцов: запас и деньги.
func to_dict() -> Dictionary:
	var state := {}
	for id in order:
		var m := merchants[id]
		state[id] = {"goods": ItemStack.to_array(m.goods.bag), "purse": m.goods.purse}
	return {"format": FORMAT, "merchants": state}


## Накладывает сохранённое состояние; купцы, которых нет в данных, и неверные
## записи пропускаются, чужой формат — игнорируется.
func apply_saved(data: Dictionary, db: RulesDb) -> void:
	if JsonRead.get_int(data, "format") != FORMAT:
		return
	var state := JsonRead.get_dict(data, "merchants")
	for id in order:
		if not state.has(id) or typeof(state[id]) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = state[id]
		var goods := Inventory.from_dict(
			{"bag": entry.get("goods", []), "purse": entry.get("purse", 0)}
		)
		var problems: Array[String] = []
		goods.validate(db, id, problems)
		if problems.is_empty():
			merchants[id].goods = goods
