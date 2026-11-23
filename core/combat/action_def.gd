class_name ActionDef
extends RefCounted
## Действие участника боя: атака оружием, заговор, умение класса, приём существа.
## Описывается данными (modules/*/rules/actions.json, items.json, creatures.json),
## механику исполняет ActionResolver. Формат — docs/rules/actions.md.

const COST_ACTION := "action"
const COST_BONUS := "bonus"
const COST_REACTION := "reaction"
const COST_FREE := "free"
const COSTS: Array[String] = [COST_ACTION, COST_BONUS, COST_REACTION, COST_FREE]

const KIND_ATTACK := "attack"
const KIND_SAVE := "save"
const KIND_HEAL := "heal"
const KIND_EFFECT := "effect"
const KIND_MULTI := "multiattack"
const KINDS: Array[String] = [KIND_ATTACK, KIND_SAVE, KIND_HEAL, KIND_EFFECT, KIND_MULTI]

const MELEE := "melee"
const RANGED := "ranged"

const TARGET_ENEMY := "enemy"
const TARGET_ALLY := "ally"
const TARGET_SELF := "self"
const TARGET_POINT := "point"
const TARGETS: Array[String] = [TARGET_ENEMY, TARGET_ALLY, TARGET_SELF, TARGET_POINT]

const AREA_BURST := "burst"
const AREA_CONE := "cone"

## Особые действия: механика в коде, данные только включают её.
const SPECIAL_DASH := "dash"
const SPECIAL_DISENGAGE := "disengage"
const SPECIAL_DODGE := "dodge"
const SPECIAL_EXTRA_ACTION := "extra_action"
## Встать (половина скорости, без траты действия).
const SPECIAL_STAND := "stand"
## Толкнуть цель на клетку (если некуда — сбить с ног) или сразу сбить с ног (ForcedMove).
const SPECIAL_SHOVE := "shove"
const SPECIAL_SHOVE_PRONE := "shove_prone"
## Безрассудная атака: состояние reckless до начала своего следующего хода.
const SPECIAL_RECKLESS := "reckless"
const SPECIALS: Array[String] = [
	SPECIAL_DASH,
	SPECIAL_DISENGAGE,
	SPECIAL_DODGE,
	SPECIAL_EXTRA_ACTION,
	SPECIAL_STAND,
	SPECIAL_SHOVE,
	SPECIAL_SHOVE_PRONE,
	SPECIAL_RECKLESS,
]

## Приёмы оружия (weapon mastery SRD 5.2). Действуют только реализованные,
## остальные можно указывать в данных — они пока ни на что не влияют.
const MASTERIES: Array[String] = ["cleave", "graze", "nick", "push", "sap", "slow", "topple", "vex"]
const MASTERIES_IMPLEMENTED: Array[String] = ["graze", "sap", "topple", "vex"]

var id: String = ""
var name_key: String = ""
var cost: String = COST_ACTION
var kind: String = KIND_ATTACK
## Для атак: melee или ranged.
var attack_type: String = MELEE
## Характеристика для MOD: str, dex, spell (заклинательная) или пусто.
var ability: String = ""
## Бонус атаки, обычно "MOD + PROF".
var attack_bonus: Formula = Formula.parse("MOD + PROF")
## Дальность в клетках (ближний бой — досягаемость, обычно 1).
var range_cells: int = 1
## Дальняя дистанция (с помехой); 0 — нет.
var long_range: int = 0
var target: String = TARGET_ENEMY
## Область: пусто, burst (квадрат радиуса area_size вокруг точки), cone (от себя).
var area: String = ""
var area_size: int = 0
var damage: Array[DamagePart] = []
## Метки урона: silver, aspen, iron, fire, magic, weapon, spell…
var tags: Array[String] = []
## Спасбросок цели (для kind == save) и СЛ для всех эффектов действия.
var save_ability: String = ""
var save_dc: Formula = Formula.parse("8 + PROF + MOD")
## Половина урона при успешном спасброске.
var save_half: bool = false
var heal: Formula = Formula.constant(0)
var effects: Array[EffectDef] = []
## Расходуемый ресурс (ячейки, заряды умений, предметы) и сколько.
var resource: String = ""
var resource_cost: int = 1
var concentration: bool = false
## Приём оружия; применяется, только если участник им владеет.
var mastery: String = ""
var special: String = ""
## Для multiattack: id действий, которые выполняются по очереди.
var sub_actions: Array[String] = []
## Предмет, которым действие делается (оружие, отвар); пусто — не предмет.
## Доступно, только если предмет в руке или на поясе (ADR-0024).
var item: String = ""
## Предмет тратится при использовании (метательное оружие, расходник).
var consumes: bool = false
## Оружие двуручное: в руку — только при свободной второй руке.
var two_handed: bool = false
## Круг заклинания (ADR-0044): 0 — не заклинание с ячейкой (заговор, умение). Ячейка —
## slot_<круг>; когда их нет — ближайшая выше, и действие усиливается на [member upcast].
var spell_level: int = 0
## Кости, прибавляемые к урону (или лечению) за каждый круг ячейки выше круга заклинания: "1d6".
var upcast: String = ""
## Круг ячейки, которой заклинание сотворено сейчас (копия действия при сотворении).
var cast_level: int = 0


func is_attack() -> bool:
	return kind == KIND_ATTACK


func is_melee_attack() -> bool:
	return kind == KIND_ATTACK and attack_type == MELEE


## Наибольшая дальность (с помехой, если больше обычной).
func max_range() -> int:
	return maxi(range_cells, long_range)


func to_dict() -> Dictionary:
	var dmg: Array = []
	for d in damage:
		dmg.append(d.to_dict())
	var fx: Array = []
	for e in effects:
		fx.append(e.to_dict())
	var data := {
		"id": id,
		"name_key": name_key,
		"cost": cost,
		"kind": kind,
		"attack_type": attack_type,
		"ability": ability,
		"attack_bonus": attack_bonus.text,
		"range": range_cells,
		"long_range": long_range,
		"target": target,
		"area": area,
		"area_size": area_size,
		"damage": dmg,
		"tags": tags.duplicate(),
		"save_ability": save_ability,
		"save_dc": save_dc.text,
		"save_half": save_half,
		"heal": heal.text,
		"effects": fx,
		"resource": resource,
		"resource_cost": resource_cost,
		"concentration": concentration,
		"mastery": mastery,
		"special": special,
		"sub_actions": sub_actions.duplicate(),
		"item": item,
		"consumes": consumes,
		"two_handed": two_handed,
	}
	# Только у заклинаний с ячейками: прочие действия (и старые сохранения) не меняются.
	if spell_level > 0:
		data["spell_level"] = spell_level
		data["upcast"] = upcast
		data["cast_level"] = cast_level
	return data


## Читает действие из данных. Ошибки (неизвестные значения, плохие формулы)
## дописываются в [param errors]; действие всё равно возвращается.
static func from_dict(data: Dictionary, errors: Array[String] = []) -> ActionDef:
	var a := ActionDef.new()
	a.id = JsonRead.get_str(data, "id")
	a.name_key = JsonRead.get_str(data, "name_key", a.id)
	a.cost = JsonRead.get_str(data, "cost", COST_ACTION)
	a.kind = JsonRead.get_str(data, "kind", KIND_ATTACK)
	a.attack_type = JsonRead.get_str(data, "attack_type", MELEE)
	a.ability = JsonRead.get_str(data, "ability")
	a.attack_bonus = _formula(data, "attack_bonus", "MOD + PROF", a.id, errors)
	a.range_cells = JsonRead.get_int(data, "range", 1)
	a.long_range = JsonRead.get_int(data, "long_range")
	a.target = JsonRead.get_str(data, "target", TARGET_ENEMY)
	a.area = JsonRead.get_str(data, "area")
	a.area_size = JsonRead.get_int(data, "area_size")
	for item: Variant in JsonRead.get_array(data, "damage"):
		var entry: Dictionary = item
		var part := DamagePart.from_dict(entry)
		if not part.formula.is_valid():
			errors.append("%s: bad damage formula '%s'" % [a.id, part.formula.text])
		if not DamageRules.is_type(part.damage_type):
			errors.append("%s: unknown damage type '%s'" % [a.id, part.damage_type])
		a.damage.append(part)
	a.tags = JsonRead.get_str_array(data, "tags")
	a.save_ability = JsonRead.get_str(data, "save_ability")
	a.save_dc = _formula(data, "save_dc", "8 + PROF + MOD", a.id, errors)
	a.save_half = JsonRead.get_bool(data, "save_half")
	a.heal = _formula(data, "heal", "0", a.id, errors)
	for item: Variant in JsonRead.get_array(data, "effects"):
		var entry: Dictionary = item
		var effect := EffectDef.from_dict(entry)
		if not Conditions.is_condition(effect.condition):
			errors.append("%s: unknown condition '%s'" % [a.id, effect.condition])
		a.effects.append(effect)
	a.resource = JsonRead.get_str(data, "resource")
	a.resource_cost = JsonRead.get_int(data, "resource_cost", 1)
	a.concentration = JsonRead.get_bool(data, "concentration")
	a.mastery = JsonRead.get_str(data, "mastery")
	a.special = JsonRead.get_str(data, "special")
	a.sub_actions = JsonRead.get_str_array(data, "sub_actions")
	a.item = JsonRead.get_str(data, "item")
	a.consumes = JsonRead.get_bool(data, "consumes")
	a.two_handed = JsonRead.get_bool(data, "two_handed")
	a.spell_level = clampi(JsonRead.get_int(data, "spell_level"), 0, 9)
	a.upcast = JsonRead.get_str(data, "upcast")
	a.cast_level = JsonRead.get_int(data, "cast_level")
	if a.spell_level > 0 and a.resource == "":
		a.resource = "slot_%d" % a.spell_level
	if a.upcast != "" and not _is_dice(a.upcast):
		errors.append("%s: upcast must be dice like 1d6" % a.id)
	_check(a, errors)
	return a


static func _is_dice(text: String) -> bool:
	var parts := text.split("d")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()


## Копия, сотворённая ячейкой круга [param level]: выше круга — урон или лечение
## больше на [member upcast] за каждый круг.
func cast_with(level: int) -> ActionDef:
	var copy := ActionDef.from_dict(to_dict())
	copy.cast_level = level
	var extra := level - spell_level
	if extra <= 0 or upcast == "":
		return copy
	var parts := upcast.split("d")
	var dice := "%dd%s" % [parts[0].to_int() * extra, parts[1]]
	if kind == KIND_HEAL:
		copy.heal = Formula.parse(heal.text + " + " + dice)
	elif not damage.is_empty():
		copy.damage.append(DamagePart.new(Formula.parse(dice), damage[0].damage_type))
	return copy


static func _formula(
	data: Dictionary, key: String, default: String, id: String, errors: Array[String]
) -> Formula:
	var f := Formula.parse(JsonRead.get_str(data, key, default))
	if not f.is_valid():
		errors.append("%s: bad formula in '%s': %s" % [id, key, f.error])
	return f


static func _check(a: ActionDef, errors: Array[String]) -> void:
	if a.id == "":
		errors.append("action without id")
	if not COSTS.has(a.cost):
		errors.append("%s: unknown cost '%s'" % [a.id, a.cost])
	if not KINDS.has(a.kind):
		errors.append("%s: unknown kind '%s'" % [a.id, a.kind])
	if not TARGETS.has(a.target):
		errors.append("%s: unknown target '%s'" % [a.id, a.target])
	if a.area != "" and a.area != AREA_BURST and a.area != AREA_CONE:
		errors.append("%s: unknown area '%s'" % [a.id, a.area])
	if a.save_ability != "" and not Abilities.is_ability(a.save_ability):
		errors.append("%s: unknown save ability '%s'" % [a.id, a.save_ability])
	if a.mastery != "" and not MASTERIES.has(a.mastery):
		errors.append("%s: unknown mastery '%s'" % [a.id, a.mastery])
	if a.special != "" and not SPECIALS.has(a.special):
		errors.append("%s: unknown special '%s'" % [a.id, a.special])
	if a.attack_bonus.has_dice() or a.save_dc.has_dice():
		errors.append("%s: attack_bonus and save_dc must not roll dice" % a.id)
	if a.kind == KIND_SAVE and a.save_ability == "":
		errors.append("%s: save action needs save_ability" % a.id)
