class_name BattleGrid
extends RefCounted
## Логическая боевая сетка (ADR-0007). Клетка 5 футов = 1.5 м.
## Каждая колонка (x, z) имеет один уровень высоты и может быть непроходимой.
## Правила перемещения — docs/rules/movement.md.

enum Diagonal { CHEBYSHEV, ALTERNATING }

const CELL_SIZE_M: float = 1.5
## Уровень высоты — 5 футов, как клетка (ADR-0037); на экране — столько же метров.
const LEVEL_FEET := 5
const LEVEL_HEIGHT_M: float = 1.5
## С какого перепада вниз шаг становится падением (10 футов).
const FALL_LEVELS := 2

var width: int = 0
var depth: int = 0
var diagonal: Diagonal = Diagonal.CHEBYSHEV

var _levels: Dictionary[Vector2i, int] = {}
var _blocked: Dictionary[Vector2i, bool] = {}
var _low: Dictionary[Vector2i, bool] = {}


func _init(p_width: int = 0, p_depth: int = 0) -> void:
	width = p_width
	depth = p_depth


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < depth


func set_level(c: Vector2i, level: int) -> void:
	_levels[c] = level


func level_at(c: Vector2i) -> int:
	return _levels.get(c, 0)


func set_blocked(c: Vector2i, blocked: bool) -> void:
	if blocked:
		_blocked[c] = true
	else:
		_blocked.erase(c)
		_low.erase(c)


func is_blocked(c: Vector2i) -> bool:
	return _blocked.has(c)


## Низкая преграда (плетень, надгробие): непроходима, даёт половинное укрытие,
## но не перекрывает линию видимости (docs/rules/cover.md).
func set_low_obstacle(c: Vector2i, low: bool) -> void:
	set_blocked(c, low)
	if low:
		_low[c] = true
	else:
		_low.erase(c)


func is_low_obstacle(c: Vector2i) -> bool:
	return _low.has(c)


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_blocked(c)


## Клетка с уровнем: Vector3i(x, level, z).
func cell_at(c: Vector2i) -> Vector3i:
	return Vector3i(c.x, level_at(c), c.y)


## Можно ли шагнуть между соседними колонками. Перепад любой: на уступ выше
## 1 уровня лезут, с уступа ниже 1 уровня прыгают (docs/rules/movement.md).
func can_step(_from: Vector2i, to: Vector2i) -> bool:
	return is_walkable(to)


## Падение при шаге [param from] → [param to]: перепад вниз от FALL_LEVELS уровней.
func is_fall(from: Vector2i, to: Vector2i) -> bool:
	return level_at(from) - level_at(to) >= FALL_LEVELS


## Расстояние по Чебышёву в колонках (для ближнего боя и эвристики).
static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Разбирает сетку из данных арены: строки карты, где '.' — уровень 0,
## '1'..'9' — уровень, '#' — высокая преграда (стена, столб), '=' — низкая преграда.
static func from_dict(data: Dictionary) -> BattleGrid:
	var rows := JsonRead.get_array(data, "map")
	if rows.is_empty():
		push_error("Empty grid map")
		return BattleGrid.new()
	var grid := BattleGrid.new(str(rows[0]).length(), rows.size())
	var diag := JsonRead.get_str(data, "diagonal", "chebyshev")
	grid.diagonal = Diagonal.ALTERNATING if diag == "alternating" else Diagonal.CHEBYSHEV
	for z in grid.depth:
		var row := str(rows[z])
		if row.length() != grid.width:
			push_error("Grid map rows must have equal length")
			return BattleGrid.new()
		for x in grid.width:
			var ch := row[x]
			var c := Vector2i(x, z)
			if ch == "#":
				grid.set_blocked(c, true)
			elif ch == "=":
				grid.set_low_obstacle(c, true)
			elif ch != ".":
				grid.set_level(c, ch.to_int())
	return grid
