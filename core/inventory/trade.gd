class_name Trade
extends RefCounted
## Купля-продажа между героем и купцом (ADR-0025). Герой покупает в мешок
## и продаёт из мешка; деньги — из кошелька этого героя. При ошибке ничего не меняется.

const ERR_NO_MONEY := "err_trade_no_money"
const ERR_MERCHANT_NO_MONEY := "err_trade_merchant_no_money"
const ERR_NOT_BUYING := "err_trade_not_buying"
const ERR_WORTHLESS := "err_trade_worthless"


## Купить [param count] предметов у купца. [param strength] — Сила героя: больше,
## чем он может тащить (Сила × 30), не купить.
static func buy(
	db: RulesDb, merchant: Merchant, hero: Inventory, strength: int, item_id: String, count: int = 1
) -> String:
	if count <= 0 or merchant.goods.bag_count(item_id) < count:
		return Inventory.ERR_NOT_HERE
	var cost := merchant.price_to_buy(db, item_id) * count
	if hero.purse < cost:
		return ERR_NO_MONEY
	if hero.weight(db) + ItemInfo.weight(db, item_id) * count > ItemInfo.drag_limit(strength):
		return Inventory.ERR_TOO_HEAVY
	merchant.goods.remove(item_id, count)
	hero.add(item_id, count)
	hero.purse -= cost
	merchant.goods.purse += cost
	return ""


## Продать [param count] предметов из мешка героя.
static func sell(
	db: RulesDb, merchant: Merchant, hero: Inventory, item_id: String, count: int = 1
) -> String:
	if count <= 0 or hero.bag_count(item_id) < count:
		return Inventory.ERR_NOT_HERE
	if not merchant.wants(db, item_id):
		return ERR_NOT_BUYING
	var gain := merchant.price_to_sell(db, item_id) * count
	if gain <= 0:
		return ERR_WORTHLESS
	if merchant.goods.purse < gain:
		return ERR_MERCHANT_NO_MONEY
	hero.remove(item_id, count)
	merchant.goods.add(item_id, count)
	merchant.goods.purse -= gain
	hero.purse += gain
	return ""
