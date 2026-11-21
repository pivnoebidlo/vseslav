class_name MarketStore
extends RefCounted
## Купцы тестового модуля и их состояние между боями (user://saves/market.json, ADR-0025).

const DATA_PATH := "res://modules/spike/merchants.json"
const PATH := "user://saves/market.json"


static func load_market(db: RulesDb, errors: Array[String]) -> Market:
	var market := Market.from_data(ArenaLoader.read_file(DATA_PATH), db, errors)
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			var data: Dictionary = parsed
			market.apply_saved(data, db)
	return market


## Купцы как в данных (сбросить торг).
static func fresh_market(db: RulesDb) -> Market:
	return Market.from_data(ArenaLoader.read_file(DATA_PATH), db)


static func save_market(market: Market) -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(market.to_dict(), "  ", true))
	file.close()
