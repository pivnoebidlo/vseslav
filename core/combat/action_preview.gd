class_name ActionPreview
extends RefCounted
## Предпросмотр действия для UI и ИИ: шанс, урон «от — до» после защит цели,
## причины преимущества и помехи. Ничего не бросает и не меняет состояние.

## Шанс успеха действия в процентах: попадания (атака) или провала спасброска цели.
var chance: int = 0
## Шанс критического попадания в процентах (только атаки).
var crit_chance: int = 0
var damage_min: int = 0
var damage_max: int = 0
## Наибольший урон при критическом попадании.
var crit_max: int = 0
var heal_min: int = 0
var heal_max: int = 0
## Для атак — бонус и КД; для спасбросков — модификатор цели и СЛ.
var bonus: int = 0
var target_number: int = 0
var mods: RollModifiers = RollModifiers.new()
## Сработавшие защиты цели: resist, immune, vulnerable.
var defenses: Array[String] = []
## Спасбросок проваливается автоматически.
var auto_fail: bool = false
## Укрытие цели (LineOfSight.Cover): для атак — от атакующего, для спасбросков
## Ловкости — от точки исхода. Бонус уже учтён в target_number или bonus.
var cover: int = LineOfSight.Cover.NONE


## [param cell] — выбранная точка для действий с областью (центр взрыва, направление конуса).
static func for_target(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	cell: Vector2i = ActionResolver.NO_CELL
) -> ActionPreview:
	match action.kind:
		ActionDef.KIND_ATTACK:
			return _attack(state, actor, action, target)
		ActionDef.KIND_MULTI:
			return _multi(state, actor, action, target)
		ActionDef.KIND_SAVE:
			return _save(state, actor, action, target, cell)
		ActionDef.KIND_HEAL:
			var p := ActionPreview.new()
			var r := action.heal.value_range(actor.formula_vars(action))
			p.chance = 100
			p.heal_min = maxi(r.x, 0)
			p.heal_max = maxi(r.y, 0)
			return p
	var effect := ActionPreview.new()
	effect.chance = 100
	return effect


## Доля успехов d20 из 400 (чтобы считать преимущество в целых): [param wins] из 20.
static func _with_mode(wins: int, mode: int) -> int:
	match mode:
		1:
			return 400 - (20 - wins) * (20 - wins)
		-1:
			return wins * wins
	return wins * 20


static func _percent(of_400: int) -> int:
	return IntMath.floor_div(of_400 * 100 + 200, 400)


static func _attack(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant
) -> ActionPreview:
	var p := ActionPreview.new()
	var s := ActionResolver.setup_attack(state, actor, action, target)
	p.bonus = s.bonus
	p.target_number = s.target_ac
	p.mods = s.mods
	p.cover = s.cover
	var wins := 0
	var crits := 0
	for natural in range(1, 21):
		if natural >= s.crit_from:
			wins += 1
			crits += 1
		elif natural != 1 and natural + s.bonus >= s.target_ac:
			wins += 1
	var mode := s.mods.mode()
	p.chance = _percent(_with_mode(wins, mode))
	p.crit_chance = _percent(_with_mode(crits, mode))
	if Conditions.auto_crit(target.conditions, s.distance):
		p.crit_chance = p.chance
	var normal := _damage_range(state, actor, action, target, false, p.defenses)
	var ignored: Array[String] = []
	var crit := _damage_range(state, actor, action, target, true, ignored)
	p.damage_min = normal.x
	p.damage_max = normal.y
	p.crit_max = crit.y
	return p


static func _multi(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant
) -> ActionPreview:
	var total := ActionPreview.new()
	var first := true
	for sub_id in action.sub_actions:
		var sub := actor.get_action(sub_id)
		if sub == null:
			continue
		var p := _attack(state, actor, sub, target)
		if first:
			total.chance = p.chance
			total.crit_chance = p.crit_chance
			total.bonus = p.bonus
			total.target_number = p.target_number
			total.mods = p.mods
			total.cover = p.cover
			total.defenses = p.defenses
			first = false
		total.damage_min += p.damage_min
		total.damage_max += p.damage_max
		total.crit_max += p.crit_max
	return total


static func _save(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant, cell: Vector2i
) -> ActionPreview:
	var p := ActionPreview.new()
	var dc := ActionResolver.save_dc(actor, action)
	p.cover = ActionResolver.save_cover(state, actor, action, target, cell)
	var modifier := target.save_modifier(action.save_ability) + LineOfSight.ac_bonus(p.cover)
	p.bonus = modifier
	p.target_number = dc
	if Conditions.save_auto_fail(target.conditions, action.save_ability):
		p.auto_fail = true
		p.chance = 100
	else:
		p.mods = Conditions.save_modifiers(target.conditions, action.save_ability)
		var successes := 0
		for natural in range(1, 21):
			if natural + modifier >= dc:
				successes += 1
		p.chance = 100 - _percent(_with_mode(successes, p.mods.mode()))
	var vars := actor.formula_vars(action)
	for part in action.damage:
		var r := part.formula.value_range(vars)
		var tags := _tags(action, part.damage_type)
		var lo := DamageRules.modify(maxi(r.x, 0), part.damage_type, tags, target.defenses)
		var hi := DamageRules.modify(
			maxi(r.y, 0), part.damage_type, tags, target.defenses, p.defenses
		)
		if action.save_half:
			lo = IntMath.floor_div(lo, 2)
		else:
			lo = 0
		p.damage_min += lo
		p.damage_max += hi
	p.crit_max = p.damage_max
	return p


## Урон «от — до» с учётом черт (метка, добыча охотника) и защит цели.
static func _damage_range(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: Combatant,
	critical: bool,
	applied: Array[String]
) -> Vector2i:
	var vars := actor.formula_vars(action)
	var parts: Array[Array] = []
	for part in action.damage:
		parts.append([part.damage_type, part.formula.value_range(vars, critical)])
	for i in actor.traits.size():
		var t := actor.traits[i]
		if t.type != TraitDef.BONUS_DAMAGE:
			continue
		if t.attack_type != "" and t.attack_type != action.attack_type:
			continue
		if t.when == TraitDef.WHEN_TARGET_MARKED:
			if not Conditions.has_from(target.conditions, Conditions.MARKED, actor.id):
				continue
		if t.when == TraitDef.WHEN_TARGET_WOUNDED and target.hp >= target.max_hp:
			continue
		if t.once_per_turn and state.turn_once.has("trait_%d" % i):
			continue
		var damage_type := t.damage_type
		if damage_type == "" and not action.damage.is_empty():
			damage_type = action.damage[0].damage_type
		parts.append([damage_type, t.formula.value_range(vars, critical)])
	var total := Vector2i.ZERO
	for pair in parts:
		var damage_type: String = pair[0]
		var r: Vector2i = pair[1]
		var tags := _tags(action, damage_type)
		total.x += DamageRules.modify(maxi(r.x, 0), damage_type, tags, target.defenses)
		total.y += DamageRules.modify(maxi(r.y, 0), damage_type, tags, target.defenses, applied)
	return total


static func _tags(action: ActionDef, damage_type: String) -> Array[String]:
	var tags: Array[String] = action.tags.duplicate()
	tags.append(damage_type)
	return tags


func to_dict() -> Dictionary:
	return {
		"chance": chance,
		"crit_chance": crit_chance,
		"damage": [damage_min, damage_max],
		"crit_max": crit_max,
		"heal": [heal_min, heal_max],
		"bonus": bonus,
		"target_number": target_number,
		"mods": mods.to_dict(),
		"defenses": defenses.duplicate(),
		"auto_fail": auto_fail,
		"cover": cover,
	}
