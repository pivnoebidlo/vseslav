extends GutTest
## Критерий этапа 0: бой детерминирован, сохранение посреди боя
## и загрузка дают тот же итог, что и бой без перерыва.

const GOLDEN_PATH := "res://tests/golden/doroga_seed42.json"


func test_same_seed_same_outcome() -> void:
	var a := CombatSim.new_arena_combat(42)
	var b := CombatSim.new_arena_combat(42)
	CombatSim.run(a)
	CombatSim.run(b)
	assert_true(a.ended, "combat must finish")
	assert_eq(a.to_dict(), b.to_dict())


func test_save_load_mid_combat_gives_same_outcome() -> void:
	for cut: int in [1, 7, 23, 40]:
		var straight := CombatSim.new_arena_combat(42)
		CombatSim.run(straight)
		var interrupted := CombatSim.new_arena_combat(42)
		CombatSim.run(interrupted, cut)
		var restored := CombatSim.through_json(interrupted)
		CombatSim.run(restored)
		assert_eq(restored.to_dict(), straight.to_dict(), "cut after %d commands" % cut)


func test_matches_golden_replay() -> void:
	var text := FileAccess.get_file_as_string(GOLDEN_PATH)
	assert_ne(text, "", "golden file missing — record it with tools/record_golden.sh")
	var golden: Dictionary = JSON.parse_string(text)
	var state := CombatSim.new_arena_combat(JsonRead.get_int(golden, "seed"))
	CombatSim.run(state)
	# Сравниваем через JSON, чтобы типы чисел совпадали.
	var actual: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	assert_eq(actual, JsonRead.get_dict(golden, "expected"))


func test_arena_loads_cleanly() -> void:
	var data := ArenaLoader.read_file(CombatSim.ARENA_PATH)
	var errors: Array[String] = []
	var state := ArenaLoader.new_combat(data, 1, CombatSim.rules(), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(state.combatants.size(), 7)
	for c in state.combatants:
		assert_true(state.grid.is_walkable(c.column), "%s stands on a walkable cell" % c.id)
