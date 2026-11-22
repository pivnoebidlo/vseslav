class_name ArenaCamera
extends Camera3D
## Камера арены: смотрит на поле сверху-спереди; колесо мыши приближает и отдаляет,
## WASD, стрелки и средняя кнопка мыши сдвигают.

const OFFSET := Vector3(0.0, 14.0, 10.0)
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.3
const ZOOM_STEP := 0.1
const PAN_STEP := 0.75
const PAN_DRAG_SPEED := 0.02

var _target := Vector3.ZERO
var _zoom := 1.1
var _size := Vector3.ZERO


## Наводит камеру на поле размером [param width] × [param depth] клеток по [param cell] м.
func frame(width: int, depth: int, cell: float) -> void:
	fov = 50.0
	_size = Vector3(width * cell, 0.0, depth * cell)
	var center := Vector3((width - 1) * cell / 2.0, 0.0, (depth - 1) * cell / 2.0)
	# Цель взгляда смещена к камере, чтобы поле не уходило под журнал внизу экрана.
	_target = center + Vector3(-1.5, 0.0, 2.0)
	_zoom = 1.1
	_place()


## Следить за точкой (исследование): цель взгляда — [param point], масштаб — [param zoom].
func focus(point: Vector3, zoom: float = -1.0) -> void:
	fov = 50.0
	if zoom > 0.0:
		_zoom = clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	_target = point
	_place()


## Обрабатывает ввод камеры; true — событие использовано.
func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed:
		return _pan_by_key(key.keycode)
	var motion := event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_pan(Vector3(-motion.relative.x, 0.0, -motion.relative.y) * PAN_DRAG_SPEED * _zoom)
		return true
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		if click.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(ZOOM_MIN, _zoom - ZOOM_STEP)
			_place()
			return true
		if click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(ZOOM_MAX, _zoom + ZOOM_STEP)
			_place()
			return true
	return false


func _pan_by_key(keycode: Key) -> bool:
	match keycode:
		KEY_A, KEY_LEFT:
			_pan(Vector3(-PAN_STEP, 0.0, 0.0))
		KEY_D, KEY_RIGHT:
			_pan(Vector3(PAN_STEP, 0.0, 0.0))
		KEY_W, KEY_UP:
			_pan(Vector3(0.0, 0.0, -PAN_STEP))
		KEY_S, KEY_DOWN:
			_pan(Vector3(0.0, 0.0, PAN_STEP))
		_:
			return false
	return true


func _pan(delta: Vector3) -> void:
	_target = (_target + delta).clamp(-_size * 0.25, _size * 1.25)
	_place()


func _place() -> void:
	position = _target + OFFSET * _zoom
	look_at(_target)
