extends Node3D
## Спайк этапа 0: загрузка моделей GLB из папки вне проекта и ретаргетинг анимаций.
##
## Аргументы (после `--`):
##   --models=DIR       папка с .glb (по умолчанию user://models)
##   --mode=own|retarget  своя анимация модели или анимация источника на всех моделях
##   --anim=NAME        анимация по умолчанию
##   --lang=ru|en       язык интерфейса
##   --screenshot=PATH  снимок экрана через 3 с и выход

const DEFAULT_DIR := "user://models"
const SPACING := 2.8
const PREFERRED_ANIMS: Array[String] = ["Walking_A", "Idle", "Swing"]

var _dir := DEFAULT_DIR
var _retarget_mode := true
var _anim := ""
var _lang := "ru"
var _screenshot_path := ""

var _profiles: Array[RigProfile] = []
var _source_path := ""
var _source_anims: PackedStringArray = []
var _stage: Node3D
var _info := Label.new()
var _anim_label := Label.new()
var _mode_button := Button.new()


func _ready() -> void:
	_parse_args()
	TranslationServer.set_locale(_lang)
	_profiles = RigProfile.load_all()
	_setup_environment()
	_setup_ui()
	_stage = Node3D.new()
	add_child(_stage)
	_find_animation_source()
	_rebuild()
	if _screenshot_path != "":
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("Screenshot saved: %s" % _screenshot_path)
		get_tree().quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			_dir = arg.trim_prefix("--models=")
		elif arg == "--mode=own":
			_retarget_mode = false
		elif arg == "--mode=retarget":
			_retarget_mode = true
		elif arg.begins_with("--anim="):
			_anim = arg.trim_prefix("--anim=")
		elif arg.begins_with("--lang="):
			_lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")


func _model_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(_dir)
	if dir == null:
		return paths
	for file in dir.get_files():
		if file.get_extension().to_lower() == "glb":
			paths.append(_dir.path_join(file))
	paths.sort()
	return paths


## Источник анимаций — первая распознанная модель с анимациями.
func _find_animation_source() -> void:
	for path in _model_paths():
		var model := CharacterLoader.load_file(path, _profiles)
		var anims := model.animations()
		var usable := model.ok() and model.rig != null and not anims.is_empty()
		if model.root != null:
			model.root.free()
		if usable:
			_source_path = path
			_source_anims = anims
			break
	if _anim == "" or not _source_anims.has(_anim):
		_anim = ""
		for name in PREFERRED_ANIMS:
			if _source_anims.has(name):
				_anim = name
				break
		if _anim == "" and not _source_anims.is_empty():
			_anim = _source_anims[0]


func _rebuild() -> void:
	for child in _stage.get_children():
		child.queue_free()
	var paths := _model_paths()
	if paths.is_empty():
		_info.text = tr("VIEWER_NO_MODELS").format({"dir": ProjectSettings.globalize_path(_dir)})
	else:
		_info.text = tr("VIEWER_DIR").format({"dir": ProjectSettings.globalize_path(_dir)})
	for i in paths.size():
		var x := (i - (paths.size() - 1) / 2.0) * SPACING
		_place_model(paths[i], Vector3(x, 0, 0))
	_update_labels()


func _place_model(path: String, at: Vector3) -> void:
	var model := CharacterLoader.load_file(path, _profiles)
	var lines: PackedStringArray = [path.get_file()]
	if not model.ok():
		for e in model.errors:
			lines.append(_format(e))
		_add_label(at, "\n".join(lines), Color(1.0, 0.5, 0.45))
		if model.root != null:
			model.root.free()
		return

	var rig_title := model.rig.title if model.rig != null else tr("VIEWER_RIG_UNKNOWN")
	lines.append(
		tr("VIEWER_STATS").format({"rig": rig_title, "tris": model.triangles, "bones": model.bones})
	)
	for w in model.warnings:
		lines.append(_format(w))

	var shown: Node3D = model.root
	var player := model.animation_player
	var retargeted := false
	if _retarget_mode and _source_path != "" and path != _source_path and model.rig != null:
		var source := CharacterLoader.load_file(_source_path, _profiles)
		if source.ok() and Retarget.attach(source, model):
			player = source.animation_player
			retargeted = true
		elif source.root != null:
			source.root.free()
	if retargeted:
		lines.append(tr("VIEWER_RETARGETED").format({"source": _source_path.get_file()}))
	_stage.add_child(shown)
	shown.position = at
	_play(player)
	_add_label(
		at, "\n".join(lines), Color.WHITE if model.warnings.is_empty() else Color(1, 0.85, 0.5)
	)


func _play(player: AnimationPlayer) -> void:
	if player == null:
		return
	var list := player.get_animation_list()
	var name := _anim if list.has(_anim) else ""
	if name == "":
		for preferred in PREFERRED_ANIMS:
			if list.has(preferred):
				name = preferred
				break
	if name == "" and not list.is_empty():
		name = list[0]
	if name == "":
		return
	var anim := player.get_animation(name)
	anim.loop_mode = Animation.LOOP_LINEAR
	player.play(name)


func _format(entry: Dictionary) -> String:
	var args: Dictionary = entry.get("args", {})
	return tr(str(entry["key"])).format(args)


func _add_label(at: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 32
	label.pixel_size = 0.005
	label.outline_size = 10
	label.position = at + Vector3(0, 2.6, 0)
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stage.add_child(label)


func _update_labels() -> void:
	_mode_button.text = tr("VIEWER_MODE_RETARGET") if _retarget_mode else tr("VIEWER_MODE_OWN")
	_anim_label.text = tr("VIEWER_ANIM").format({"anim": _anim if _anim != "" else "—"})


# --- Окружение и интерфейс ----------------------------------------------------


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 10)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.5, 0.3)
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 2.0, 7.0)
	camera.look_at(Vector3(0, 1.2, 0))
	camera.current = true


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = tr("VIEWER_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	box.add_child(_info)
	box.add_child(_anim_label)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_mode_button.pressed.connect(_on_toggle_mode)
	buttons.add_child(_mode_button)
	var prev := Button.new()
	prev.text = "◀"
	prev.pressed.connect(_on_cycle_anim.bind(-1))
	buttons.add_child(prev)
	var next := Button.new()
	next.text = "▶"
	next.pressed.connect(_on_cycle_anim.bind(1))
	buttons.add_child(next)
	var reload := Button.new()
	reload.text = tr("VIEWER_RELOAD")
	reload.pressed.connect(_on_reload)
	buttons.add_child(reload)


func _on_toggle_mode() -> void:
	_retarget_mode = not _retarget_mode
	_rebuild()


func _on_cycle_anim(step: int) -> void:
	if _source_anims.is_empty():
		return
	var i := _source_anims.find(_anim)
	_anim = _source_anims[posmod(i + step, _source_anims.size())]
	_rebuild()


func _on_reload() -> void:
	_find_animation_source()
	_rebuild()
