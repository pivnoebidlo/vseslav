extends SceneTree
## Записывает golden-реплей боя на тестовой арене.
## Запускать только при НАМЕРЕННОМ изменении правил (скил testing).

const OUT := "res://tests/golden/doroga_seed42.json"
const SEED := 42


func _init() -> void:
	var state := CombatSim.new_arena_combat(SEED)
	var steps := CombatSim.run(state)
	var golden := {
		"arena": CombatSim.ARENA_PATH,
		"seed": SEED,
		"steps": steps,
		"expected": state.to_dict(),
	}
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % OUT)
		quit(1)
		return
	file.store_string(JSON.stringify(golden, "  ", true) + "\n")
	file.close()
	print("Golden recorded: %s (%d commands)" % [OUT, steps])
	quit()
