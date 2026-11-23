class_name MapPreview
extends PanelContainer
## Предпросмотр области в 3D поверх редактора (ADR-0041): тот же облик, что в игре
## (AreaView, свет, модели и текстуры модулей). Колесо — масштаб, WASD и средняя
## кнопка — сдвиг, Q/E — поворот, G — сетка. Левый клик по земле — клетка уходит
## в [signal cell_clicked]: инструмент карты ставит туда модель, выход и прочее.

signal cell_clicked(cell: Vector2i)

var _viewport := SubViewport.new()
var _world := Node3D.new()
var _camera := MapCamera.new()
var _view: AreaView = null
var _area_id := ""


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.05, 0.05, 0.06, 0.98), UiStyle.ACTIVE.darkened(0.3), 1, 6)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var bar := HBoxContainer.new()
	var title := Label.new()
	title.text = tr("UI_MAP_PREVIEW_TITLE")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	var close := Button.new()
	close.text = tr("UI_EQ_CLOSE")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide_preview)
	bar.add_child(close)
	box.add_child(bar)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.gui_input.connect(_on_input)
	box.add_child(container)
	_viewport.own_world_3d = true
	container.add_child(_viewport)
	_viewport.add_child(_world)
	_world.add_child(_camera)


## Строит облик области [param data] заново и показывает окно. [param keep_camera] —
## после правки камера остаётся где была.
func open(
	area_id: String, data: Dictionary, content: ModuleContent, keep_camera: bool = false
) -> void:
	keep_camera = keep_camera and visible and area_id == _area_id
	_area_id = area_id
	for child in _world.get_children():
		if child != _camera:
			_world.remove_child(child)
			child.queue_free()
	var env := SceneEnv.add_to(_world)
	var area := AreaMap.from_dict(area_id, data)
	if area.interior:
		SceneEnv.make_interior(env)
	_view = AreaView.new()
	_view.build(area, PropCatalog.from_content(content), SurfaceCatalog.from_content(content))
	_world.add_child(_view)
	_camera.current = true
	if not keep_camera:
		_camera.frame(area.width(), area.depth(), BattleGrid.CELL_SIZE_M)
		var center := Vector3(area.width() * 0.75, 0.0, area.depth() * 0.75)
		_camera.focus(center, 1.6)
	visible = true


## Клетка земли под точкой окна предпросмотра (луч по слою рельефа); (-1, -1) — мимо.
func _cell_under(pos: Vector2) -> Vector2i:
	var origin := _camera.project_ray_origin(pos)
	var to := origin + _camera.project_ray_normal(pos) * 400.0
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = AreaView.TERRAIN_LAYER
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector2i(-1, -1)
	var at: Vector3 = hit["position"]
	var cell := BattleGrid.CELL_SIZE_M
	return Vector2i(roundi(at.x / cell), roundi(at.z / cell))


func hide_preview() -> void:
	visible = false
	for child in _world.get_children():
		if child != _camera:
			_world.remove_child(child)
			child.queue_free()
	_view = null


func _on_input(event: InputEvent) -> void:
	_camera.handle_input(event)
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_under(click.position)
		if cell.x >= 0:
			cell_clicked.emit(cell)
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_G and _view != null:
		_view.set_grid_visible(not _view.is_grid_visible())
