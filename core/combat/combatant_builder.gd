class_name CombatantBuilder
extends RefCounted
## Собирает лист участника боя из данных (docs/rules/actions.md):
## персонаж = класс + путь + происхождение + инвентарь; существо — готовый блок.

const BASE_SPEED := 6
const HEAVY_ARMOR_PENALTY := 2
## Перегруженный (вес больше Силы × 15) двигается не дальше 1 клетки за ход (SRD 5.2).
const OVERLOADED_SPEED := 1


## Участник по записи арены: {"character": id} | {"creature": id} | {"sheet": {...}}
## плюс id, team, player, at. Возвращает null при ошибке (причины в [param errors]).
static func from_entry(db: RulesDb, entry: Dictionary, errors: Array[String]) -> Combatant:
	var c: Combatant = null
	if entry.has("character"):
		var char_id := JsonRead.get_str(entry, "character")
		if not db.characters.has(char_id):
			errors.append("unknown character '%s'" % char_id)
			return null
		c = from_character(db, db.characters[char_id], errors)
	elif entry.has("creature"):
		var creature_id := JsonRead.get_str(entry, "creature")
		if not db.creatures.has(creature_id):
			errors.append("unknown creature '%s'" % creature_id)
			return null
		c = from_creature(db, db.creatures[creature_id], errors)
	elif entry.has("sheet"):
		c = Combatant.from_dict(JsonRead.get_dict(entry, "sheet"), errors)
	else:
		errors.append("combatant entry needs character, creature or sheet")
		return null
	if c == null:
		return null
	if entry.has("id"):
		c.id = JsonRead.get_str(entry, "id")
	c.team = JsonRead.get_str(entry, "team", c.team)
	if entry.has("player"):
		c.player = JsonRead.get_bool(entry, "player")
	if entry.has("at"):
		c.column = JsonRead.to_vec2i(entry["at"])
	return c


## [param inventory] — снаряжение героя (экран снаряжения); null — из данных персонажа.
static func from_character(
	db: RulesDb, data: Dictionary, errors: Array[String], inventory: Inventory = null
) -> Combatant:
	var id := JsonRead.get_str(data, "id")
	var cls: Dictionary = db.classes.get(JsonRead.get_str(data, "class"), {})
	var origin: Dictionary = db.origins.get(JsonRead.get_str(data, "origin"), {})
	if cls.is_empty() or origin.is_empty():
		errors.append("%s: unknown class or origin" % id)
		return null
	var c := Combatant.new()
	c.id = id
	c.name_key = JsonRead.get_str(data, "name_key", id)
	c.player = true
	c.death_saves = true
	c.creature_tags = ["humanoid"]
	c.level = clampi(JsonRead.get_int(data, "level", 1), 1, 20)
	c.proficiency = IntMath.proficiency_bonus(c.level)
	c.abilities = Abilities.from_dict(JsonRead.get_dict(data, "abilities"))
	_apply_origin_bonus(c, origin, JsonRead.get_dict(data, "origin_bonus"), errors)
	c.save_proficiencies = JsonRead.get_str_array(cls, "saves")
	c.spell_ability = JsonRead.get_str(cls, "spell_ability")

	var action_ids: Array[String] = []
	_collect_class_features(c, cls, JsonRead.get_str(data, "path"), action_ids, errors)
	for t: Variant in JsonRead.get_array(origin, "traits"):
		var entry: Dictionary = t
		c.traits.append(TraitDef.from_dict(entry, errors))
	var spell_list := JsonRead.get_str_array(cls, "spell_list")
	for spell in JsonRead.get_str_array(data, "spells"):
		if not spell_list.has(spell):
			errors.append("%s: spell '%s' is not on the class list" % [id, spell])
		elif not action_ids.has(spell):
			action_ids.append(spell)

	var hit_die := JsonRead.get_int(cls, "hit_die", 8)
	var con := c.abilities.modifier(Abilities.CON)
	c.max_hp = hit_die + con + (c.level - 1) * (IntMath.floor_div(hit_die, 2) + 1 + con)
	for t in c.traits_of(TraitDef.HP_PER_LEVEL):
		c.max_hp += t.value * c.level
	c.max_hp = maxi(c.max_hp, 1)
	c.hp = c.max_hp

	var inv := inventory
	if inv == null:
		inv = Inventory.from_dict(JsonRead.get_dict(data, "inventory"))
	inv.validate(db, id, errors)
	_equip(db, c, cls, inv, errors)
	for action_id in action_ids:
		var a := db.make_action(action_id, errors)
		if a != null:
			c.actions.append(a)
	_finish(db, c, errors)
	return c


static func from_creature(db: RulesDb, data: Dictionary, errors: Array[String]) -> Combatant:
	var c := Combatant.new()
	c.id = JsonRead.get_str(data, "id")
	c.name_key = JsonRead.get_str(data, "name_key", c.id)
	c.creature_tags = JsonRead.get_str_array(data, "tags")
	c.proficiency = JsonRead.get_int(data, "proficiency", 2)
	c.abilities = Abilities.from_dict(JsonRead.get_dict(data, "abilities"))
	c.save_proficiencies = JsonRead.get_str_array(data, "saves")
	c.spell_ability = JsonRead.get_str(data, "spell_ability")
	c.armor_class = JsonRead.get_int(data, "armor_class", 10)
	c.max_hp = maxi(JsonRead.get_int(data, "hp", 1), 1)
	c.hp = c.max_hp
	c.speed = JsonRead.get_int(data, "speed", BASE_SPEED)
	for item: Variant in JsonRead.get_array(data, "defenses"):
		var entry: Dictionary = item
		c.defenses.append(Defense.from_dict(entry))
	for item: Variant in JsonRead.get_array(data, "traits"):
		var entry: Dictionary = item
		c.traits.append(TraitDef.from_dict(entry, errors))
	for item: Variant in JsonRead.get_array(data, "actions"):
		var entry: Dictionary = item
		var a := ActionDef.from_dict(entry, errors)
		c.actions.append(a)
	c.masteries = JsonRead.get_str_array(data, "masteries")
	for a in c.actions:
		for sub in a.sub_actions:
			if c.get_action(sub) == null:
				errors.append("%s: multiattack refers to unknown action '%s'" % [c.id, sub])
	_finish(db, c, errors)
	return c


static func _apply_origin_bonus(
	c: Combatant, origin: Dictionary, bonus: Dictionary, errors: Array[String]
) -> void:
	var allowed := JsonRead.get_str_array(origin, "abilities")
	var total := 0
	for key: Variant in bonus:
		var ability := str(key)
		var value := JsonRead.to_int(bonus[key])
		if not allowed.has(ability) or value < 1 or value > 2:
			errors.append("%s: origin bonus %s +%d is not allowed" % [c.id, ability, value])
			continue
		total += value
		c.abilities.set_score(ability, c.abilities.score(ability) + value)
	if total != 3:
		errors.append("%s: origin bonuses must add up to 3 (got %d)" % [c.id, total])


static func _collect_class_features(
	c: Combatant, cls: Dictionary, path_id: String, action_ids: Array[String], errors: Array[String]
) -> void:
	var levels := JsonRead.get_dict(cls, "levels")
	var features: Array[Dictionary] = []
	for lvl in range(1, c.level + 1):
		if levels.has(str(lvl)):
			features.append(JsonRead.get_dict(levels, str(lvl)))
	var path_found := path_id == ""
	for item: Variant in JsonRead.get_array(cls, "paths"):
		var path: Dictionary = item
		if JsonRead.get_str(path, "id") != path_id:
			continue
		path_found = true
		if c.level >= JsonRead.get_int(path, "level", 3):
			features.append(path)
	if not path_found:
		errors.append("%s: unknown path '%s'" % [c.id, path_id])
	for f in features:
		for action_id in JsonRead.get_str_array(f, "actions"):
			if not action_ids.has(action_id):
				action_ids.append(action_id)
		for t: Variant in JsonRead.get_array(f, "traits"):
			var entry: Dictionary = t
			c.traits.append(TraitDef.from_dict(entry, errors))
		var res := JsonRead.get_dict(f, "resources")
		for key: Variant in res:
			c.resources_max[str(key)] = JsonRead.to_int(res[key])
	if JsonRead.get_bool(cls, "weapon_mastery"):
		c.masteries = ["*"]


## Снаряжение: доспех и щит → КД и скорость; оружие и расходники → действия
## с привязкой к предмету. Доступны те, чей предмет в руке или на поясе; вещи
## из мешка сначала достают (ADR-0024). Метательное и расходники тратятся.
static func _equip(
	db: RulesDb, c: Combatant, cls: Dictionary, inv: Inventory, errors: Array[String]
) -> void:
	var dex := c.abilities.modifier(Abilities.DEX)
	var ac := 10 + dex
	var armored := false
	c.speed = BASE_SPEED
	var trained_armor := JsonRead.get_str_array(cls, "armor")
	if inv.armor != "" and db.items.has(inv.armor):
		var item: Dictionary = db.items[inv.armor]
		var kind := JsonRead.get_str(item, "armor")
		if not trained_armor.has(kind):
			errors.append("%s: not trained in %s armor" % [c.id, kind])
		var cap := JsonRead.get_int(item, "dex_cap", -1)
		var dex_part := dex if cap < 0 else mini(dex, cap)
		ac = JsonRead.get_int(item, "base", 10) + dex_part
		armored = true
		var str_req := JsonRead.get_int(item, "str_req")
		if str_req > 0 and c.abilities.score(Abilities.STR) < str_req:
			c.speed -= HEAVY_ARMOR_PENALTY
	if inv.off_hand != "" and ItemInfo.item_type(db, inv.off_hand) == "shield":
		if not trained_armor.has("shield"):
			errors.append("%s: not trained with shields" % c.id)
		c.has_shield = true
		ac += JsonRead.get_int(db.items[inv.off_hand], "ac", 2)
	var weapon_masteries: Array[String] = []
	var ready := _ready_items(inv)
	for item_id in _combat_items(inv):
		if not db.items.has(item_id):
			continue
		var item: Dictionary = db.items[item_id]
		match JsonRead.get_str(item, "type"):
			"weapon":
				_add_weapon(c, cls, item, ready.has(item_id), weapon_masteries, errors)
			"consumable":
				var action_data := JsonRead.get_dict(item, "action").duplicate()
				action_data["id"] = "use_" + item_id
				action_data["name_key"] = JsonRead.get_str(item, "name_key", item_id)
				action_data["item"] = item_id
				action_data["consumes"] = true
				c.actions.append(ActionDef.from_dict(action_data, errors))
	c.inventory = Inventory.from_dict(inv.to_dict())
	for t in c.traits_of(TraitDef.AC_BONUS):
		if t.when == TraitDef.WHEN_ARMORED and armored:
			ac += t.value
	c.armor_class = ac
	if inv.weight(db) > ItemInfo.carry_limit(c.abilities.score(Abilities.STR)):
		c.speed = mini(c.speed, OVERLOADED_SPEED)
	if c.masteries.has("*"):
		weapon_masteries.sort()
		c.masteries = weapon_masteries


## Предметы под рукой без повторов: руки, затем пояс по порядку.
static func _ready_items(inv: Inventory) -> Array[String]:
	var ids: Array[String] = []
	for item_id: String in [inv.main_hand, inv.off_hand]:
		if item_id != "" and not ids.has(item_id):
			ids.append(item_id)
	for s in inv.belt:
		if not ids.has(s.item):
			ids.append(s.item)
	return ids


## Все боевые предметы без повторов: под рукой (руки, пояс), затем мешок.
static func _combat_items(inv: Inventory) -> Array[String]:
	var ids := _ready_items(inv)
	for s in inv.bag:
		if not ids.has(s.item):
			ids.append(s.item)
	return ids


## Оружие → атака. Невладение оружием под рукой — ошибка данных; оружием
## из мешка, которым герой не владеет, он просто не пользуется.
static func _add_weapon(
	c: Combatant,
	cls: Dictionary,
	item: Dictionary,
	ready: bool,
	weapon_masteries: Array[String],
	errors: Array[String]
) -> void:
	var item_id := JsonRead.get_str(item, "id")
	if not JsonRead.get_str_array(cls, "weapons").has(JsonRead.get_str(item, "category")):
		if ready:
			errors.append("%s: not trained with %s" % [c.id, item_id])
		return
	var attack := weapon_action(c, item)
	attack.item = item_id
	attack.consumes = JsonRead.get_bool(item, "thrown")
	attack.two_handed = JsonRead.get_str_array(item, "properties").has("two_handed")
	c.actions.append(attack)
	if attack.mastery != "":
		weapon_masteries.append(attack.mastery)


## Атака оружием: MOD — Сила (ближний и метательное) или Ловкость (дальнобойное);
## у фехтовального оружия — лучшая из двух.
static func weapon_action(c: Combatant, item: Dictionary) -> ActionDef:
	var a := ActionDef.new()
	a.id = JsonRead.get_str(item, "id")
	a.name_key = JsonRead.get_str(item, "name_key", a.id)
	a.kind = ActionDef.KIND_ATTACK
	a.attack_type = JsonRead.get_str(item, "attack_type", ActionDef.MELEE)
	var props := JsonRead.get_str_array(item, "properties")
	if a.attack_type == ActionDef.RANGED and not JsonRead.get_bool(item, "thrown"):
		a.ability = Abilities.DEX
	else:
		a.ability = Abilities.STR
	if props.has("finesse") and c.abilities.modifier(Abilities.DEX) > c.ability_mod(a.ability):
		a.ability = Abilities.DEX
	a.range_cells = JsonRead.get_int(item, "range", 1)
	a.long_range = JsonRead.get_int(item, "long_range")
	var dice := JsonRead.get_str(item, "damage", "1d4")
	a.damage = [
		DamagePart.new(
			Formula.parse(dice + " + MOD"), JsonRead.get_str(item, "damage_type", "bludgeoning")
		)
	]
	a.tags = JsonRead.get_str_array(item, "tags")
	a.mastery = JsonRead.get_str(item, "mastery")
	return a


## Общее для всех: инициатива, ресурсы, действия «Рывок», «Отход», «Уклонение».
static func _finish(db: RulesDb, c: Combatant, errors: Array[String]) -> void:
	c.initiative_bonus = c.abilities.modifier(Abilities.DEX)
	var vars := c.formula_vars()
	for t in c.traits_of(TraitDef.INITIATIVE):
		c.initiative_bonus += t.formula.value_range(vars).x
	for key in c.resources_max:
		c.resources[key] = c.resources_max[key]
	for action_id in db.common_actions:
		if c.get_action(action_id) == null:
			var a := db.make_action(action_id, errors)
			if a != null:
				c.actions.append(a)
