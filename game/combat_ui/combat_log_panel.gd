class_name CombatLogPanel
extends PanelContainer
## Журнал боя внизу слева: заголовок с кнопкой «свернуть». Свёрнутый журнал
## показывает последние строки и почти не закрывает поле.

const EXPANDED_HEIGHT := 170
const COLLAPSED_HEIGHT := 38

var _text := RichTextLabel.new()
var _toggle := Button.new()
var _collapsed := false


func _init() -> void:
	UiStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_LOG")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.add_theme_font_size_override("font_size", 12)
	_toggle.pressed.connect(_on_toggle)
	header.add_child(_toggle)
	_text.scroll_following = true
	_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_text)
	_apply()


func write(text: String, color: Color = Color.WHITE) -> void:
	_text.push_color(color)
	_text.add_text(text)
	_text.pop()
	_text.newline()


func clear() -> void:
	_text.clear()


func _on_toggle() -> void:
	_collapsed = not _collapsed
	_apply()


func _apply() -> void:
	_text.custom_minimum_size = Vector2(0, COLLAPSED_HEIGHT if _collapsed else EXPANDED_HEIGHT)
	_toggle.text = TranslationServer.translate("UI_LOG_EXPAND" if _collapsed else "UI_LOG_COLLAPSE")
