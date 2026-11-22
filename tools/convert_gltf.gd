extends SceneTree
## Переводит модели .gltf (+ .bin + текстуры рядом) в один .glb — формат модулей
## (docs/LICENSING.md, скил asset-pipeline). Использование:
##   godot --headless -s res://tools/convert_gltf.gd -- <вход.gltf> <выход.glb> [...]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var failed := false
	for i in range(0, args.size() - 1, 2):
		var src := args[i]
		var dst := args[i + 1]
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(src, state) != OK:
			printerr("cannot read %s" % src)
			failed = true
			continue
		if doc.write_to_filesystem(state, dst) != OK:
			printerr("cannot write %s" % dst)
			failed = true
			continue
		print("%s -> %s" % [src.get_file(), dst])
	quit(1 if failed else 0)
