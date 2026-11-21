class_name ReactionDialog
extends PanelContainer
## Вопрос о реакции посреди чужого хода (ADR-0023): что случилось, что даст реакция,
## две кнопки. Ответ — сигнал [signal answered].

signal answered(accepted: bool)

var _text := Label.new()
var _detail := Label.new()
var _yes := Button.new()
var _no := Button.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel",
		UiStyle.box(
			UiStyle.PANEL_BG.lightened(0.05), UiStyle.cost_color(ActionDef.COST_REACTION), 2, 8
		)
	)
	custom_minimum_size = Vector2(440, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_REACTION")
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UiStyle.cost_color(ActionDef.COST_REACTION))
	box.add_child(title)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_text)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	box.add_child(_detail)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	UiStyle.style_cost_button(_no, ActionDef.COST_FREE, false)
	UiStyle.style_cost_button(_yes, ActionDef.COST_REACTION, false)
	_no.pressed.connect(func() -> void: _answer(false))
	_yes.pressed.connect(func() -> void: _answer(true))
	buttons.add_child(_no)
	buttons.add_child(_yes)
	visible = false


## Показывает вопрос; ответ придёт сигналом [signal answered].
func ask(text: String, detail: String, yes_label: String, no_label: String) -> void:
	_text.text = text
	_detail.text = detail
	_detail.visible = detail != ""
	_yes.text = yes_label
	_no.text = no_label
	visible = true
	_yes.grab_focus()


func _answer(accepted: bool) -> void:
	visible = false
	answered.emit(accepted)
