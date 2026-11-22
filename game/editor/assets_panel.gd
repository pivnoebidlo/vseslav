class_name AssetsPanel
extends ScrollContainer
## Свои ассеты модуля (ADR-0041): модели окружения (GLB) и поверхности (PNG).
## Файл с диска проверяется теми же загрузчиками, что в игре (CharacterLoader,
## SurfaceCatalog), копируется в модуль и регистрируется; потом его можно ставить
## на карту и в стиль области. Лицензию автор записывает в CREDITS.md.

signal edited(edit: DocEdit)
signal message(lines: Array[String])

const SPINS: Array[String] = ["none", "quarter", "free"]
const DEFAULT_TILE := 3.0

## (заголовок, подсказка, обработчик(id, текст), занят(id)) — окно ввода id у экрана.
var ask_id: Callable

var _doc: ModuleDoc
var _content: ModuleContent
var _editable := true
var _box := VBoxContainer.new()
var _dialog := FileDialog.new()
var _picking := ""
## Файл облика → имена узлов, которые можно держать в руках (кэш, чтобы не грузить
## модель при каждой перерисовке).
var _holdable: Dictionary[String, PackedStringArray] = {}


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(func(path: String) -> void: _on_files([path]))
	_dialog.files_selected.connect(func(paths: PackedStringArray) -> void: _on_files(paths))
	add_child(_dialog)


func show_assets(doc: ModuleDoc, content: ModuleContent, editable: bool) -> void:
	_doc = doc
	_content = content
	_editable = editable
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if doc == null:
		return
	_box.add_child(_heading(tr("UI_AS_TITLE") + " " + doc.module_id()))
	_box.add_child(_caption(tr("UI_AS_LICENSE")))
	_box.add_child(_heading(tr("UI_AS_PROPS")))
	var own := AssetOps.prop_ids(doc)
	if own.is_empty():
		_box.add_child(_caption(tr("UI_AS_NONE")))
	for id in own:
		_box.add_child(_prop_row(id))
	if editable:
		_box.add_child(_button("UI_AS_ADD_PROP", func() -> void: _pick("prop")))
	_box.add_child(_caption(tr("UI_AS_ALL_PROPS") % _content.props.size()))
	_box.add_child(HSeparator.new())
	_box.add_child(_heading(tr("UI_AS_SURFACES")))
	var surfaces := AssetOps.surface_ids(doc)
	if surfaces.is_empty():
		_box.add_child(_caption(tr("UI_AS_NONE")))
	for id in surfaces:
		_box.add_child(_surface_row(id))
	if editable:
		_box.add_child(_button("UI_AS_ADD_SURFACE", func() -> void: _pick("surface")))
	_box.add_child(_caption(tr("UI_AS_SURFACE_HINT")))
	_box.add_child(HSeparator.new())
	_box.add_child(_heading(tr("UI_AS_FIGURES")))
	var figures := AssetOps.figure_ids(doc)
	if figures.is_empty():
		_box.add_child(_caption(tr("UI_AS_NONE")))
	for id in figures:
		_box.add_child(_figure_row(id))
	if editable:
		_box.add_child(_button("UI_AS_ADD_FIGURE", func() -> void: _pick("figure")))
	_box.add_child(_caption(tr("UI_AS_FIGURE_HINT")))


# --- Модели -------------------------------------------------------------------------


func _prop_row(id: String) -> PanelContainer:
	var entry: Dictionary = _doc.get_value(AssetOps.PROPS, AssetOps.PROPS, ["props", id])
	var panel := _panel()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "%s  (%s)" % [id, JsonRead.get_str(entry, "file")]
	box.add_child(title)
	var row := HBoxContainer.new()
	var fit := _spin(tr("UI_AS_FIT"), 0.1, 4.0, 0.05, _num(entry, "fit", 1.0))
	var jitter := _spin(tr("UI_AS_JITTER"), 0.0, 0.5, 0.05, _num(entry, "jitter", 0.0))
	var spin := OptionButton.new()
	for s in SPINS:
		spin.add_item(tr("UI_AS_SPIN_" + s.to_upper()))
		if s == JsonRead.get_str(entry, "spin", "none"):
			spin.select(spin.item_count - 1)
	spin.disabled = not _editable
	var commit := func() -> void:
		var file := JsonRead.get_str(entry, "file")
		var s := SPINS[maxi(spin.selected, 0)]
		edited.emit(AssetOps.register_prop(_doc, id, file, fit.value, jitter.value, s))
	fit.value_changed.connect(func(_v: float) -> void: commit.call())
	jitter.value_changed.connect(func(_v: float) -> void: commit.call())
	spin.item_selected.connect(func(_i: int) -> void: commit.call())
	row.add_child(fit)
	row.add_child(jitter)
	row.add_child(spin)
	box.add_child(row)
	return panel


func _import_prop(path: String) -> void:
	var profiles: Array[RigProfile] = []
	var model := CharacterLoader.load_file(path, profiles)
	var problems: Array[String] = []
	for err in model.errors:
		problems.append(tr(str(err["key"])).format(err.get("args", {})))
	var tris := model.triangles
	if model.root != null:
		model.root.free()
	if not problems.is_empty():
		message.emit(problems)
		return
	var add := func(id: String, _text: String) -> void:
		var errors: Array[String] = []
		var file := AssetOps.copy_file(_doc, path, AssetOps.PROPS, id, errors)
		if file == "":
			message.emit(errors)
			return
		var done: Array[String] = [tr("UI_AS_PROP_ADDED") % [id, tris]]
		message.emit(done)
		edited.emit(AssetOps.register_prop(_doc, id, file, 1.0, 0.0, "none"))
	var taken := func(id: String) -> bool:
		return id.contains(".") or _content.props.has(id) or AssetOps.prop_ids(_doc).has(id)
	ask_id.call(tr("UI_AS_PROP_ID"), "", add, taken)


# --- Поверхности --------------------------------------------------------------------


func _surface_row(id: String) -> PanelContainer:
	var entry: Dictionary = _doc.get_value(AssetOps.SURFACES, AssetOps.SURFACES, ["surfaces", id])
	var panel := _panel()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var files: PackedStringArray = []
	for key: String in ["color", "normal", "roughness"]:
		if JsonRead.get_str(entry, key) != "":
			files.append(JsonRead.get_str(entry, key))
	var title := Label.new()
	title.text = "%s  (%s)" % [id, ", ".join(files)]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var tile := _spin(tr("UI_AS_TILE"), 0.5, 16.0, 0.5, _num(entry, "tile", DEFAULT_TILE))
	tile.value_changed.connect(
		func(v: float) -> void: edited.emit(AssetOps.register_surface(_doc, id, entry, v))
	)
	box.add_child(tile)
	return panel


## Файлы поверхности: в имени normal — нормали, rough — шероховатость, иначе — цвет.
func _import_surface(paths: PackedStringArray) -> void:
	var roles := {}
	var problems: Array[String] = []
	for path in paths:
		if SurfaceCatalog.load_png(path) == null:
			problems.append(tr("UI_AS_BAD_PNG") % path.get_file())
			continue
		var name := path.get_file().to_lower()
		if name.contains("normal"):
			roles["normal"] = path
		elif name.contains("rough"):
			roles["roughness"] = path
		else:
			roles["color"] = path
	if not roles.has("color"):
		problems.append(tr("UI_AS_NO_COLOR"))
	if not problems.is_empty():
		message.emit(problems)
		return
	var add := func(id: String, _text: String) -> void:
		var errors: Array[String] = []
		var files := {}
		for role: String in roles:
			var file := AssetOps.copy_file(
				_doc, str(roles[role]), AssetOps.SURFACES, "%s_%s" % [id, role], errors
			)
			if file != "":
				files[role] = file
		if not errors.is_empty():
			message.emit(errors)
			return
		edited.emit(AssetOps.register_surface(_doc, id, files, DEFAULT_TILE))
	var taken := func(id: String) -> bool:
		return id.contains(".") or _content.surfaces.has(id) or AssetOps.surface_ids(_doc).has(id)
	ask_id.call(tr("UI_AS_SURFACE_ID"), "", add, taken)


# --- Облик персонажей ---------------------------------------------------------------


func _figure_row(id: String) -> PanelContainer:
	var entry: Dictionary = _doc.get_value(AssetOps.MODELS, AssetOps.MODELS, ["figures", id])
	var file := JsonRead.get_str(entry, "file")
	var panel := _panel()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "%s  (%s)" % [id, file]
	box.add_child(title)
	var hold := JsonRead.get_str_array(entry, "hold")
	var names := _holdable_of(_doc.dir.path_join(AssetOps.MODELS).path_join(file))
	if names.is_empty():
		box.add_child(_caption(tr("UI_AS_NO_HOLD")))
	else:
		box.add_child(_caption(tr("UI_AS_HOLD")))
		var flow := HFlowContainer.new()
		for n in names:
			var check := CheckBox.new()
			check.text = n
			check.button_pressed = hold.has(n)
			check.disabled = not _editable
			check.toggled.connect(
				func(on: bool) -> void:
					var changed := hold.duplicate()
					if on and not changed.has(n):
						changed.append(n)
					elif not on:
						changed.erase(n)
					edited.emit(AssetOps.register_figure(_doc, id, file, changed))
			)
			flow.add_child(check)
		box.add_child(flow)
	return panel


## Узлы снаряжения модели (дети слотов крепления рига): их можно показывать в руках.
func _holdable_of(path: String) -> PackedStringArray:
	if _holdable.has(path):
		return _holdable[path]
	var names := PackedStringArray()
	var model := CharacterLoader.load_file(path, RigProfile.load_all())
	if model.root != null:
		if model.rig != null:
			for slot_name in model.rig.attachment_slots:
				for slot in model.root.find_children(slot_name, "", true, false):
					for child in slot.get_children():
						if child is Node3D and not names.has(child.name):
							names.append(child.name)
		model.root.free()
	_holdable[path] = names
	return names


func _import_figure(path: String) -> void:
	var model := CharacterLoader.load_file(path, RigProfile.load_all())
	var lines: Array[String] = []
	for err in model.errors:
		lines.append(tr(str(err["key"])).format(err.get("args", {})))
	var ok := model.ok()
	var rig := model.rig.id if model.rig != null else ""
	var tris := model.triangles
	if model.root != null:
		model.root.free()
	if not ok:
		message.emit(lines)
		return
	var add := func(id: String, _text: String) -> void:
		var errors: Array[String] = []
		var file := AssetOps.copy_file(_doc, path, AssetOps.MODELS, id, errors)
		if file == "":
			message.emit(errors)
			return
		var done: Array[String] = [tr("UI_AS_FIGURE_ADDED") % [id, tris]]
		if rig == "":
			done.append(tr("UI_AS_NO_RIG"))
		message.emit(done)
		var none: Array[String] = []
		edited.emit(AssetOps.register_figure(_doc, id, file, none))
	var taken := func(id: String) -> bool:
		return id.contains(".") or _content.figures.has(id) or AssetOps.figure_ids(_doc).has(id)
	ask_id.call(tr("UI_AS_FIGURE_ID"), "", add, taken)


# --- Выбор файлов -------------------------------------------------------------------


func _pick(kind: String) -> void:
	_picking = kind
	if kind == "prop" or kind == "figure":
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.filters = PackedStringArray(["*.glb ; GLB"])
		_dialog.title = tr("UI_AS_ADD_PROP" if kind == "prop" else "UI_AS_ADD_FIGURE")
	else:
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_dialog.filters = PackedStringArray(["*.png ; PNG"])
		_dialog.title = tr("UI_AS_ADD_SURFACE")
	_dialog.popup_centered_ratio(0.7)


func _on_files(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	if _picking == "prop":
		_import_prop(paths[0])
	elif _picking == "figure":
		_import_figure(paths[0])
	else:
		_import_surface(paths)


# --- Поля ---------------------------------------------------------------------------


static func _num(entry: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = entry.get(key, fallback)
	if value is float:
		return value
	if value is int:
		var i: int = value
		return i
	return fallback


func _spin(prefix: String, lo: float, hi: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.prefix = prefix
	s.value = value
	s.editable = _editable
	s.custom_minimum_size = Vector2(200, 0)
	return s


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.14, 0.14, 0.16), Color(0.3, 0.3, 0.34), 1, 6)
	)
	return panel


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _button(key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b
