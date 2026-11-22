class_name MarketStore
extends RefCounted
## Купцы из модулей и их состояние между боями (user://saves/market.json, ADR-0025).

const PATH := "user://saves/market.json"


## [param data] — купцы из модулей (ModuleContent.merchants_data).
static func load_market(db: RulesDb, data: Dictionary, errors: Array[String]) -> Market:
	var market := Market.from_data(data, db, errors)
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			var saved: Dictionary = parsed
			market.apply_saved(saved, db)
	return market


static func save_market(market: Market) -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(market.to_dict(), "  ", true))
	file.close()
