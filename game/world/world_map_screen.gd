class_name WorldMapScreen
extends PanelContainer
## Глобальная карта (ADR-0051): схема городов и дорог с днями пути. Выбор города — путь:
## дни идут, отряд переходит в город. Карта работает в городах; вне их — только смотреть.

## Выбран город [param city_id]; закрытие экрана — в [method close].
signal travel_chosen(city_id: String)

const SCHEME_SIZE := Vector2(520, 320)
const CITY_RADIUS := 7.0

var _map: WorldMap
var _here := ""
var _day := 1
var _scheme := Control.new()
var _info := Label.new()
var _destinations := VBoxContainer.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.13, 0.15), Color(0.45, 0.5, 0.6), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_MAP_TITLE")
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = TranslationServer.translate("UI_EQ_CLOSE")
	UiStyle.style_cost_button(close_button, ActionDef.COST_REACTION, false)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_scheme.custom_minimum_size = SCHEME_SIZE
	_scheme.draw.connect(_draw_scheme)
	box.add_child(_scheme)
	_info.add_theme_font_size_override("font_size", 12)
	box.add_child(_info)
	box.add_child(_destinations)
	visible = false


## Показать карту [param map]; [param here] — город, где отряд сейчас (пусто — в пути).
func open(map: WorldMap, here: String, day: int) -> void:
	_map = map
	_here = here
	_day = day
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func _rebuild() -> void:
	if _here == "":
		_info.text = TranslationServer.translate("UI_MAP_NOT_IN_CITY")
	else:
		_info.text = CombatLogFormat.tr_fmt(
			"UI_MAP_DAY",
			{"day": _day, "city": TranslationServer.translate(_map.city(_here).name_key)}
		)
	for child in _destinations.get_children():
		_destinations.remove_child(child)
		child.queue_free()
	for id in _map.sorted_ids():
		if id == _here:
			continue
		var days := _map.days_between(_here, id)
		var button := Button.new()
		button.text = CombatLogFormat.tr_fmt(
			"UI_MAP_TRAVEL_TO",
			{"city": TranslationServer.translate(_map.city(id).name_key), "days": days}
		)
		button.disabled = _here == "" or days < 1
		button.pressed.connect(func() -> void: travel_chosen.emit(id))
		_destinations.add_child(button)
	_scheme.queue_redraw()


## Схема: дороги с числом дней, города; город, где отряд, — подсвечен.
func _draw_scheme() -> void:
	if _map == null:
		return
	var font := _scheme.get_theme_default_font()
	for road in _map.roads:
		var a := _point(_map.city(road.a))
		var b := _point(_map.city(road.b))
		_scheme.draw_line(a, b, Color(0.7, 0.6, 0.4), 3.0)
		_scheme.draw_string(font, (a + b) / 2.0, str(road.days), 0, -1, 13)
	for id in _map.sorted_ids():
		var city := _map.city(id)
		var color := UiStyle.ACTIVE if id == _here else Color(0.85, 0.85, 0.9)
		_scheme.draw_circle(_point(city), CITY_RADIUS, color)
		_scheme.draw_string(
			font,
			_point(city) + Vector2(CITY_RADIUS + 4, 4),
			TranslationServer.translate(city.name_key),
			0,
			-1,
			14
		)


## Место города на схеме в пикселях (координаты 0–1000 из данных).
func _point(city: WorldMap.City) -> Vector2:
	return Vector2(city.at) * _scheme.size / 1000.0
