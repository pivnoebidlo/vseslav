extends GutTest
## Бои детерминированы; сохранение посреди боя и загрузка дают тот же итог,
## что и бой без перерыва; записанные golden-реплеи воспроизводятся побитово.


func test_same_seed_same_outcome() -> void:
	for arena in CombatSim.GOLDEN_ARENAS:
		var a := CombatSim.new_arena_combat(7, CombatSim.arena_path(arena))
		var b := CombatSim.new_arena_combat(7, CombatSim.arena_path(arena))
		CombatSim.run(a)
		CombatSim.run(b)
		assert_true(a.ended, "%s must finish" % arena)
		assert_eq(a.to_dict(), b.to_dict(), arena)


func test_save_load_mid_combat_gives_same_outcome() -> void:
	for arena in CombatSim.GOLDEN_ARENAS:
		for cut: int in [1, 7, 23, 40, 61]:
			var straight := CombatSim.new_arena_combat(42, CombatSim.arena_path(arena))
			CombatSim.run(straight)
			var interrupted := CombatSim.new_arena_combat(42, CombatSim.arena_path(arena))
			CombatSim.run(interrupted, cut)
			var restored := CombatSim.through_json(interrupted)
			CombatSim.run(restored)
			assert_eq(restored.to_dict(), straight.to_dict(), "%s, cut after %d" % [arena, cut])


func test_matches_golden_replays() -> void:
	for arena in CombatSim.GOLDEN_ARENAS:
		var text := FileAccess.get_file_as_string(CombatSim.golden_path(arena))
		assert_ne(text, "", "golden for %s missing — tools/record_golden.sh" % arena)
		if text == "":
			continue
		var golden: Dictionary = JSON.parse_string(text)
		var state := CombatSim.new_arena_combat(
			JsonRead.get_int(golden, "seed"), CombatSim.arena_path(arena)
		)
		CombatSim.run(state)
		# Сравниваем через JSON, чтобы типы чисел совпадали.
		var actual: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
		assert_eq(actual, JsonRead.get_dict(golden, "expected"), arena)


func test_arenas_load_cleanly() -> void:
	for arena in CombatSim.GOLDEN_ARENAS:
		var data := ArenaLoader.read_file(CombatSim.arena_path(arena))
		var errors: Array[String] = []
		var state := ArenaLoader.new_combat(data, 1, CombatSim.rules(), errors)
		assert_eq(errors, [] as Array[String], arena)
		assert_gt(state.combatants.size(), 3, arena)
		var party := 0
		for c in state.combatants:
			assert_true(state.grid.is_walkable(c.column), "%s: %s on walkable cell" % [arena, c.id])
			if c.player:
				party += 1
		assert_eq(party, 3, "%s: party of 3" % arena)
