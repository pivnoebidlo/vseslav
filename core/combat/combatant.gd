class_name Combatant
extends RefCounted
## Участник боя. Данные приходят из арены/модуля, а не из кода.

var id: String = ""
## Ключ локализации имени.
var name_key: String = ""
var team: String = ""
var max_hp: int = 1
var hp: int = 1
var armor_class: int = 10
var attack_bonus: int = 0
var damage: DiceSpec = DiceSpec.new()
## Скорость в клетках по 5 футов.
var speed: int = 6
var initiative_bonus: int = 0
## Колонка на сетке (x, z); уровень берётся из сетки.
var column: Vector2i = Vector2i.ZERO


func is_alive() -> bool:
	return hp > 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name_key": name_key,
		"team": team,
		"max_hp": max_hp,
		"hp": hp,
		"armor_class": armor_class,
		"attack_bonus": attack_bonus,
		"damage": damage.to_text(),
		"speed": speed,
		"initiative_bonus": initiative_bonus,
		"at": [column.x, column.y],
	}


static func from_dict(data: Dictionary) -> Combatant:
	var c := Combatant.new()
	c.id = JsonRead.get_str(data, "id")
	c.name_key = JsonRead.get_str(data, "name_key")
	c.team = JsonRead.get_str(data, "team")
	c.max_hp = JsonRead.get_int(data, "max_hp", 1)
	c.hp = JsonRead.get_int(data, "hp", c.max_hp)
	c.armor_class = JsonRead.get_int(data, "armor_class", 10)
	c.attack_bonus = JsonRead.get_int(data, "attack_bonus")
	var dice := DiceSpec.parse(JsonRead.get_str(data, "damage"))
	if dice == null:
		push_error("Bad damage dice for %s" % c.id)
		dice = DiceSpec.new(1, 1, 0)
	c.damage = dice
	c.speed = JsonRead.get_int(data, "speed", 6)
	c.initiative_bonus = JsonRead.get_int(data, "initiative_bonus")
	c.column = JsonRead.to_vec2i(data.get("at"))
	return c
