class_name MiniCombat
extends RefCounted
## Маленький бой для unit-тестов: участники собираются в коде, броски — StubRng.

const MAP_5X5: Array[String] = [".....", ".....", ".....", ".....", "....."]


## Участник с ровными характеристиками 10 (+0), если не задано иное.
static func unit(
	id: String, team: String, at: Vector2i, hp: int = 20, ac: int = 10, speed: int = 6
) -> Combatant:
	var c := Combatant.new()
	c.id = id
	c.name_key = id
	c.team = team
	c.column = at
	c.max_hp = hp
	c.hp = hp
	c.armor_class = ac
	c.speed = speed
	return c


## Действие из словаря (формат data/actions.json); ошибки разбора валят тест.
static func action(data: Dictionary) -> ActionDef:
	var errors: Array[String] = []
	var a := ActionDef.from_dict(data, errors)
	assert(errors.is_empty(), "bad test action: %s" % [errors])
	return a


## Ближняя атака: +bonus к попаданию, урон формулой.
static func melee(id: String = "hit", damage: String = "1d6", bonus: int = 5) -> ActionDef:
	return action(
		{
			"id": id,
			"attack_type": "melee",
			"attack_bonus": str(bonus),
			"damage": [{"formula": damage, "type": "slashing"}],
		}
	)


static func ranged(id: String = "shoot", damage: String = "1d6", bonus: int = 5) -> ActionDef:
	return action(
		{
			"id": id,
			"attack_type": "ranged",
			"attack_bonus": str(bonus),
			"range": 6,
			"long_range": 12,
			"damage": [{"formula": damage, "type": "piercing"}],
		}
	)


static func trait_def(data: Dictionary) -> TraitDef:
	return TraitDef.from_dict(data)


## Состояние боя на карте [param map]; ход начинается по [param order] без инициативы.
static func make(
	units: Array[Combatant], order: Array[String], map: Array[String] = MAP_5X5
) -> CombatState:
	var state := CombatState.new()
	state.grid = BattleGrid.from_dict({"map": map})
	state.combatants = units
	state.rng = StubRng.new([])
	state.start_in_order(order)
	return state


## Подставляет броски на следующие команды.
static func rolls(state: CombatState, values: Array[int]) -> void:
	state.rng = StubRng.new(values)


static func use(
	state: CombatState,
	actor: String,
	action_id: String,
	target: String = "",
	cell: Vector2i = ActionResolver.NO_CELL
) -> Array[CombatEvent]:
	var cmd := UseActionCommand.new(actor, action_id, target, cell)
	var err := cmd.validate(state)
	assert(err == "", "command %s rejected: %s" % [cmd.to_dict(), err])
	return cmd.apply(state)


static func events_of(events: Array[CombatEvent], type: String) -> Array[CombatEvent]:
	var result: Array[CombatEvent] = []
	for e in events:
		if e.type == type:
			result.append(e)
	return result
