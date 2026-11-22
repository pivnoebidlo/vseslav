class_name AreaView
extends Node3D
## Облик области для исследования: земля, дороги, избы, деревья, плетни — простая
## геометрия по символьной карте (ADR-0029) — и сетка клеток, которую можно включить
## (ADR-0030): по ней видно, где пройдёт бой.

const CELL := BattleGrid.CELL_SIZE_M
const HOUSE_HEIGHT := 2.1
const FENCE_HEIGHT := 0.6
const GRID_Y := 0.025

var area: AreaMap
var _grid := MeshInstance3D.new()


func build(p_area: AreaMap) -> void:
	area = p_area
	_build_area()
	_build_grid()


func set_grid_visible(on: bool) -> void:
	_grid.visible = on


func is_grid_visible() -> bool:
	return _grid.visible


## Сетка — контуры проходимых клеток: там, где можно встать в бою.
func _build_grid() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var h := CELL / 2.0
	for z in area.depth():
		for x in area.width():
			if not area.grid.is_walkable(Vector2i(x, z)):
				continue
			var c := _cell_pos(Vector2i(x, z)) + Vector3(0.0, GRID_Y, 0.0)
			var corners: Array[Vector3] = [
				c + Vector3(-h, 0.0, -h),
				c + Vector3(h, 0.0, -h),
				c + Vector3(h, 0.0, h),
				c + Vector3(-h, 0.0, h),
			]
			for i in 4:
				mesh.surface_add_vertex(corners[i])
				mesh.surface_add_vertex(corners[(i + 1) % 4])
	mesh.surface_end()
	_grid.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.1, 0.1, 0.08, 0.45)
	_grid.material_override = mat
	_grid.visible = false
	add_child(_grid)


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)


func _build_area() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(area.width() * CELL, area.depth() * CELL)
	ground.mesh = plane
	ground.position = Vector3((area.width() - 1) * CELL / 2.0, 0.0, (area.depth() - 1) * CELL / 2.0)
	ground.material_override = _material(Color(0.42, 0.52, 0.3))
	add_child(ground)
	var road := _material(Color(0.55, 0.47, 0.34))
	var wall := _material(Color(0.47, 0.34, 0.22))
	var roof := _material(Color(0.36, 0.3, 0.2))
	var trunk := _material(Color(0.35, 0.25, 0.16))
	var crown := _material(Color(0.2, 0.36, 0.2))
	var fence := _material(Color(0.5, 0.4, 0.27))
	for z in area.depth():
		for x in area.width():
			var c := Vector2i(x, z)
			match area.tile(c):
				AreaMap.ROAD:
					_box(c, Vector3(CELL, 0.02, CELL), 0.01, road)
				AreaMap.BUILDING:
					_box(c, Vector3(CELL, HOUSE_HEIGHT, CELL), HOUSE_HEIGHT / 2.0, wall)
					_box(c, Vector3(CELL * 1.08, 0.35, CELL * 1.08), HOUSE_HEIGHT + 0.17, roof)
				AreaMap.TREE:
					_tree(c, trunk, crown)
				AreaMap.FENCE:
					_fence(c, fence)


func _box(c: Vector2i, size: Vector3, y: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = _cell_pos(c) + Vector3(0.0, y, 0.0)
	add_child(m)


## Дерево: ствол и конус кроны; размер чуть разный по клетке, чтобы лес не был ровным.
func _tree(c: Vector2i, trunk: Material, crown: Material) -> void:
	var s := 0.8 + float((c.x * 7 + c.y * 13) % 5) * 0.1
	var t := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.16
	cyl.height = 1.0 * s
	t.mesh = cyl
	t.material_override = trunk
	t.position = _cell_pos(c) + Vector3(0.0, 0.5 * s, 0.0)
	add_child(t)
	var k := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.75 * s
	cone.height = 2.2 * s
	k.mesh = cone
	k.material_override = crown
	k.position = _cell_pos(c) + Vector3(0.0, 1.0 * s + 1.1 * s, 0.0)
	add_child(k)


## Плетень: вдоль соседних плетней (по горизонтали или по вертикали).
func _fence(c: Vector2i, mat: Material) -> void:
	var along_x := (
		area.tile(c + Vector2i.LEFT) == AreaMap.FENCE
		or area.tile(c + Vector2i.RIGHT) == AreaMap.FENCE
	)
	var along_z := (
		area.tile(c + Vector2i.UP) == AreaMap.FENCE or area.tile(c + Vector2i.DOWN) == AreaMap.FENCE
	)
	if along_x or not along_z:
		_box(c, Vector3(CELL, FENCE_HEIGHT, 0.12), FENCE_HEIGHT / 2.0, mat)
	if along_z:
		_box(c, Vector3(0.12, FENCE_HEIGHT, CELL), FENCE_HEIGHT / 2.0, mat)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
