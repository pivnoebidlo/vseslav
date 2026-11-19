class_name Combatant
extends RefCounted
## Участник боя — готовый лист: всё уже посчитано CombatantBuilder из данных
## (класс, происхождение, снаряжение или блок существа). Сохраняется целиком,
## поэтому сейв боя не зависит от последующих правок данных модуля.

var id: String = ""
## Ключ локализации имени.
var name_key: String = ""
var team: String = ""
## Управляет игрок (иначе ИИ).
var player: bool = false
var level: int = 1
var proficiency: int = 2
var abilities: Abilities = Abilities.new()
var save_proficiencies: Array[String] = []
## Характеристика заклинаний (переменная SPELL в формулах); пусто — нет.
var spell_ability: String = ""
var max_hp: int = 1
var hp: int = 1
var armor_class: int = 10
## Скорость в клетках по 5 футов.
var speed: int = 6
var initiative_bonus: int = 0
## Метки существа: humanoid, beast, undead, nechist…
var creature_tags: Array[String] = []
var defenses: Array[Defense] = []
var traits: Array[TraitDef] = []
var actions: Array[ActionDef] = []
## Приёмы оружия, которыми владеет участник.
var masteries: Array[String] = []
var has_shield: bool = false
var resources: Dictionary[String, int] = {}
var resources_max: Dictionary[String, int] = {}
var conditions: Array[ConditionState] = []
## Спасброски от смерти (у персонажей игрока); существа при 0 хитов погибают.
var death_saves: bool = false
var death_successes: int = 0
var death_failures: int = 0
var stable: bool = false
var dead: bool = false
## Упал, но встанет в начале своего хода (черта revive).
var reviving: bool = false
## Метки последнего полученного урона (для черты revive).
var last_damage_tags: Array[String] = []
## Id действия, на котором держится концентрация; пусто — нет.
var concentration: String = ""
## Реакция доступна (восстанавливается в начале своего хода).
var reaction_ready: bool = true
## Колонка на сетке (x, z); уровень берётся из сетки.
var column: Vector2i = Vector2i.ZERO


## В строю: хиты больше 0. Лежащий без сознания персонаж ещё не выбыл из боя,
## но и не «в строю».
func is_alive() -> bool:
	return hp > 0


## Участвует в бою: не погиб (лежащий при смерти персонаж — участвует).
func is_present() -> bool:
	return not dead and (hp > 0 or death_saves or reviving)


## Держит сторону в бою: в строю или вот-вот встанет.
func is_standing() -> bool:
	return not dead and (hp > 0 or reviving)


func has_condition(condition_id: String) -> bool:
	return Conditions.has(conditions, condition_id)


func get_action(action_id: String) -> ActionDef:
	for a in actions:
		if a.id == action_id:
			return a
	return null


func traits_of(trait_type: String) -> Array[TraitDef]:
	var result: Array[TraitDef] = []
	for t in traits:
		if t.type == trait_type:
			result.append(t)
	return result


func ability_mod(ability_id: String) -> int:
	if ability_id == "spell":
		return abilities.modifier(spell_ability) if spell_ability != "" else 0
	if ability_id == "":
		return 0
	return abilities.modifier(ability_id)


## Переменные формул для действия [param action] (MOD — его характеристика).
func formula_vars(action: ActionDef = null) -> Dictionary[String, int]:
	var vars := abilities.formula_vars()
	vars["PROF"] = proficiency
	vars["LEVEL"] = level
	vars["SPELL"] = ability_mod("spell")
	vars["MOD"] = ability_mod(action.ability) if action != null else 0
	return vars


func save_modifier(ability_id: String) -> int:
	var mod := abilities.modifier(ability_id)
	if save_proficiencies.has(ability_id):
		mod += proficiency
	return mod


func resource_left(resource_id: String) -> int:
	return resources.get(resource_id, 0)


func add_condition(state: ConditionState) -> void:
	for i in conditions.size():
		if conditions[i].id == state.id and conditions[i].source == state.source:
			conditions[i] = state
			return
	conditions.append(state)


## Снимает состояние; с [param source] — только наложенное этим источником.
## Возвращает true, если что-то снято.
func remove_condition(condition_id: String, source: String = "") -> bool:
	var kept: Array[ConditionState] = []
	for c in conditions:
		if c.id != condition_id or (source != "" and c.source != source):
			kept.append(c)
	var removed := kept.size() != conditions.size()
	conditions = kept
	return removed


func to_dict() -> Dictionary:
	var defs: Array = []
	for d in defenses:
		defs.append(d.to_dict())
	var trait_list: Array = []
	for t in traits:
		trait_list.append(t.to_dict())
	var action_list: Array = []
	for a in actions:
		action_list.append(a.to_dict())
	var cond_list: Array = []
	for c in conditions:
		cond_list.append(c.to_dict())
	return {
		"id": id,
		"name_key": name_key,
		"team": team,
		"player": player,
		"level": level,
		"proficiency": proficiency,
		"abilities": abilities.to_dict(),
		"save_proficiencies": save_proficiencies.duplicate(),
		"spell_ability": spell_ability,
		"max_hp": max_hp,
		"hp": hp,
		"armor_class": armor_class,
		"speed": speed,
		"initiative_bonus": initiative_bonus,
		"creature_tags": creature_tags.duplicate(),
		"defenses": defs,
		"traits": trait_list,
		"actions": action_list,
		"masteries": masteries.duplicate(),
		"has_shield": has_shield,
		"resources": _sorted_dict(resources),
		"resources_max": _sorted_dict(resources_max),
		"conditions": cond_list,
		"death_saves": death_saves,
		"death_successes": death_successes,
		"death_failures": death_failures,
		"stable": stable,
		"dead": dead,
		"reviving": reviving,
		"last_damage_tags": last_damage_tags.duplicate(),
		"concentration": concentration,
		"reaction_ready": reaction_ready,
		"at": [column.x, column.y],
	}


static func from_dict(data: Dictionary, errors: Array[String] = []) -> Combatant:
	var c := Combatant.new()
	c.id = JsonRead.get_str(data, "id")
	c.name_key = JsonRead.get_str(data, "name_key")
	c.team = JsonRead.get_str(data, "team")
	c.player = JsonRead.get_bool(data, "player")
	c.level = JsonRead.get_int(data, "level", 1)
	c.proficiency = JsonRead.get_int(data, "proficiency", 2)
	c.abilities = Abilities.from_dict(JsonRead.get_dict(data, "abilities"))
	c.save_proficiencies = JsonRead.get_str_array(data, "save_proficiencies")
	c.spell_ability = JsonRead.get_str(data, "spell_ability")
	c.max_hp = JsonRead.get_int(data, "max_hp", 1)
	c.hp = JsonRead.get_int(data, "hp", c.max_hp)
	c.armor_class = JsonRead.get_int(data, "armor_class", 10)
	c.speed = JsonRead.get_int(data, "speed", 6)
	c.initiative_bonus = JsonRead.get_int(data, "initiative_bonus")
	c.creature_tags = JsonRead.get_str_array(data, "creature_tags")
	for item: Variant in JsonRead.get_array(data, "defenses"):
		var entry: Dictionary = item
		c.defenses.append(Defense.from_dict(entry))
	for item: Variant in JsonRead.get_array(data, "traits"):
		var entry: Dictionary = item
		c.traits.append(TraitDef.from_dict(entry, errors))
	for item: Variant in JsonRead.get_array(data, "actions"):
		var entry: Dictionary = item
		c.actions.append(ActionDef.from_dict(entry, errors))
	c.masteries = JsonRead.get_str_array(data, "masteries")
	c.has_shield = JsonRead.get_bool(data, "has_shield")
	c.resources = _int_dict(JsonRead.get_dict(data, "resources"))
	c.resources_max = _int_dict(JsonRead.get_dict(data, "resources_max"))
	for item: Variant in JsonRead.get_array(data, "conditions"):
		var entry: Dictionary = item
		c.conditions.append(ConditionState.from_dict(entry))
	c.death_saves = JsonRead.get_bool(data, "death_saves")
	c.death_successes = JsonRead.get_int(data, "death_successes")
	c.death_failures = JsonRead.get_int(data, "death_failures")
	c.stable = JsonRead.get_bool(data, "stable")
	c.dead = JsonRead.get_bool(data, "dead")
	c.reviving = JsonRead.get_bool(data, "reviving")
	c.last_damage_tags = JsonRead.get_str_array(data, "last_damage_tags")
	c.concentration = JsonRead.get_str(data, "concentration")
	c.reaction_ready = JsonRead.get_bool(data, "reaction_ready", true)
	c.column = JsonRead.to_vec2i(data.get("at", [0, 0]))
	return c


static func _sorted_dict(source: Dictionary[String, int]) -> Dictionary:
	var keys := source.keys()
	keys.sort()
	var result := {}
	for key: String in keys:
		result[key] = source[key]
	return result


static func _int_dict(source: Dictionary) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	var keys := source.keys()
	keys.sort()
	for key: Variant in keys:
		result[str(key)] = JsonRead.to_int(source[key])
	return result
