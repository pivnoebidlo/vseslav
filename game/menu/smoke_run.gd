class_name SmokeRun
extends Node
## Дымовая проверка боя без участия человека (ADR-0045): новая игра без записи
## сохранений, бой на карте, ИИ за обе стороны, снимок экрана и выход.
## Запуск: godot --path . -- --smoke [--fight=<id боя>] [--seed=N] [--screenshot=PATH]
## Без --fight — первый бой стартовой области. Код выхода 1 — боя нет или он не кончился.

const LOAD_WAIT := 1.0
const LOAD_TIMEOUT := 30.0
const TIMEOUT := 120.0

var _fight := ""
var _shot := ""
var _x: Exploration = null
var _done := false


## Разбирает аргументы; true — это дымовой запуск (тогда проверка уже идёт).
static func start_if_asked(tree: SceneTree, args: PackedStringArray) -> bool:
	if not args.has("--smoke"):
		return false
	var run := SmokeRun.new()
	for arg in args:
		if arg.begins_with("--fight="):
			run._fight = arg.trim_prefix("--fight=")
		elif arg.begins_with("--screenshot="):
			run._shot = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--seed="):
			seed(arg.trim_prefix("--seed=").to_int())
	SaveStore.disabled = true
	SaveStore.pending = null
	SaveStore.new_game = true
	tree.root.add_child.call_deferred(run)
	return true


func _ready() -> void:
	get_tree().change_scene_to_file(MainMenu.EXPLORATION_SCENE)
	var waited := 0.0
	while waited < LOAD_TIMEOUT:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		_x = get_tree().current_scene as Exploration
		if _x != null and _x._area != null and not _x._heroes.is_empty():
			break
	await get_tree().create_timer(LOAD_WAIT).timeout
	if _x == null or _x._area == null:
		_finish("no exploration scene", 1)
		return
	var e: Encounter = null
	if _fight != "":
		e = _x._area.get_encounter(_fight)
	elif not _x._area.encounters.is_empty():
		e = _x._area.encounters[0]
	if e == null:
		_finish("no encounter '%s' in %s" % [_fight, _x._area.id], 1)
		return
	print("Smoke: fight '%s' in %s" % [e.id, _x._area.id])
	_x._session.autoplay = true
	_x._session.ended.connect(_on_ended)
	get_tree().create_timer(TIMEOUT).timeout.connect(func() -> void: _finish("timeout", 1))
	_x._start_combat(e)


func _on_ended(winner: String) -> void:
	await get_tree().create_timer(1.0).timeout
	_finish("winner %s" % winner, 0)


func _finish(result: String, code: int) -> void:
	if _done:
		return
	_done = true
	print("Smoke: %s" % result)
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)
		print("Smoke: screenshot %s" % _shot)
	get_tree().quit(code)
