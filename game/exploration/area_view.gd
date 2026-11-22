class_name AreaView
extends Node3D
## Облик области: земля и дороги, а на символах карты — модели окружения по стилю
## области и явные объекты (ADR-0033); без стиля — простая геометрия (ADR-0029).
## Модели размножаются через MultiMesh. Сетка клеток включается по желанию (ADR-0030).

const CELL := BattleGrid.CELL_SIZE_M
const HOUSE_HEIGHT := 2.1
const FENCE_HEIGHT := 0.6
const GRID_Y := 0.025
## Доля пустых клеток с мелочами «scatter» (камешки), процентов.
const SCATTER_PERCENT := 4
## Доля свободных клеток постройки с мелочами «yard», процентов.
const YARD_PERCENT := 60

var area: AreaMap
var _grid := MeshInstance3D.new()
var _props: PropCatalog = null
## Положения моделей: id → преобразования экземпляров.
var _instances: Dictionary[String, Array] = {}
## Клетки под явными объектами: их символы моделями стиля не рисуются.
var _covered: Dictionary[Vector2i, bool] = {}


func build(p_area: AreaMap, props: PropCatalog = null) -> void:
	area = p_area
	_props = props
	_build_area()
	_flush()
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
	var stone := _material(Color(0.55, 0.55, 0.52))
	var grave_mound := _material(Color(0.36, 0.32, 0.24))
	_place_objects()
	var built: Dictionary[Vector2i, bool] = {}
	for z in area.depth():
		for x in area.width():
			var c := Vector2i(x, z)
			if area.tile(c) == AreaMap.ROAD:
				_box(c, Vector3(CELL, 0.02, CELL), 0.01, road)
			if _covered.has(c):
				continue
			match area.tile(c):
				AreaMap.BUILDING:
					if not built.has(c) and _place_building(c, built):
						continue
					if not built.has(c):
						_box(c, Vector3(CELL, HOUSE_HEIGHT, CELL), HOUSE_HEIGHT / 2.0, wall)
						_box(c, Vector3(CELL * 1.08, 0.35, CELL * 1.08), HOUSE_HEIGHT + 0.17, roof)
				AreaMap.TREE:
					if not _place_styled("tree", c):
						_tree(c, trunk, crown)
				AreaMap.FENCE:
					if not _place_fence(c):
						_fence(c, fence)
				AreaMap.GRAVE:
					if not _place_styled("grave", c):
						_box(c, Vector3(0.55, 0.7, 0.16), 0.35, stone)
						_box(c, Vector3(0.7, 0.08, 1.1), 0.04, grave_mound)
				AreaMap.GROUND:
					if _hash(c) % 100 < SCATTER_PERCENT:
						_place_styled("scatter", c)


# --- Модели (ADR-0033) ------------------------------------------------------------


func _place_objects() -> void:
	for o in area.objects:
		var at := JsonRead.to_vec2i(o.get("at", []))
		var size := Vector2i(1, 1)
		if o.has("size"):
			size = JsonRead.to_vec2i(o["size"])
		var rect := Rect2i(at, size)
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_covered[Vector2i(x, z)] = true
		_place(JsonRead.get_str(o, "prop"), rect, JsonRead.get_int(o, "rotation"), _hash(at))


## Постройка # — связная группа клеток: одна модель на её габарит (колодец, дом,
## большой дом по числу клеток), на свободных клетках группы — мелочи «yard».
func _place_building(start: Vector2i, built: Dictionary[Vector2i, bool]) -> bool:
	var cells := _component(start)
	for c in cells:
		built[c] = true
	var rect := Rect2i(start, Vector2i.ONE)
	for c in cells:
		rect = rect.expand(c)
	rect.size += Vector2i.ONE
	var key := "house"
	if cells.size() == 1:
		key = "well"
	elif cells.size() > 8:
		key = "house_large"
	var id := _pick(key, start)
	if id == "" and key != "house":
		id = _pick("house", start)
	var used := _place(id, rect, 0, _hash(start))
	if not used.has_area():
		for c in cells:
			built.erase(c)
		return false
	for c in cells:
		var center := Vector2(c.x * CELL, c.y * CELL)
		if not used.grow(-0.2).has_point(center) and _hash(c) % 100 < YARD_PERCENT:
			_place(_pick("yard", c), Rect2i(c, Vector2i.ONE), 0, _hash(c))
	return true


func _component(start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary[Vector2i, bool] = {start: true}
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		out.append(c)
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if not seen.has(n) and area.tile(n) == AreaMap.BUILDING and not _covered.has(n):
				seen[n] = true
				queue.append(n)
	return out


func _place_styled(key: String, c: Vector2i) -> bool:
	return _place(_pick(key, c), Rect2i(c, Vector2i.ONE), 0, _hash(c)).has_area()


## Плетень — вдоль соседних плетней; модель вытянута по z, поперёк — поворот.
func _place_fence(c: Vector2i) -> bool:
	var id := _pick("fence", c)
	if id == "" or _props == null or _props.get_prop(id) == null:
		return false
	var along_x := (
		area.tile(c + Vector2i.LEFT) == AreaMap.FENCE
		or area.tile(c + Vector2i.RIGHT) == AreaMap.FENCE
	)
	var along_z := (
		area.tile(c + Vector2i.UP) == AreaMap.FENCE or area.tile(c + Vector2i.DOWN) == AreaMap.FENCE
	)
	if along_x or not along_z:
		_place(id, Rect2i(c, Vector2i.ONE), 90, 0)
	if along_z:
		_place(id, Rect2i(c, Vector2i.ONE), 0, 0)
	return true


## Ставит модель [param id] в клетки [param rect] с поворотом [param rotation];
## возвращает занятый прямоугольник на земле (в метрах), пустой — модели нет.
func _place(id: String, rect: Rect2i, rotation: int, seed_value: int) -> Rect2:
	if id == "" or _props == null:
		return Rect2()
	var p := _props.get_prop(id)
	if p == null or p.meshes.is_empty():
		return Rect2()
	var degrees := float(rotation)
	if p.spin == PropCatalog.SPIN_QUARTER:
		degrees += 90.0 * float(seed_value % 4)
	elif p.spin == PropCatalog.SPIN_FREE:
		degrees += float(seed_value % 360)
	var quarter := p.spin != PropCatalog.SPIN_FREE and int(roundf(degrees / 90.0)) % 2 == 1
	var ax := p.aabb.size.z if quarter else p.aabb.size.x
	var az := p.aabb.size.x if quarter else p.aabb.size.z
	var fw := rect.size.x * CELL
	var fd := rect.size.y * CELL
	var shrink := 1.0 - p.jitter * float((seed_value / 7) % 100) / 100.0
	var s := minf(fw / maxf(ax, 0.01), fd / maxf(az, 0.01)) * p.fit * shrink
	var basis := Basis(Vector3.UP, deg_to_rad(degrees)).scaled(Vector3.ONE * s)
	var center := Vector3(
		(rect.position.x + (rect.size.x - 1) / 2.0) * CELL,
		0.0,
		(rect.position.y + (rect.size.y - 1) / 2.0) * CELL
	)
	var local := Vector3(p.aabb.get_center().x, p.aabb.position.y, p.aabb.get_center().z)
	var list: Array = _instances.get(id, [])
	list.append(Transform3D(basis, center - basis * local))
	_instances[id] = list
	var size := Vector2(ax * s, az * s)
	return Rect2(Vector2(center.x, center.z) - size / 2.0, size)


func _pick(key: String, c: Vector2i) -> String:
	var list := JsonRead.get_str_array(area.style, key)
	if list.is_empty():
		return ""
	return list[_hash(c) % list.size()]


## Одинаковый для клетки «случай»: облик не меняется от запуска к запуску.
static func _hash(c: Vector2i) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663)) % 1000003


## Все экземпляры каждой модели — одной отрисовкой на меш.
func _flush() -> void:
	var ids: Array[String] = []
	ids.assign(_instances.keys())
	ids.sort()
	for id in ids:
		var p := _props.get_prop(id)
		var list: Array = _instances[id]
		for i in p.meshes.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p.meshes[i]
			mm.instance_count = list.size()
			for j in list.size():
				var xf: Transform3D = list[j]
				mm.set_instance_transform(j, xf * p.transforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
	if _props != null:
		for err in _props.errors:
			push_error(err)


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
