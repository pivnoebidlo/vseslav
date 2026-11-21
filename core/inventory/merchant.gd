class_name Merchant
extends RefCounted
## Купец (ADR-0025): свой запас и кошелёк, наценка при продаже герою, доля цены
## при покупке у героя, какие типы предметов берёт. Данные — в модуле.

var id: String = ""
var name_key: String = ""
## Герой платит цену × [member markup] / 100.
var markup: int = 100
## Купец платит за предмет цену × [member buyback] / 100 (SRD: половина).
var buyback: int = 50
## Какие типы предметов купец покупает; пусто — любые.
var buys: Array[String] = []
## Запас — мешок, деньги — кошелёк.
var goods: Inventory = Inventory.new()


func price_to_buy(db: RulesDb, item_id: String) -> int:
	return IntMath.floor_div(ItemInfo.price(db, item_id) * markup + 99, 100)


func price_to_sell(db: RulesDb, item_id: String) -> int:
	return IntMath.floor_div(ItemInfo.price(db, item_id) * buyback, 100)


func wants(db: RulesDb, item_id: String) -> bool:
	return buys.is_empty() or buys.has(ItemInfo.item_type(db, item_id))


func validate(db: RulesDb, errors: Array[String]) -> void:
	if id == "":
		errors.append("merchant without id")
	if markup < 1 or buyback < 0 or buyback > markup:
		errors.append("%s: markup must be >= 1 and buyback in 0..markup" % id)
	for s in goods.bag:
		if not db.items.has(s.item):
			errors.append("%s: unknown item '%s'" % [id, s.item])


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name_key": name_key,
		"markup": markup,
		"buyback": buyback,
		"buys": buys.duplicate(),
		"goods": ItemStack.to_array(goods.bag),
		"purse": goods.purse,
	}


static func from_dict(data: Dictionary) -> Merchant:
	var m := Merchant.new()
	m.id = JsonRead.get_str(data, "id")
	m.name_key = JsonRead.get_str(data, "name_key", m.id)
	m.markup = JsonRead.get_int(data, "markup", 100)
	m.buyback = JsonRead.get_int(data, "buyback", 50)
	m.buys = JsonRead.get_str_array(data, "buys")
	m.goods = Inventory.from_dict({"bag": data.get("goods", []), "purse": data.get("purse", 0)})
	return m
