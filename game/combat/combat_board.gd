class_name CombatBoard
extends Node3D
## Клетки поля боя поверх любой местности (арена или участок карты): подсветка
## досягаемости, дальности и области, попадание кликом в клетку, координаты в мире.
## Клетка (0, 0) сетки боя стоит в клетке [member origin] местности.

enum Paint { NONE, REACH, RANGE, AREA, ZONE }

const CELL := BattleGrid.CELL_SIZE_M
const LEVEL_HEIGHT := BattleGrid.LEVEL_HEIGHT_M
const LIFT := 0.03
const GLOW_SHADER := preload("res://game/combat/cell_glow.gdshader")

var grid: BattleGrid
var origin := Vector2i.ZERO

var _quads: Dictionary[Vector2i, MeshInstance3D] = {}
var _paint: Dictionary[Vector2i, Paint] = {}
var _area: Array[Vector2i] = []
## Клетки длящихся зон заклинаний — под подсветкой хода (ADR-0046).
var _zones: Array[Vector2i] = []
var _mats: Dictionary[Paint, ShaderMaterial] = {}
var _quad_mesh := PlaneMesh.new()


func _init() -> void:
	_quad_mesh.size = Vector2(CELL * 0.94, CELL * 0.94)
	_mats[Paint.REACH] = _glow(Color(0.55, 0.85, 0.45, 0.45))
	_mats[Paint.RANGE] = _glow(Color(0.5, 0.6, 0.95, 0.4))
	_mats[Paint.AREA] = _glow(Color(0.95, 0.45, 0.35, 0.55))
	_mats[Paint.ZONE] = _glow(Color(0.85, 0.9, 1.0, 0.35))


## Строит клетки для сетки [param p_grid], смещённой на [param p_origin] клеток местности.
func build(p_grid: BattleGrid, p_origin: Vector2i = Vector2i.ZERO) -> void:
	for child in get_children():
		child.queue_free()
	_quads.clear()
	_paint.clear()
	_area.clear()
	_zones.clear()
	grid = p_grid
	origin = p_origin
	for z in grid.depth:
		for x in grid.width:
			var column := Vector2i(x, z)
			if grid.is_walkable(column):
				_add_cell(column)


## Точка в мире, где стоит участник в колонке [param column] сетки боя.
func position_of(column: Vector2i) -> Vector3:
	var level := grid.level_at(column) if grid != null else 0
	return Vector3((column.x + origin.x) * CELL, level * LEVEL_HEIGHT, (column.y + origin.y) * CELL)


## Колонка сетки боя под точкой мира; NO_CELL — вне поля.
func column_at(world: Vector3) -> Vector2i:
	var c := Vector2i(roundi(world.x / CELL) - origin.x, roundi(world.z / CELL) - origin.y)
	return c if grid != null and grid.in_bounds(c) else ActionResolver.NO_CELL


func paint(cells: Array[Vector2i], kind: Paint) -> void:
	for c in cells:
		if _quads.has(c):
			_paint[c] = kind
			_show(c)


## Область под курсором — поверх досягаемости и дальности.
func paint_area(cells: Array[Vector2i]) -> void:
	var old := _area
	_area = cells.duplicate()
	for c in old:
		_show(c)
	for c in _area:
		_show(c)


## Зоны заклинаний: держатся, пока их не заменят (clear их не трогает).
func paint_zones(cells: Array[Vector2i]) -> void:
	var old := _zones
	_zones = cells.duplicate()
	for c in old:
		_show(c)
	for c in _zones:
		_show(c)


func clear() -> void:
	var cells: Array[Vector2i] = []
	cells.assign(_paint.keys())
	_paint.clear()
	_area.clear()
	for c in cells:
		_show(c)


func _show(c: Vector2i) -> void:
	if not _quads.has(c):
		return
	var kind: Paint = Paint.NONE
	if _area.has(c):
		kind = Paint.AREA
	elif _paint.has(c):
		kind = _paint[c]
	elif _zones.has(c):
		kind = Paint.ZONE
	var quad := _quads[c]
	quad.visible = kind != Paint.NONE
	if kind != Paint.NONE:
		quad.material_override = _mats[kind]


func _add_cell(column: Vector2i) -> void:
	var quad := MeshInstance3D.new()
	quad.mesh = _quad_mesh
	quad.position = position_of(column) + Vector3(0.0, LIFT, 0.0)
	quad.visible = false
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	_quads[column] = quad
	var body := StaticBody3D.new()
	body.set_meta("column", column)
	body.position = position_of(column) - Vector3(0.0, 0.05, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL, 0.1, CELL)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _glow(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("tint", Color(color, minf(1.0, color.a * 1.6)))
	return m
