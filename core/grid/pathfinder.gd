class_name Pathfinder
extends RefCounted
## Детерминированный поиск пути на BattleGrid (ADR-0007).
## Узел поиска — (x, z, parity): parity нужна для правила диагоналей 5-10-5.
## При равенстве приоритетов выбирается узел с меньшими (f, h, z, x, parity),
## поэтому один и тот же запрос всегда даёт один и тот же путь.

## Порядок соседей фиксирован: сначала ортогональные, затем диагональные.
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


## Путь от [param from] до [param to]. Клетки из [param occupied] непроходимы;
## в клетках из [param no_stop] (союзники) нельзя остановиться, но можно пройти.
static func find_path(
	grid: BattleGrid,
	from: Vector2i,
	to: Vector2i,
	occupied: Dictionary[Vector2i, bool] = {},
	no_stop: Dictionary[Vector2i, bool] = {}
) -> PathResult:
	var result := PathResult.new()
	if from == to or not grid.is_walkable(to) or occupied.has(to) or no_stop.has(to):
		return result
	var start := Vector3i(from.x, from.y, 0)
	var g: Dictionary[Vector3i, int] = {start: 0}
	var parent: Dictionary[Vector3i, Vector3i] = {}
	var open: Array[Vector3i] = [start]
	var closed: Dictionary[Vector3i, bool] = {}
	while not open.is_empty():
		var current := _pop_best(open, g, to)
		if Vector2i(current.x, current.y) == to:
			return _build(current, parent, g, grid)
		closed[current] = true
		for step in _steps(grid, current, occupied):
			var node: Vector3i = step[0]
			var step_cost: int = step[1]
			var cost: int = g[current] + step_cost
			if closed.has(node):
				continue
			if not g.has(node) or cost < g[node]:
				g[node] = cost
				parent[node] = current
				if not open.has(node):
					open.append(node)
	return result


## Минимальная стоимость достижения каждой колонки в пределах [param budget].
## Стартовая колонка и клетки из [param no_stop] не включаются (но через них можно пройти).
static func reachable(
	grid: BattleGrid,
	from: Vector2i,
	budget: int,
	occupied: Dictionary[Vector2i, bool] = {},
	no_stop: Dictionary[Vector2i, bool] = {}
) -> Dictionary[Vector2i, int]:
	var best: Dictionary[Vector2i, int] = {}
	var start := Vector3i(from.x, from.y, 0)
	var g: Dictionary[Vector3i, int] = {start: 0}
	var open: Array[Vector3i] = [start]
	var closed: Dictionary[Vector3i, bool] = {}
	while not open.is_empty():
		var current := _pop_best(open, g, Vector2i(-1, -1))
		closed[current] = true
		var col := Vector2i(current.x, current.y)
		if col != from and not no_stop.has(col) and (not best.has(col) or g[current] < best[col]):
			best[col] = g[current]
		for step in _steps(grid, current, occupied):
			var node: Vector3i = step[0]
			var step_cost: int = step[1]
			var cost: int = g[current] + step_cost
			if cost > budget or closed.has(node):
				continue
			if not g.has(node) or cost < g[node]:
				g[node] = cost
				if not open.has(node):
					open.append(node)
	return best


## Возможные шаги из узла: массив пар [узел: Vector3i, стоимость: int].
static func _steps(
	grid: BattleGrid, node: Vector3i, occupied: Dictionary[Vector2i, bool]
) -> Array[Array]:
	var steps: Array[Array] = []
	var col := Vector2i(node.x, node.y)
	for d in NEIGHBORS:
		var next := col + d
		if not grid.can_step(col, next) or occupied.has(next):
			continue
		var parity := node.z
		var cost := 1
		var diagonal := d.x != 0 and d.y != 0
		if diagonal:
			# Не срезаем углы: обе ортогональные клетки должны быть проходимы.
			if not grid.is_walkable(col + Vector2i(d.x, 0)):
				continue
			if not grid.is_walkable(col + Vector2i(0, d.y)):
				continue
			if grid.diagonal == BattleGrid.Diagonal.ALTERNATING:
				cost = 2 if parity == 1 else 1
				parity = 1 - parity
		if grid.level_at(next) > grid.level_at(col):
			cost += 1  # подъём на уровень стоит дополнительную клетку
		steps.append([Vector3i(next.x, next.y, parity), cost])
	return steps


static func _pop_best(
	open: Array[Vector3i], g: Dictionary[Vector3i, int], goal: Vector2i
) -> Vector3i:
	var best_i := 0
	var best_key := _key(open[0], g, goal)
	for i in range(1, open.size()):
		var key := _key(open[i], g, goal)
		if _less(key, best_key):
			best_i = i
			best_key = key
	var best := open[best_i]
	open.remove_at(best_i)
	return best


static func _key(node: Vector3i, g: Dictionary[Vector3i, int], goal: Vector2i) -> Array[int]:
	var h := 0
	if goal.x >= 0:
		h = BattleGrid.chebyshev(Vector2i(node.x, node.y), goal)
	return [g[node] + h, h, node.y, node.x, node.z]


static func _less(a: Array[int], b: Array[int]) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


static func _build(
	goal: Vector3i,
	parent: Dictionary[Vector3i, Vector3i],
	g: Dictionary[Vector3i, int],
	grid: BattleGrid
) -> PathResult:
	var nodes: Array[Vector3i] = []
	var node := goal
	while parent.has(node):
		nodes.append(node)
		node = parent[node]
	nodes.reverse()
	var result := PathResult.new()
	for n in nodes:
		result.cells.append(grid.cell_at(Vector2i(n.x, n.y)))
		result.costs.append(g[n])
	return result
