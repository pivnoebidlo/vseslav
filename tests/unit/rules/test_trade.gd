extends GutTest
## Торговля (ADR-0025): цены с наценкой, продажа за долю цены, ограниченные запас
## и кошелёк купца, кошелёк героя, вес.

var _db: RulesDb


func before_all() -> void:
	_db = CombatSim.rules()


func _smith(purse: int = 100) -> Merchant:
	return (
		Merchant
		. from_dict(
			{
				"id": "smith",
				"markup": 120,
				"buyback": 50,
				"buys": ["weapon", "armor", "shield"],
				"purse": purse,
				"goods": [{"item": "nozh", "count": 2}, "kolchuga"],
			}
		)
	)


func test_prices() -> void:
	var m := _smith()
	assert_eq(m.price_to_buy(_db, "nozh"), 10, "8 kuny × 120% = 9.6 → rounded up")
	assert_eq(m.price_to_sell(_db, "nozh"), 4)
	assert_eq(m.price_to_sell(_db, "posoh"), 0, "1 kuna × 50% rounds down")


func test_buy_moves_item_and_money() -> void:
	var m := _smith()
	var hero := Inventory.from_dict({"purse": 25})
	assert_eq(Trade.buy(_db, m, hero, 10, "nozh"), "")
	assert_eq(hero.bag_count("nozh"), 1)
	assert_eq(hero.purse, 15)
	assert_eq(m.goods.purse, 110)
	assert_eq(m.goods.bag_count("nozh"), 1)
	assert_eq(Trade.buy(_db, m, hero, 10, "nozh", 2), Inventory.ERR_NOT_HERE, "only one left")
	assert_eq(Trade.buy(_db, m, hero, 10, "kolchuga"), Trade.ERR_NO_MONEY)


func test_buy_respects_weight() -> void:
	var m := _smith()
	var hero := Inventory.from_dict({"purse": 1000})
	assert_eq(Trade.buy(_db, m, hero, 1, "kolchuga"), Inventory.ERR_TOO_HEAVY, "STR 1 drags 30 lb")
	assert_eq(hero.purse, 1000)


func test_sell_rules() -> void:
	var m := _smith(10)
	var hero := Inventory.from_dict({"main_hand": "mech", "bag": ["fakel", "posoh", "topor"]})
	assert_eq(Trade.sell(_db, m, hero, "mech"), Inventory.ERR_NOT_HERE, "only from the bag")
	assert_eq(Trade.sell(_db, m, hero, "fakel"), Trade.ERR_NOT_BUYING)
	assert_eq(Trade.sell(_db, m, hero, "posoh"), Trade.ERR_WORTHLESS)
	assert_eq(Trade.sell(_db, m, hero, "topor"), Trade.ERR_MERCHANT_NO_MONEY, "20 > 10")
	m.goods.purse = 50
	assert_eq(Trade.sell(_db, m, hero, "topor"), "")
	assert_eq(hero.purse, 20)
	assert_eq(m.goods.purse, 30)
	assert_eq(m.goods.bag_count("topor"), 1, "sold goods appear in the stock")


func test_market_state_round_trip() -> void:
	var errors: Array[String] = []
	var data := {
		"merchants":
		[
			{"id": "a", "goods": ["nozh"], "purse": 5},
			{"id": "b", "goods": ["lazer"]},
			{"id": "a", "goods": []},
		]
	}
	var market := Market.from_data(data, _db, errors)
	assert_eq(market.order, ["a"] as Array[String])
	assert_eq(errors.size(), 2, "unknown item and duplicate id")
	var hero := Inventory.from_dict({"purse": 100})
	Trade.buy(_db, market.get_merchant("a"), hero, 10, "nozh")
	var saved := market.to_dict()
	var fresh := Market.from_data(data, _db)
	assert_eq(fresh.get_merchant("a").goods.bag_count("nozh"), 1)
	fresh.apply_saved(saved, _db)
	assert_eq(fresh.get_merchant("a").goods.bag_count("nozh"), 0)
	assert_eq(fresh.get_merchant("a").goods.purse, 13)
	fresh.apply_saved({"format": 99, "merchants": {"a": {"purse": 0}}}, _db)
	assert_eq(fresh.get_merchant("a").goods.purse, 13, "foreign format ignored")


func test_module_merchants_are_valid() -> void:
	var errors: Array[String] = []
	var data := CombatLoader.read_file("res://modules/spike/merchants.json")
	var market := Market.from_data(data, _db, errors)
	assert_eq(errors, [] as Array[String])
	assert_gt(market.order.size(), 0)
