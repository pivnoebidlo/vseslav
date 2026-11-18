class_name PathResult
extends RefCounted
## Найденный путь. Пустой [member cells] — пути нет.

## Клетки пути без стартовой, по порядку.
var cells: Array[Vector3i] = []
## Накопленная стоимость (в клетках по 5 футов) до каждой клетки из [member cells].
var costs: Array[int] = []


func found() -> bool:
	return not cells.is_empty()


func total_cost() -> int:
	return costs[-1] if not costs.is_empty() else 0


## Обрезает путь до последней клетки, стоимость которой не превышает [param budget].
func truncated(budget: int) -> PathResult:
	var result := PathResult.new()
	for i in cells.size():
		if costs[i] > budget:
			break
		result.cells.append(cells[i])
		result.costs.append(costs[i])
	return result
