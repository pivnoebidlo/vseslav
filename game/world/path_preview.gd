class_name PathPreview
extends Node3D
## Путь под курсором, как в BG3: точки по земле от героя до цели и кольцо в конце.
## Общий для исследования и боя.

const DOT_STEP := 0.4
const Y := 0.06
const COLOR := Color(1.0, 0.97, 0.85, 0.9)

var _dots: Array[MeshInstance3D] = []
var _end := MeshInstance3D.new()
var _dot_mesh := CylinderMesh.new()
var _mat := StandardMaterial3D.new()


func _init() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = COLOR
	_dot_mesh.top_radius = 0.07
	_dot_mesh.bottom_radius = 0.07
	_dot_mesh.height = 0.01
	var ring := TorusMesh.new()
	ring.inner_radius = 0.32
	ring.outer_radius = 0.42
	_end.mesh = ring
	_end.material_override = _mat
	_end.scale = Vector3(1.0, 0.2, 1.0)
	add_child(_end)
	visible = false


## Точки пути (первая — где стоит герой).
func show_points(points: Array[Vector3]) -> void:
	if points.size() < 2:
		clear()
		return
	var used := 0
	var left := DOT_STEP
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var length := a.distance_to(b)
		var along := left
		while along < length:
			_dot(used).position = a.lerp(b, along / length) + Vector3(0.0, Y, 0.0)
			used += 1
			along += DOT_STEP
		left = along - length
	for i in range(used, _dots.size()):
		_dots[i].visible = false
	_end.position = points[-1] + Vector3(0.0, Y, 0.0)
	visible = true


func clear() -> void:
	visible = false


## Путь в бою к клетке [param cell], если до неё хватает перемещения.
## [param to_world] — колонка сетки → точка в мире.
func show_combat(state: CombatState, actor: Combatant, cell: Vector2i, to_world: Callable) -> void:
	if cell == ActionResolver.NO_CELL or not MoveCommand.reachable_for(state, actor).has(cell):
		clear()
		return
	var p := MoveCommand.path_for(state, actor, cell)
	var start: Vector3 = to_world.call(actor.column)
	var points: Array[Vector3] = [start]
	for c in p.cells:
		var at: Vector3 = to_world.call(Vector2i(c.x, c.z))
		points.append(at)
	show_points(points)


func _dot(index: int) -> MeshInstance3D:
	while _dots.size() <= index:
		var d := MeshInstance3D.new()
		d.mesh = _dot_mesh
		d.material_override = _mat
		add_child(d)
		_dots.append(d)
	_dots[index].visible = true
	return _dots[index]
