class_name Loading
extends RefCounted
## Экран загрузки (ADR-0040): большая область собирается пару секунд, и всё это время
## игра «висит». Перед сменой сцены поверх текущей рисуется «Загрузка…», и только
## потом начинается сборка — замерший кадр показывает надпись, а не старую картинку.

const LAYER := 128
const KEY := "UI_LOADING"


## Показывает «Загрузка…» поверх [param from] и через кадр меняет сцену на [param path].
static func change_scene(from: Node, path: String) -> void:
	var tree := from.get_tree()
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.07, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var label := Label.new()
	label.text = TranslationServer.translate(KEY)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg.add_child(label)
	tree.root.add_child(layer)
	# Два кадра: надпись успевает попасть на экран до тяжёлой сборки новой сцены.
	await tree.process_frame
	await tree.process_frame
	tree.change_scene_to_file(path)
	await tree.process_frame
	await tree.process_frame
	layer.queue_free()
