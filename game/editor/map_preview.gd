class_name MapPreview
extends PanelContainer
## Предпросмотр области в 3D поверх редактора (ADR-0041): тот же облик, что в игре
## (AreaView, свет, модели и текстуры модулей). Колесо — масштаб, WASD и средняя
## кнопка — сдвиг, Q/E — поворот, G — сетка.

var _viewport := SubViewport.new()
var _world := Node3D.new()
var _camera := ArenaCamera.new()
var _view: AreaView = null


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


## Строит облик области [param data] заново и показывает окно.
func open(area_id: String, data: Dictionary, content: ModuleContent) -> void:
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
	_camera.frame(area.width(), area.depth(), BattleGrid.CELL_SIZE_M)
	var center := Vector3(area.width() * 0.75, 0.0, area.depth() * 0.75)
	_camera.focus(center, 1.6)
	visible = true


func hide_preview() -> void:
	visible = false
	for child in _world.get_children():
		if child != _camera:
			_world.remove_child(child)
			child.queue_free()
	_view = null


func _on_input(event: InputEvent) -> void:
	_camera.handle_input(event)
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_G and _view != null:
		_view.set_grid_visible(not _view.is_grid_visible())
