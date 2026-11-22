class_name TerrainMesh
extends RefCounted
## Рельеф области (ADR-0037): сетка вершин мельче клетки, высота — сглаженный
## уровень. Между соседними клетками с перепадом 1 — пологий откос, при перепаде
## больше — обрыв (соседа не сглаживаем, и между двумя вершинами у края клетки
## получается почти отвесная стенка). Центр клетки всегда ровно на своём уровне,
## поэтому фигуры, стоящие по уровню, не висят и не тонут.

const CELL := BattleGrid.CELL_SIZE_M
const LEVEL := BattleGrid.LEVEL_HEIGHT_M
## Вершин на клетку по каждой оси.
const SUB := 4
## Полуширина окна сглаживания в долях клетки: у центра ровная площадка.
const SMOOTH := 0.45


## Сетка земли на всю область; для плоской области — тоже сетка (из 4 вершин на клетку).
static func build(grid: BattleGrid) -> ArrayMesh:
	var xs := _axis(grid.width)
	var zs := _axis(grid.depth)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in zs.size():
		for i in xs.size():
			var p := Vector2(xs[i], zs[j])
			st.add_vertex(Vector3(p.x * CELL, height_at(grid, p), p.y * CELL))
	var row := xs.size()
	for j in zs.size() - 1:
		for i in row - 1:
			var a := j * row + i
			var b := a + 1
			var c := a + row
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	return st.commit()


## Высота земли в точке [param p] (координаты в клетках: центр клетки — целые числа).
static func height_at(grid: BattleGrid, p: Vector2) -> float:
	var own := Vector2i(roundi(p.x), roundi(p.y))
	var own_level := _level(grid, own)
	var total := 0.0
	var weight := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := own + Vector2i(dx, dz)
			var w := _overlap(p.x, c.x) * _overlap(p.y, c.y)
			if w <= 0.0:
				continue
			var level := _level(grid, c)
			# Обрыв не сглаживается: чужой уровень заменяется своим.
			if absi(level - own_level) > 1:
				level = own_level
			total += w * level
			weight += w
	return total / weight * LEVEL if weight > 0.0 else own_level * LEVEL


## Положения вершин по оси: край карты, по SUB точек внутри каждой клетки
## (не на границах клеток — так обрыв ложится ровно на границу), край карты.
static func _axis(cells: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.append(-0.5)
	for k in cells * SUB:
		values.append(-0.5 + (k + 0.5) / SUB)
	values.append(cells - 0.5)
	return values


## Доля окна [t − SMOOTH, t + SMOOTH], попавшая в клетку с центром [param center].
static func _overlap(t: float, center: int) -> float:
	var lo := maxf(t - SMOOTH, center - 0.5)
	var hi := minf(t + SMOOTH, center + 0.5)
	return maxf(hi - lo, 0.0)


## Уровень клетки; за краем карты — уровень ближайшей клетки на краю.
static func _level(grid: BattleGrid, c: Vector2i) -> int:
	var inside := Vector2i(clampi(c.x, 0, grid.width - 1), clampi(c.y, 0, grid.depth - 1))
	return grid.level_at(inside)
