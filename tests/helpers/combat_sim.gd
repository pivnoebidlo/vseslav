class_name CombatSim
extends RefCounted
## Прогон боя, где все стороны управляются SimpleAi. Для тестов и golden-реплеев.

const ARENA_PATH := "res://modules/spike/arena.json"
const MAX_STEPS := 2000


static func new_arena_combat(seed_value: int) -> CombatState:
	var state := ArenaLoader.new_combat(ArenaLoader.read_file(ARENA_PATH), seed_value)
	state.start()
	return state


## Выполняет до [param steps] команд (или до конца боя). Возвращает число выполненных.
static func run(state: CombatState, steps: int = MAX_STEPS) -> int:
	var done := 0
	while not state.ended and done < steps:
		var cmd := SimpleAi.next_command(state)
		var err := cmd.validate(state)
		assert(err == "", "AI produced invalid command %s: %s" % [cmd.to_dict(), err])
		cmd.apply(state)
		done += 1
	return done


## Состояние через JSON-текст — как при реальном сохранении на диск.
static func through_json(state: CombatState) -> CombatState:
	var text := JSON.stringify(state.to_dict())
	var parsed: Dictionary = JSON.parse_string(text)
	return CombatState.from_dict(parsed, state.grid)
