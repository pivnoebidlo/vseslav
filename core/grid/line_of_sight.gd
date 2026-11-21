class_name LineOfSight
extends RefCounted
## Линия видимости и укрытие по клеткам (ADR-0021, docs/rules/cover.md).
##
## Из каждого угла клетки атакующего ведём 4 отрезка к углам клетки цели и берём
## угол, дающий цели наименьшее укрытие. Отрезок перекрыт высокими преградами, если
## проходит через внутренность преграды, идёт по ребру между двумя преградами или
## через узел между двумя преградами, стоящими по диагонали (как запрет срезать углы
## при ходьбе); край карты считается преградой. Простое касание стороны или угла
## одной преграды не считается.
## Перекрыто 0 — укрытия нет, 1–2 — половинное, 3 — три четверти, 4 — полное.
## Низкая преграда или существо на любом отрезке выбранного угла дают не меньше
## половинного укрытия, но никогда не больше.
## Все вычисления — в целых числах: углы клеток лежат в узлах решётки.

enum Cover { NONE, HALF, THREE_QUARTERS, TOTAL }

const CORNERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]


## Бонус к КД и спасброскам Ловкости за укрытие.
static func ac_bonus(cover: int) -> int:
	match cover:
		Cover.HALF:
			return 2
		Cover.THREE_QUARTERS:
			return 5
	return 0


## Укрытие цели в [param to] от атакующего в [param from].
## [param creatures] — клетки существ, которые могут дать укрытие (без атакующего и цели).
static func cover(
	grid: BattleGrid, from: Vector2i, to: Vector2i, creatures: Array[Vector2i] = []
) -> int:
	if from == to:
		return Cover.NONE
	var tall: Dictionary[Vector2i, bool] = {}
	var low: Array[Vector2i] = []
	_collect(grid, from, to, creatures, tall, low)
	var best := Cover.TOTAL
	for a in CORNERS:
		var p := from + a
		var blocked := 0
		var low_hit := false
		for b in CORNERS:
			var q := to + b
			if _blocked_by_tall(p, q, tall):
				blocked += 1
			elif not low_hit and _hits_any(p, q, low):
				low_hit = true
		var c := _from_count(blocked)
		if low_hit and c == Cover.NONE:
			c = Cover.HALF
		best = mini(best, c) as Cover
		if best == Cover.NONE:
			break
	return best


## Видна ли клетка: укрытие от преград не полное (существа полного не дают).
static func can_see(grid: BattleGrid, from: Vector2i, to: Vector2i) -> bool:
	return cover(grid, from, to) != Cover.TOTAL


## Высокая преграда для линии между клетками с уровнями до [param max_level]:
## непроходимая клетка, кроме низких преград, или земля выше обоих концов.
static func is_tall(grid: BattleGrid, c: Vector2i, max_level: int) -> bool:
	if grid.is_blocked(c):
		return not grid.is_low_obstacle(c)
	return grid.level_at(c) > max_level


static func _from_count(blocked: int) -> Cover:
	if blocked == 0:
		return Cover.NONE
	if blocked <= 2:
		return Cover.HALF
	if blocked == 3:
		return Cover.THREE_QUARTERS
	return Cover.TOTAL


## Преграды в прямоугольнике между клетками (высокие — с запасом в клетку, чтобы
## видеть рёбра и узлы по краям), кроме самих концов. За краем карты — высокая преграда.
static func _collect(
	grid: BattleGrid,
	from: Vector2i,
	to: Vector2i,
	creatures: Array[Vector2i],
	tall: Dictionary[Vector2i, bool],
	low: Array[Vector2i]
) -> void:
	var max_level := maxi(grid.level_at(from), grid.level_at(to))
	for z in range(mini(from.y, to.y) - 1, maxi(from.y, to.y) + 2):
		for x in range(mini(from.x, to.x) - 1, maxi(from.x, to.x) + 2):
			var c := Vector2i(x, z)
			if c == from or c == to:
				continue
			if not grid.in_bounds(c) or is_tall(grid, c, max_level):
				tall[c] = true
			elif grid.is_low_obstacle(c) or creatures.has(c):
				low.append(c)


## Перекрыт ли отрезок высокими преградами (см. описание класса).
static func _blocked_by_tall(p: Vector2i, q: Vector2i, tall: Dictionary[Vector2i, bool]) -> bool:
	if p == q:
		return false
	for c: Vector2i in tall:
		if segment_hits_cell(p, q, c):
			return true
	var d := q - p
	var steps := _gcd(absi(d.x), absi(d.y))
	var step := d / steps
	for k in range(0, steps + 1):
		var at := p + step * k
		if k > 0 and k < steps and _gap_closed(at, tall):
			return true
		if k < steps and _edge_closed(at, step, tall):
			return true
	return false


## Обе диагональные пары клеток вокруг узла: если одна пара — преграды, щели нет.
static func _gap_closed(at: Vector2i, tall: Dictionary[Vector2i, bool]) -> bool:
	var tl := tall.has(at + Vector2i(-1, -1))
	var tr := tall.has(at + Vector2i(0, -1))
	var bl := tall.has(at + Vector2i(-1, 0))
	var br := tall.has(at + Vector2i(0, 0))
	return (tl and br) or (tr and bl)


## Единичное ребро из узла [param at] по [param step] (только для осевых отрезков):
## перекрыто, если с обеих сторон преграды.
static func _edge_closed(at: Vector2i, step: Vector2i, tall: Dictionary[Vector2i, bool]) -> bool:
	if step.x != 0 and step.y != 0:
		return false
	if step.y == 0:
		var x := mini(at.x, at.x + step.x)
		return tall.has(Vector2i(x, at.y - 1)) and tall.has(Vector2i(x, at.y))
	var z := mini(at.y, at.y + step.y)
	return tall.has(Vector2i(at.x - 1, z)) and tall.has(Vector2i(at.x, z))


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a


static func _hits_any(p: Vector2i, q: Vector2i, cells: Array[Vector2i]) -> bool:
	for c in cells:
		if segment_hits_cell(p, q, c):
			return true
	return false


## Проходит ли отрезок между узлами решётки [param p]–[param q] через внутренность
## клетки [param cell] (квадрат от cell до cell + 1). Теорема о разделяющей оси:
## оси X и Z и нормаль отрезка; строгие неравенства — касание не считается.
static func segment_hits_cell(p: Vector2i, q: Vector2i, cell: Vector2i) -> bool:
	if p == q:
		return false
	if mini(p.x, q.x) >= cell.x + 1 or maxi(p.x, q.x) <= cell.x:
		return false
	if mini(p.y, q.y) >= cell.y + 1 or maxi(p.y, q.y) <= cell.y:
		return false
	var d := q - p
	var positive := false
	var negative := false
	for k in CORNERS:
		var r := cell + k - p
		var side := d.x * r.y - d.y * r.x
		if side > 0:
			positive = true
		elif side < 0:
			negative = true
	return positive and negative
