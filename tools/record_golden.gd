extends SceneTree
## Записывает golden-реплеи боёв на тестовых аренах (ИИ против ИИ).
## Запускать только при НАМЕРЕННОМ изменении правил или ИИ (скил testing).

const SEED := 42


func _init() -> void:
	for arena: String in CombatSim.GOLDEN_ARENAS:
		var out := CombatSim.golden_path(arena)
		var state := CombatSim.new_arena_combat(SEED, CombatSim.arena_path(arena))
		var steps := CombatSim.run(state)
		var golden := {
			"arena": CombatSim.arena_path(arena),
			"seed": SEED,
			"steps": steps,
			"expected": state.to_dict(),
		}
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write %s" % out)
			quit(1)
			return
		file.store_string(JSON.stringify(golden, "  ", true) + "\n")
		file.close()
		print("Golden recorded: %s (%d commands, winner %s)" % [out, steps, state.winner])
	quit()
