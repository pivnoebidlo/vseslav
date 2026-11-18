extends SceneTree
## Генерирует синтетическую модель с именами костей Mixamo (без сторонних ассетов).
## Использование: godot --headless -s res://tools/make_sample_models.gd -- /путь/к/папке


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else "user://models"
	DirAccess.make_dir_recursive_absolute(dir)
	var scene := SyntheticRig.build(SyntheticRig.STYLE_MIXAMO, 1.0, 70.0)
	var path := dir.path_join("synthetic_mixamo.glb")
	var err := SyntheticRig.save_glb(scene, path)
	scene.free()
	print("Synthetic model: %s (%s)" % [path, error_string(err)])
	quit(0 if err == OK else 1)
