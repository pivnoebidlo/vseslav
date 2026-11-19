class_name Area
extends RefCounted
## Области эффектов на сетке (docs/rules/magic.md). Расстояние — по Чебышёву (ADR-0019),
## высота не учитывается. Клетки возвращаются в порядке (z, x).


## Квадрат радиуса [param radius] вокруг [param center].
static func burst(grid: BattleGrid, center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, z)
			if grid.in_bounds(c):
				cells.append(c)
	return cells


## Конус длины [param length] от [param origin] в сторону [param toward]
## (одно из 8 направлений). По прямой — клин 90°, по диагонали — четверть квадрата.
## Клетка источника в конус не входит.
static func cone(
	grid: BattleGrid, origin: Vector2i, toward: Vector2i, length: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dir := Vector2i(signi(toward.x - origin.x), signi(toward.y - origin.y))
	if dir == Vector2i.ZERO:
		return cells
	for z in range(origin.y - length, origin.y + length + 1):
		for x in range(origin.x - length, origin.x + length + 1):
			var c := Vector2i(x, z)
			var v := c - origin
			if v == Vector2i.ZERO or not grid.in_bounds(c):
				continue
			if _in_cone(v, dir):
				cells.append(c)
	return cells


static func _in_cone(v: Vector2i, dir: Vector2i) -> bool:
	if dir.x != 0 and dir.y != 0:
		return v.x * dir.x >= 0 and v.y * dir.y >= 0
	if dir.x != 0:
		return v.x * dir.x >= 1 and absi(v.y) <= v.x * dir.x
	return v.y * dir.y >= 1 and absi(v.x) <= v.y * dir.y
