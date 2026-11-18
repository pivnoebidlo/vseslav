extends SceneTree
## Записывает golden-реплей боя на тестовой арене.
## Запускать только при НАМЕРЕННОМ изменении правил (скил testing).

const OUT := "res://tests/golden/spike_arena_seed42.json"
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
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(golden, "  ", true) + "\n")
	file.close()
	print("Golden recorded: %s (%d commands)" % [OUT, steps])
	quit()
