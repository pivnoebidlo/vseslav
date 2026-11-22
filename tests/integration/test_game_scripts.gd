extends GutTest
## Каждый скрипт представления (game/) компилируется: линт не проверяет типы, а тесты
## ядра эти скрипты не загружают — ошибка всплыла бы только при запуске игры.


func _scripts(dir: String, into: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			into.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), into)


func test_every_game_script_compiles() -> void:
	var paths: Array[String] = []
	_scripts("res://game", paths)
	assert_gt(paths.size(), 20)
	for path in paths:
		var script: Script = load(path)
		assert_not_null(script, path)
		if script != null:
			assert_true(script.can_instantiate(), path)
