class_name CombatAi
extends RefCounted
## ИИ боя (противники и партия в автоигре). Те же команды и проверки, что у игрока;
## детерминирован: при равенстве оценок выбор по id и координатам.
##
## Порядок решений в ходу:
## встать → поднять упавшего союзника → бонусное действие (лечение, второе дыхание,
## метка) → лучшее действие (атака, область или толчок с обрыва) → «Натиск», если
## действие кончилось → перемещение к позиции для удара (повыше, без прыжков, если
## можно) → «Рывок», если никого не достать → конец хода.

## Оценки — в «сотых долях хита», чтобы обойтись целыми числами.
const SCALE := 100
## Область применяется, если задевает не меньше стольких врагов и ни одного союзника.
const AREA_MIN_ENEMIES := 2
## Сколько хитов «стоит» сбить цель с ног (для оценки толчка).
const PRONE_WORTH := 2


static func next_command(state: CombatState) -> CombatCommand:
	var actor := state.current()
	var cmd: CombatCommand = _stand(state, actor)
	if cmd == null:
		cmd = _heal_ally(state, actor, true)
	if cmd == null:
		cmd = _bonus_action(state, actor)
	if cmd == null:
		cmd = _best_action(state, actor)
	if cmd == null:
		cmd = _extra_action(state, actor)
	if cmd == null:
		cmd = _reposition(state, actor)
	if cmd == null:
		cmd = _dash(state, actor)
	if cmd == null:
		cmd = EndTurnCommand.new(actor.id)
	return cmd


# --- Оценки --------------------------------------------------------------------


static func _valid(
	state: CombatState,
	actor: Combatant,
	action: ActionDef,
	target: String,
	cell: Vector2i = ActionResolver.NO_CELL
) -> bool:
	return ActionResolver.validate(state, actor, action, target, cell) == ""


static func _enemies(state: CombatState, actor: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c in state.sorted_combatants():
		if c.is_present() and c.team != actor.team:
			result.append(c)
	return result


## Шанс попадания в процентах (5–95) с учётом преимущества/помехи.
static func hit_chance(bonus: int, ac: int, mode: int) -> int:
	var need := clampi(ac - bonus, 2, 20)
	var single := (21 - need) * 5
	match mode:
		1:
			return 100 - (100 - single) * (100 - single) / 100
		-1:
			return single * single / 100
	return single


## Средний урон частей действия по цели с учётом её защит (без бросков).
static func average_damage(actor: Combatant, action: ActionDef, target: Combatant) -> int:
	var vars := actor.formula_vars(action)
	var total := 0
	for part in action.damage:
		var r := part.formula.value_range(vars)
		var avg := IntMath.floor_div(r.x + r.y, 2)
		var tags := action.tags.duplicate()
		tags.append(part.damage_type)
		var typed: Array[String] = []
		typed.assign(tags)
		total += DamageRules.modify(avg, part.damage_type, typed, target.defenses)
	return total


## Ожидаемая польза атаки по цели (сотые доли хита).
static func attack_value(
	state: CombatState, actor: Combatant, action: ActionDef, target: Combatant
) -> int:
	if action.kind == ActionDef.KIND_MULTI:
		var sum := 0
		for sub_id in action.sub_actions:
			var sub := actor.get_action(sub_id)
			if sub != null:
				sum += attack_value(state, actor, sub, target)
		return sum
	if target.reviving:
		# Павшего упыря имеет смысл бить только тем, что не даёт ему встать.
		return SCALE * 50 if _prevents_revive(action, target) else 0
	# Та же подготовка, что у настоящей атаки: укрытие, приёмы, прикрытие, черты.
	var s := ActionResolver.setup_attack(state, actor, action, target)
	var chance := hit_chance(s.bonus, s.target_ac, s.mods.mode())
	var dmg := average_damage(actor, action, target)
	if target.hp > 0:
		dmg = mini(dmg, target.hp)
	return dmg * chance


## Польза толчка (ADR-0037): только если цель полетит с уступа — шанс провала
## спасброска × (средний урон падения + «сбит с ног»). Иначе 0: просто сбивать
## с ног ИИ пока не умеет.
static func shove_value(state: CombatState, actor: Combatant, target: Combatant) -> int:
	if not target.is_alive():
		return 0
	var dest := ForcedMove.push_cell(state, actor, target)
	if dest == ActionResolver.NO_CELL or not state.grid.is_fall(target.column, dest):
		return 0
	var drop := state.grid.level_at(target.column) - state.grid.level_at(dest)
	var save := maxi(target.save_modifier(Abilities.STR), target.save_modifier(Abilities.DEX))
	var fail := clampi((ForcedMove.shove_dc(actor) - save - 1) * 5, 0, 100)
	var dmg := mini(IntMath.floor_div(CombatRules.fall_dice(drop) * 7, 2), target.hp)
	return fail * (dmg + PRONE_WORTH)


## Хватает ли зарядов и предмет под рукой (без учёта действия в этом ходу).
static func _has_means(actor: Combatant, action: ActionDef) -> bool:
	if action.resource != "" and actor.resource_left(action.resource) < action.resource_cost:
		return false
	if not actor.item_ready(action):
		return false
	if action.item != "" and action.kind == ActionDef.KIND_ATTACK:
		return InventoryCombat.can_draw(actor.inventory, action.item, action.two_handed) == ""
	return true


## Есть ли у участника доступная атака, которая добьёт павшего (огонь, осина…).
static func _can_finish(actor: Combatant, target: Combatant) -> bool:
	for action in actor.actions:
		if action.kind != ActionDef.KIND_ATTACK:
			continue
		if not _has_means(actor, action):
			continue
		if _prevents_revive(action, target):
			return true
	return false


static func _prevents_revive(action: ActionDef, target: Combatant) -> bool:
	var tags := action.tags.duplicate()
	for part in action.damage:
		tags.append(part.damage_type)
	for t in target.traits_of(TraitDef.REVIVE):
		for tag in t.tags:
			if tags.has(tag):
				return true
	return false


## Приоритет цели: стоящие важнее лежащих, добить важнее, чем ранить.
static func _target_weight(target: Combatant, value: int) -> int:
	if value <= 0:
		return 0
	var weight := value
	if target.is_alive():
		weight += SCALE * 10
		weight += SCALE * 20 / maxi(target.hp, 1)
	return weight


# --- Решения -------------------------------------------------------------------


static func _stand(state: CombatState, actor: Combatant) -> CombatCommand:
	var stand := actor.get_action("stand")
	if stand != null and _valid(state, actor, stand, ""):
		return UseActionCommand.new(actor.id, stand.id)
	return null


## Лечение: упавших — всегда; раненых меньше чем на треть — бонусным действием.
static func _heal_ally(state: CombatState, actor: Combatant, downed_only: bool) -> CombatCommand:
	for ally in state.sorted_combatants():
		if ally.team != actor.team or not ally.is_present() or ally.reviving:
			continue
		var needs := ally.hp == 0 or (not downed_only and ally.hp * 3 < ally.max_hp)
		if not needs:
			continue
		var options: Array[ActionDef] = []
		for action in actor.actions:
			if action.kind == ActionDef.KIND_HEAL and action.target == ActionDef.TARGET_ALLY:
				options.append(action)
		# Бонусное лечение — первым: оно оставляет действие для атаки.
		options.sort_custom(
			func(a: ActionDef, b: ActionDef) -> bool:
				if a.cost != b.cost:
					return a.cost == ActionDef.COST_BONUS
				return a.id < b.id
		)
		for action in options:
			if downed_only or action.cost == ActionDef.COST_BONUS:
				if _valid(state, actor, action, ally.id):
					return UseActionCommand.new(actor.id, action.id, ally.id)
	return null


static func _bonus_action(state: CombatState, actor: Combatant) -> CombatCommand:
	if state.bonus_used:
		return null
	var heal := _heal_ally(state, actor, false)
	if heal != null:
		return heal
	for action in actor.actions:
		if action.cost != ActionDef.COST_BONUS:
			continue
		if action.kind == ActionDef.KIND_HEAL and action.target == ActionDef.TARGET_SELF:
			if actor.hp * 2 <= actor.max_hp and _valid(state, actor, action, actor.id):
				return UseActionCommand.new(actor.id, action.id, actor.id)
		if action.kind == ActionDef.KIND_EFFECT and action.target == ActionDef.TARGET_ENEMY:
			if actor.concentration != "":
				continue
			var best: Combatant = null
			for enemy in _enemies(state, actor):
				if enemy.is_alive() and _valid(state, actor, action, enemy.id):
					if best == null or enemy.hp > best.hp:
						best = enemy
			if best != null:
				return UseActionCommand.new(actor.id, action.id, best.id)
	return null


## Лучшее действие стоимостью «действие»: атака по цели или область по клетке.
static func _best_action(state: CombatState, actor: Combatant) -> CombatCommand:
	if state.actions_left <= 0:
		return null
	var best: CombatCommand = null
	var best_score := 0
	for action in actor.actions:
		if action.cost != ActionDef.COST_ACTION:
			continue
		if action.kind == ActionDef.KIND_ATTACK or action.kind == ActionDef.KIND_MULTI:
			for enemy in _enemies(state, actor):
				if not _valid(state, actor, action, enemy.id):
					continue
				var score := _target_weight(enemy, attack_value(state, actor, action, enemy))
				# Ресурсы бережём: расходуемое оружие чуть хуже при равной пользе.
				if action.resource != "" or action.consumes:
					score -= SCALE
				if score > best_score:
					best_score = score
					best = UseActionCommand.new(actor.id, action.id, enemy.id)
		elif action.special == ActionDef.SPECIAL_SHOVE:
			for enemy in _enemies(state, actor):
				if not _valid(state, actor, action, enemy.id):
					continue
				var push := _target_weight(enemy, shove_value(state, actor, enemy))
				if push > best_score:
					best_score = push
					best = UseActionCommand.new(actor.id, action.id, enemy.id)
		elif action.kind == ActionDef.KIND_SAVE and action.area != "":
			var area := _best_area(state, actor, action)
			if area.score > best_score:
				best_score = area.score
				best = UseActionCommand.new(actor.id, action.id, "", area.cell)
	return best


class AreaChoice:
	extends RefCounted
	var cell: Vector2i = ActionResolver.NO_CELL
	var score: int = 0


static func _best_area(state: CombatState, actor: Combatant, action: ActionDef) -> AreaChoice:
	var choice := AreaChoice.new()
	if action.concentration and actor.concentration != "":
		return choice
	var r := action.max_range()
	for z in range(actor.column.y - r, actor.column.y + r + 1):
		for x in range(actor.column.x - r, actor.column.x + r + 1):
			var cell := Vector2i(x, z)
			if not _valid(state, actor, action, "", cell):
				continue
			var enemies := 0
			var hp_sum := 0
			var friendly := false
			for t in ActionResolver.targets_in_area(state, actor, action, cell):
				if t.team == actor.team:
					friendly = true
					break
				if t.is_alive():
					enemies += 1
					hp_sum += mini(t.hp, 30)
			if friendly or enemies < AREA_MIN_ENEMIES:
				continue
			var score := SCALE * 10 * enemies + SCALE * 50 * enemies + hp_sum
			if score > choice.score:
				choice.score = score
				choice.cell = cell
	return choice


static func _extra_action(state: CombatState, actor: Combatant) -> CombatCommand:
	if state.actions_left > 0:
		return null
	for action in actor.actions:
		if action.special == ActionDef.SPECIAL_EXTRA_ACTION and _valid(state, actor, action, ""):
			# Тратим, только если сразу есть по кому ударить.
			for enemy in _enemies(state, actor):
				if enemy.is_alive() and _can_attack_from(state, actor, actor.column, enemy):
					return UseActionCommand.new(actor.id, action.id)
	return null


## Есть ли у участника атака, которая достаёт цель из клетки [param from].
static func _can_attack_from(
	state: CombatState, actor: Combatant, from: Vector2i, target: Combatant
) -> bool:
	for action in actor.actions:
		if action.kind != ActionDef.KIND_ATTACK and action.kind != ActionDef.KIND_MULTI:
			continue
		if not _has_means(actor, action):
			continue
		var reach := (
			action.range_cells if action.kind == ActionDef.KIND_MULTI else action.max_range()
		)
		if reach <= 1:
			if state.reach_between(from, target.column):
				return true
		elif BattleGrid.chebyshev(from, target.column) <= reach:
			if LineOfSight.can_see(state.grid, from, target.column):
				return true
	return false


## Предпочитает ли участник дальний бой (его лучшее оружие — дальнобойное).
static func _prefers_ranged(actor: Combatant) -> bool:
	var best_melee := 0
	var best_ranged := 0
	for action in actor.actions:
		if action.kind != ActionDef.KIND_ATTACK or action.resource != "" or action.consumes:
			continue
		if not _has_means(actor, action):
			continue
		var dmg := 0
		var vars := actor.formula_vars(action)
		for part in action.damage:
			dmg += part.formula.value_range(vars).y
		if action.attack_type == ActionDef.RANGED or action.range_cells > 1:
			best_ranged = maxi(best_ranged, dmg)
		else:
			best_melee = maxi(best_melee, dmg)
	return best_ranged > best_melee


## Перемещение: в клетку, откуда можно ударить (стрелок — подальше от врагов),
## иначе — ближе к врагу. Только если действие ещё не потрачено.
static func _reposition(state: CombatState, actor: Combatant) -> CombatCommand:
	if state.actions_left <= 0 or state.movement_left <= 0:
		return null
	var targets: Array[Combatant] = []
	for e in _enemies(state, actor):
		if e.is_alive() or (e.reviving and _can_finish(actor, e)):
			targets.append(e)
	if targets.is_empty():
		return null
	var ranged := _prefers_ranged(actor)
	var reach := MoveCommand.reachable_for(state, actor)
	# Без прыжков с уступов: клетка, куда только спрыгнуть, — в последнюю очередь.
	var safe := MoveCommand.reachable_for(state, actor, false)
	var best := actor.column
	var best_key := _cell_key(state, actor, actor.column, 0, targets, ranged)
	var cells: Array[Vector2i] = []
	for cell: Vector2i in reach:
		cells.append(cell)
	for cell in cells:
		var key := _cell_key(state, actor, cell, reach[cell], targets, ranged)
		key[1] = 0 if safe.has(cell) else 1
		if _less(key, best_key):
			best = cell
			best_key = key
	if best == actor.column:
		return null
	return MoveCommand.new(actor.id, best)


## Ключ клетки (меньше — лучше): [не может ударить, только прыжком (заполняет
## _reposition), рядом с врагом (для стрелка), сколько врагов видят клетку без
## укрытия (для стрелка), минус уровень высоты (выше — лучше, ADR-0037),
## расстояние до ближайшего врага, стоимость пути, z, x].
static func _cell_key(
	state: CombatState,
	actor: Combatant,
	cell: Vector2i,
	cost: int,
	targets: Array[Combatant],
	ranged: bool
) -> Array[int]:
	var can_hit := false
	var nearest := 1 << 30
	for t in targets:
		nearest = mini(nearest, BattleGrid.chebyshev(cell, t.column))
		if not can_hit and _can_attack_from(state, actor, cell, t):
			can_hit = true
	var adjacent := 1 if ranged and nearest <= 1 else 0
	var exposed := 0
	var distance := nearest
	if ranged and can_hit:
		distance = -nearest
		for t in targets:
			if (
				t.is_alive()
				and LineOfSight.cover(state.grid, t.column, cell) == LineOfSight.Cover.NONE
			):
				exposed += 1
	var height := -state.grid.level_at(cell) if can_hit else 0
	return [0 if can_hit else 1, 0, adjacent, exposed, height, distance, cost, cell.y, cell.x]


static func _dash(state: CombatState, actor: Combatant) -> CombatCommand:
	if state.actions_left <= 0 or state.movement_left > 0:
		return null
	var dash := actor.get_action("dash")
	if dash == null or not _valid(state, actor, dash, ""):
		return null
	for e in _enemies(state, actor):
		if e.is_alive() and _can_attack_from(state, actor, actor.column, e):
			return null
	return UseActionCommand.new(actor.id, dash.id)


static func _less(a: Array[int], b: Array[int]) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
