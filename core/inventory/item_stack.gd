class_name ItemStack
extends RefCounted
## Стопка одинаковых предметов: id и количество.

var item: String = ""
var count: int = 1


func _init(p_item: String = "", p_count: int = 1) -> void:
	item = p_item
	count = p_count


func to_value() -> Variant:
	if count == 1:
		return item
	return {"item": item, "count": count}


## Из записи "id" или {"item": id, "count": n}; null при ошибке.
static func from_value(value: Variant) -> ItemStack:
	if typeof(value) == TYPE_STRING:
		return ItemStack.new(str(value), 1)
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		var s := ItemStack.new(JsonRead.get_str(d, "item"), JsonRead.get_int(d, "count", 1))
		if s.item != "" and s.count > 0:
			return s
	return null
