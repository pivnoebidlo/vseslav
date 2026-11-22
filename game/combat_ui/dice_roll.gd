class_name DiceRoll
extends PanelContainer
## Анимация броска d20 (в бою и в диалогах): кубик крутится, падает на выпавшее,
## ниже — «13 + 2 = 15 против СЛ 15 — успех». При преимуществе и помехе — два кубика,
## невзятый тускнеет. Клик или любая клавиша — досмотреть сразу.

signal finished

const SPIN_TIME := 0.6
const HOLD_TIME := 0.9
const FLICK := 0.05
const DIE_SIZE := 76.0
const GOOD := Color(0.55, 0.95, 0.55)
const BAD := Color(1.0, 0.5, 0.45)


## Грань кубика: шестиугольник с треугольником внутри и числом.
class DieFace:
	extends Control
	var value := 20
	var dim := false
	var tint := Color(0.92, 0.9, 0.82)

	func _init() -> void:
		custom_minimum_size = Vector2(DIE_SIZE, DIE_SIZE)
		pivot_offset = custom_minimum_size / 2.0

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.48
		var hex := PackedVector2Array()
		for i in 6:
			hex.append(c + Vector2.from_angle(deg_to_rad(60.0 * i - 90.0)) * r)
		var face := Color(0.16, 0.15, 0.2) if not dim else Color(0.12, 0.12, 0.14)
		var edge := tint if not dim else tint.darkened(0.6)
		draw_colored_polygon(hex, face)
		hex.append(hex[0])
		draw_polyline(hex, edge, 2.5, true)
		var tri := PackedVector2Array(
			[hex[0].lerp(c, 0.45), hex[2].lerp(c, 0.45), hex[4].lerp(c, 0.45)]
		)
		tri.append(tri[0])
		draw_polyline(tri, edge.darkened(0.35), 1.5, true)
		var font := get_theme_default_font()
		var text := str(value)
		var fs := 30
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(
			font, c + Vector2(-w / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, edge
		)


var _title := Label.new()
var _dice_row := HBoxContainer.new()
var _result := Label.new()
var _faces: Array[DieFace] = []
var _rolls: Array[int] = []
var _kept := 0
var _time := 0.0
var _flick := 0.0
var _playing := false


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.08, 0.08, 0.1, 0.94), UiStyle.ACTIVE.darkened(0.3), 1, 10)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.3
	anchor_bottom = 0.3
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override("separation", 14)
	box.add_child(_dice_row)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 18)
	_result.custom_minimum_size = Vector2(380, 0)
	box.add_child(_result)
	visible = false
	set_process(false)


## Показывает бросок. [param rolls] — выпавшие d20 (два при преимуществе/помехе),
## [param kept] — взятый. Ждать окончания — `await dice.finished`.
func play(title: String, rolls: Array[int], kept: int, result_text: String, good: bool) -> void:
	_title.text = title
	_rolls = rolls.duplicate()
	if _rolls.is_empty():
		_rolls = [kept]
	_kept = kept
	for f in _faces:
		f.queue_free()
	_faces.clear()
	for i in _rolls.size():
		var f := DieFace.new()
		_dice_row.add_child(f)
		_faces.append(f)
	_result.text = result_text
	_result.add_theme_color_override("font_color", GOOD if good else BAD)
	_result.modulate.a = 0.0
	_time = 0.0
	_flick = 0.0
	_playing = true
	visible = true
	reset_size()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _time < SPIN_TIME:
		_flick -= delta
		if _flick <= 0.0:
			_flick = FLICK
			for f in _faces:
				f.value = randi_range(1, 20)
				f.rotation = randf_range(-0.5, 0.5)
				f.queue_redraw()
		return
	if _result.modulate.a == 0.0:
		_land()
	if _time >= SPIN_TIME + HOLD_TIME:
		_finish()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_skip()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _playing and key != null and key.pressed:
		_skip()
		get_viewport().set_input_as_handled()


func _skip() -> void:
	if _time < SPIN_TIME:
		_time = SPIN_TIME
		_land()
	else:
		_finish()


func _land() -> void:
	var kept_index := _rolls.find(_kept)
	for i in _faces.size():
		var f := _faces[i]
		f.value = _rolls[i]
		f.rotation = 0.0
		f.dim = _faces.size() > 1 and i != kept_index
		if _rolls[i] == 20:
			f.tint = Color(1.0, 0.82, 0.3)
		elif _rolls[i] == 1:
			f.tint = BAD
		f.queue_redraw()
	_result.modulate.a = 1.0


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	set_process(false)
	visible = false
	finished.emit()
