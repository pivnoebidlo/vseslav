class_name UiStyle
extends RefCounted
## Общие цвета и стили интерфейса боя: команды, стоимость действий, панели, полоски хитов.

const TEAM_COLORS: Dictionary[String, Color] = {
	"party": Color(0.25, 0.5, 0.95),
	"bandits": Color(0.85, 0.2, 0.15),
	"beasts": Color(0.9, 0.55, 0.1),
	"nechist": Color(0.6, 0.25, 0.85),
	"village": Color(0.85, 0.78, 0.45),
}
## Цвет стоимости действия: действие — тёплый, бонусное — зелёный, свободное — серый.
const COST_COLORS: Dictionary[String, Color] = {
	ActionDef.COST_ACTION: Color(0.93, 0.55, 0.2),
	ActionDef.COST_BONUS: Color(0.35, 0.8, 0.4),
	ActionDef.COST_FREE: Color(0.65, 0.68, 0.72),
	ActionDef.COST_REACTION: Color(0.55, 0.65, 0.95),
}
const PANEL_BG := Color(0.1, 0.11, 0.13, 0.86)
const ACTIVE := Color(1.0, 0.85, 0.35)
const HP_GOOD := Color(0.4, 0.85, 0.4)
const HP_HURT := Color(0.95, 0.8, 0.25)
const HP_LOW := Color(0.95, 0.35, 0.3)


static func team_color(team: String) -> Color:
	return TEAM_COLORS.get(team, Color.GRAY)


static func cost_color(cost: String) -> Color:
	return COST_COLORS.get(cost, Color.GRAY)


static func hp_color(hp: int, max_hp: int) -> Color:
	var ratio := float(hp) / float(maxi(max_hp, 1))
	if ratio <= 0.25:
		return HP_LOW
	if ratio <= 0.5:
		return HP_HURT
	return HP_GOOD


## Плоская панель: фон, рамка заданной толщины, скругление.
static func box(
	bg: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 6
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func panel(container: PanelContainer, border: Color = Color.TRANSPARENT) -> void:
	container.add_theme_stylebox_override("panel", box(PANEL_BG, border, 1 if border.a > 0 else 0))


## Полоска хитов (ProgressBar без текста) с цветом по доле.
static func hp_bar(hp: int, max_hp: int, height: int = 6) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(max_hp, 1)
	bar.value = hp
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(
		"background", box(Color(0, 0, 0, 0.55), Color.TRANSPARENT, 0, 2)
	)
	var fill := box(hp_color(hp, max_hp), Color.TRANSPARENT, 0, 2)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## Кнопка в цвете стоимости действия.
static func style_cost_button(button: Button, cost: String, selected: bool) -> void:
	var c := cost_color(cost)
	var normal := box(c.darkened(0.72), c.darkened(0.25), 1, 5)
	var hover := box(c.darkened(0.6), c, 1, 5)
	var pressed := box(c.darkened(0.45), ACTIVE, 2, 5)
	var disabled := box(Color(0.18, 0.18, 0.2, 0.8), Color(0.3, 0.3, 0.32), 1, 5)
	button.add_theme_stylebox_override("normal", pressed if selected else normal)
	button.add_theme_stylebox_override("hover", pressed if selected else hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", c.lightened(0.55))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.52))
