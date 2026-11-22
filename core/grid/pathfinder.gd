class_name Pathfinder
extends RefCounted
## Детерминированный поиск пути на BattleGrid (ADR-0007), очередь — двоичная куча
## (ADR-0040): карты областей до 256 × 256 клеток.
## Узел поиска — (x, z, parity): parity нужна для правила диагоналей 5-10-5.
## При равенстве приоритетов выбирается узел с меньшими (f, h, z, x, parity),
## поэтому один и тот же запрос всегда даёт один и тот же путь.

## Падение (прыжок с уступа) в поиске пути «дороже» на столько клеток: путь
## в обход по склону предпочтительнее, если он вообще есть.
const FALL_PENALTY := 100
## Бит на поле ключа очереди: координаты и эвристика до 4095 (карты до 256 клеток).
const KEY_BITS := 12

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
## [param avoid_falls] — прыгать с уступов, только если иначе не пройти.
static func find_path(
	grid: BattleGrid,
	from: Vector2i,
	to: Vector2i,
	occupied: Dictionary[Vector2i, bool] = {},
	no_stop: Dictionary[Vector2i, bool] = {},
	avoid_falls: bool = true
) -> PathResult:
	var result := PathResult.new()
	if from == to or not grid.is_walkable(to) or occupied.has(to) or no_stop.has(to):
		return result
	var search := Search.new(grid)
	# g — цена для поиска (с надбавкой за падения), spent — настоящая стоимость.
	var start := search.index(from.x, from.y, 0)
	search.g[start] = 0
	search.open.push(_key(0, from, to, 0), start)
	while not search.open.is_empty():
		var current := search.open.pop()
		if search.closed[current] == 1:
			continue
		var cell := current / 2
		if cell % grid.width == to.x and cell / grid.width == to.y:
			return search.build(current)
		search.closed[current] = 1
		search.expand(current, occupied, avoid_falls, -1, to)
	return result


## Минимальная стоимость достижения каждой колонки в пределах [param budget].
## Стартовая колонка и клетки из [param no_stop] не включаются (но через них можно пройти).
## [param allow_falls] = false — без прыжков с уступов.
static func reachable(
	grid: BattleGrid,
	from: Vector2i,
	budget: int,
	occupied: Dictionary[Vector2i, bool] = {},
	no_stop: Dictionary[Vector2i, bool] = {},
	allow_falls: bool = true
) -> Dictionary[Vector2i, int]:
	var best: Dictionary[Vector2i, int] = {}
	var search := Search.new(grid)
	var none := Vector2i(-1, -1)
	var start := search.index(from.x, from.y, 0)
	search.g[start] = 0
	search.open.push(_key(0, from, none, 0), start)
	while not search.open.is_empty():
		var current := search.open.pop()
		if search.closed[current] == 1:
			continue
		search.closed[current] = 1
		var cell := current / 2
		var col := Vector2i(cell % grid.width, cell / grid.width)
		var cost := search.g[current]
		if col != from and not no_stop.has(col) and (not best.has(col) or cost < best[col]):
			best[col] = cost
		search.expand(current, occupied, false, budget, none, not allow_falls)
	return best


## Ключ узла в очереди одним числом: тот же порядок, что у [f, h, z, x, чётность] —
## при равенстве выигрывает меньший, поэтому путь детерминирован.
static func _key(g: int, cell: Vector2i, goal: Vector2i, parity: int) -> int:
	var h := 0
	if goal.x >= 0:
		h = BattleGrid.chebyshev(cell, goal)
	var key := ((g + h) << KEY_BITS) + h
	key = (key << KEY_BITS) + cell.y
	key = (key << KEY_BITS) + cell.x
	return (key << 1) | parity


## Состояние одного поиска: цены, родители и закрытые узлы в плоских массивах.
## Узел — (x, z, чётность) → индекс ((z × ширина) + x) × 2 + чётность.
class Search:
	extends RefCounted
	const INF := 0x3FFFFFFF
	var grid: BattleGrid
	var g := PackedInt32Array()
	var spent := PackedInt32Array()
	var parent := PackedInt32Array()
	var closed := PackedByteArray()
	var open := PathHeap.new()

	func _init(p_grid: BattleGrid) -> void:
		grid = p_grid
		var total := grid.width * grid.depth * 2
		g.resize(total)
		g.fill(INF)
		spent.resize(total)
		parent.resize(total)
		parent.fill(-1)
		closed.resize(total)

	func index(x: int, z: int, parity: int) -> int:
		return (z * grid.width + x) * 2 + parity

	## Соседи узла [param current]: подъём — клетка за уровень, срезать углы нельзя,
	## диагонали 5-10-5 — по чётности. [param budget] ≥ 0 — не дальше бюджета.
	func expand(
		current: int,
		occupied: Dictionary[Vector2i, bool],
		avoid_falls: bool,
		budget: int,
		goal: Vector2i,
		no_falls: bool = false
	) -> void:
		var parity := current % 2
		var cell := current / 2
		var col := Vector2i(cell % grid.width, cell / grid.width)
		var level := grid.level_at(col)
		var alternating := grid.diagonal == BattleGrid.Diagonal.ALTERNATING
		for d in NEIGHBORS:
			var next := col + d
			if not grid.is_walkable(next) or occupied.has(next):
				continue
			var cost := 1
			var next_parity := parity
			if d.x != 0 and d.y != 0:
				if not grid.is_walkable(col + Vector2i(d.x, 0)):
					continue
				if not grid.is_walkable(col + Vector2i(0, d.y)):
					continue
				if alternating:
					cost = 2 if parity == 1 else 1
					next_parity = 1 - parity
			var next_level := grid.level_at(next)
			if next_level > level:
				cost += next_level - level
			var fall := level - next_level >= BattleGrid.FALL_LEVELS
			if fall and no_falls:
				continue
			var node := index(next.x, next.y, next_parity)
			if closed[node] == 1:
				continue
			var price := g[current] + cost
			if budget >= 0 and price > budget:
				continue
			if fall and avoid_falls:
				price += FALL_PENALTY
			if price < g[node]:
				g[node] = price
				spent[node] = spent[current] + cost
				parent[node] = current
				open.push(Pathfinder._key(price, next, goal, next_parity), node)

	func build(goal: int) -> PathResult:
		var nodes: Array[int] = []
		var node := goal
		while parent[node] >= 0:
			nodes.append(node)
			node = parent[node]
		nodes.reverse()
		var result := PathResult.new()
		for n in nodes:
			var cell := n / 2
			result.cells.append(grid.cell_at(Vector2i(cell % grid.width, cell / grid.width)))
			result.costs.append(spent[n])
		return result
