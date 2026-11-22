class_name PartyGroup
extends RefCounted
## Кем управляет игрок в исследовании (ADR-0030, как в BG3): выбранный герой и сцепка.
## Сцепленные герои ходят группой за выбранным, если он сам в сцепке; отцепленный
## ходит один, а остальные стоят. Новый герой по умолчанию в сцепке.

## Герои в порядке партии.
var ids: Array[String] = []
var selected: String = ""

var _chained: Dictionary[String, bool] = {}


func _init(p_ids: Array[String] = []) -> void:
	ids = p_ids.duplicate()
	for id in ids:
		_chained[id] = true
	selected = ids[0] if not ids.is_empty() else ""


func select(id: String) -> void:
	if ids.has(id):
		selected = id


func is_chained(id: String) -> bool:
	return _chained.get(id, false)


## Отцепить или прицепить героя.
func toggle_chain(id: String) -> void:
	if ids.has(id):
		_chained[id] = not is_chained(id)


## Кто идёт за выбранным, по порядку партии: сцепленные, если выбранный в сцепке.
func followers() -> Array[String]:
	var result: Array[String] = []
	if not is_chained(selected):
		return result
	for id in ids:
		if id != selected and is_chained(id):
			result.append(id)
	return result


## Кто двинется по приказу: выбранный и его спутники.
func movers() -> Array[String]:
	var result: Array[String] = [selected]
	result.append_array(followers())
	return result


## Следующий герой по кругу (переключение клавишей).
func next_id() -> String:
	if ids.is_empty():
		return ""
	return ids[(ids.find(selected) + 1) % ids.size()]
