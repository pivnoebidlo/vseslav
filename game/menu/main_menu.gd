class_name MainMenu
extends Control
## Главное меню: продолжить (последнее сохранение), новая игра, выход. Бой идёт прямо
## на карте (ADR-0032). Тестовая арена — инструмент разработчика: открывается только
## запуском с аргументами (--arena, --autoplay, --screenshot, …) для баланса и проверок.

const SCENE := "res://game/menu/main_menu.tscn"
const ARENA_SCENE := "res://game/arena/arena.tscn"
const EXPLORATION_SCENE := "res://game/exploration/exploration.tscn"
const DEFAULT_LANG := "ru"

## Меню уже открывалось: аргументы запуска ведут на арену только в первый раз,
## а «В меню» с арены показывает меню.
static var _visited := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var lang := DEFAULT_LANG
	var direct := false
	for arg in args:
		if arg.begins_with("--lang="):
			lang = arg.trim_prefix("--lang=")
		else:
			direct = true
	TranslationServer.set_locale(lang)
	var first := not _visited
	_visited = true
	if direct and first:
		_open.call_deferred(ARENA_SCENE)
		return
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = tr("UI_GAME_TITLE")
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = tr("UI_MENU_SUBTITLE")
	subtitle.modulate = Color(1, 1, 1, 0.6)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(HSeparator.new())
	if SaveStore.has_any():
		_button(box, "UI_MENU_CONTINUE", _continue)
	_button(box, "UI_MENU_EXPLORE", _new_game)
	_button(box, "UI_MENU_QUIT", get_tree().quit)
	var first: Button = box.get_child(3)
	first.grab_focus.call_deferred()


func _button(box: VBoxContainer, key: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.custom_minimum_size = Vector2(340, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	box.add_child(b)
	return b


func _continue() -> void:
	var errors: Array[String] = []
	SaveStore.pending = SaveStore.latest(errors)
	SaveStore.new_game = false
	_open(EXPLORATION_SCENE)


func _new_game() -> void:
	SaveStore.pending = null
	SaveStore.new_game = true
	_open(EXPLORATION_SCENE)


func _open(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
