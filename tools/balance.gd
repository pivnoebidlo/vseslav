extends SceneTree
## Прогон баланса: ИИ против ИИ на каждой арене по N seed, сводка побед и раундов.
## Запуск: godot --headless -s res://tools/balance.gd -- [--seeds=50]

const DEFAULT_SEEDS := 50


func _init() -> void:
	var seeds := DEFAULT_SEEDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = arg.trim_prefix("--seeds=").to_int()
	for arena: String in CombatSim.GOLDEN_ARENAS:
		var wins := 0
		var rounds := 0
		var party_down := 0
		var party_dead := 0
		for seed_value in range(1, seeds + 1):
			var state := CombatSim.new_arena_combat(seed_value, CombatSim.arena_path(arena))
			CombatSim.run(state)
			if state.winner == "party":
				wins += 1
			rounds += state.round_number
			for c in state.combatants:
				if c.player and c.hp == 0:
					party_down += 1
				if c.player and c.dead:
					party_dead += 1
		print(
			(
				"%-8s party wins %3d%%  avg rounds %.1f  heroes down at end %.2f  dead %.2f"
				% [
					arena,
					wins * 100 / seeds,
					float(rounds) / seeds,
					float(party_down) / seeds,
					float(party_dead) / seeds
				]
			)
		)
	quit()
