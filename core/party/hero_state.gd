class_name HeroState
extends RefCounted
## Состояние героя между боями (ADR-0027): раны, потраченные кости хитов и заряды,
## гибель. Хранится как «сколько потрачено», чтобы правки данных (максимумы) не ломали сейв.

## Сколько хитов не хватает до максимума.
var damage: int = 0
var hit_dice_spent: int = 0
## Ресурс (ячейка, «Второе дыхание»…) → сколько потрачено.
var spent: Dictionary[String, int] = {}
var dead: bool = false
## Уровень героя (ADR-0043); 0 — ещё не задан, берётся из данных персонажа.
var level: int = 0
## Накопленный опыт, всего.
var xp: int = 0


## Переносит состояние на собранного бойца: хиты, заряды, гибель.
func apply_to(c: Combatant) -> void:
	c.hp = clampi(c.max_hp - damage, 0, c.max_hp)
	for key: String in c.resources_max:
		var used: int = spent.get(key, 0)
		c.resources[key] = maxi(c.resources_max[key] - used, 0)
	if dead:
		c.dead = true
		c.hp = 0


## Состояние после боя из бойца. [param stand_up] — упавший с 0 хитов встаёт с 1.
static func from_combatant(c: Combatant, hit_dice_spent_before: int, stand_up: bool) -> HeroState:
	var s := HeroState.new()
	s.dead = c.dead
	var hp := c.hp
	if hp == 0 and stand_up and not c.dead:
		hp = 1
	s.damage = 0 if s.dead else c.max_hp - hp
	s.hit_dice_spent = hit_dice_spent_before
	s.level = c.level
	for key: String in c.resources_max:
		var used := c.resources_max[key] - c.resource_left(key)
		if used > 0:
			s.spent[key] = used
	return s


func to_dict() -> Dictionary:
	var keys := spent.keys()
	keys.sort()
	var spent_dict := {}
	for key: Variant in keys:
		spent_dict[str(key)] = spent[key]
	return {
		"damage": damage,
		"hit_dice_spent": hit_dice_spent,
		"spent": spent_dict,
		"dead": dead,
		"level": level,
		"xp": xp,
	}


static func from_dict(data: Dictionary) -> HeroState:
	var s := HeroState.new()
	s.damage = maxi(JsonRead.get_int(data, "damage"), 0)
	s.hit_dice_spent = maxi(JsonRead.get_int(data, "hit_dice_spent"), 0)
	var spent_dict := JsonRead.get_dict(data, "spent")
	for key: Variant in spent_dict:
		s.spent[str(key)] = maxi(JsonRead.to_int(spent_dict[key]), 0)
	s.dead = JsonRead.get_bool(data, "dead")
	s.level = clampi(JsonRead.get_int(data, "level"), 0, Progression.LEVEL_CAP)
	s.xp = maxi(JsonRead.get_int(data, "xp"), 0)
	return s
