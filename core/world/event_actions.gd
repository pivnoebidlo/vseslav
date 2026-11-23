class_name EventActions
extends RefCounted
## Действия декларативных событий (SPEC §8, ADR-0034, ADR-0042): общий язык для
## ответов в диалогах, побед в энкаунтерах, сундуков и событий области.
##   set_flag {flag, value}            set_quest {quest, stage} (флаг quest.<id>)
##   give_item {item, count}           take_item {item, count} (у всего отряда)
##   give_money {kuny} (меньше нуля — забрать)
##   give_xp {amount} — опыт каждому в отряде (ADR-0043)
##   join_party {character}            leave_party {character} (флаг party.<id>)
##   message {text}                    start_dialog {dialog, speaker?}
##   start_combat {encounter}          teleport {area, spawn}
## Последние четыре исполняет игра (EventContext.requests).

const SET_FLAG := "set_flag"
const SET_QUEST := "set_quest"
const GIVE_ITEM := "give_item"
const TAKE_ITEM := "take_item"
const GIVE_MONEY := "give_money"
const GIVE_XP := "give_xp"
const JOIN_PARTY := "join_party"
const LEAVE_PARTY := "leave_party"
const MESSAGE := "message"
const START_DIALOG := "start_dialog"
const START_COMBAT := "start_combat"
const TELEPORT := "teleport"
const ALL: Array[String] = [
	SET_FLAG,
	SET_QUEST,
	GIVE_ITEM,
	TAKE_ITEM,
	GIVE_MONEY,
	GIVE_XP,
	JOIN_PARTY,
	LEAVE_PARTY,
	MESSAGE,
	START_DIALOG,
	START_COMBAT,
	TELEPORT,
]
## Действия, которые исполняет сцена.
const FOR_GAME: Array[String] = [MESSAGE, START_DIALOG, START_COMBAT, TELEPORT]
## Запросы-уведомления о вещах и деньгах (для подсказки игроку).
const NOTICE_ITEM := "item"
const NOTICE_LOST := "item_lost"
const NOTICE_MONEY := "money"
const NOTICE_JOINED := "joined"
const NOTICE_LEFT := "left"
const NOTICE_XP := "xp"


## Флаг, в котором хранится стадия квеста.
static func quest_flag(quest_id: String) -> String:
	return "quest." + quest_id


## Флаг «персонаж в отряде».
static func party_flag(character_id: String) -> String:
	return "party." + character_id


## Только флаги и квесты (старый вызов); возвращает id изменившихся квестов.
static func apply(actions: Array, flags: WorldFlags) -> Array[String]:
	var ctx := EventContext.new(flags)
	run(actions, ctx)
	return ctx.quests


## Применяет действия к [param ctx].
static func run(actions: Array, ctx: EventContext) -> void:
	for raw: Variant in actions:
		var a: Dictionary = raw
		var kind := JsonRead.get_str(a, "action")
		match kind:
			SET_FLAG:
				ctx.flags.set_flag(JsonRead.get_str(a, "flag"), a.get("value", true))
			SET_QUEST:
				_set_quest(a, ctx)
			GIVE_ITEM:
				_give_item(a, ctx)
			TAKE_ITEM:
				_take_item(a, ctx)
			GIVE_MONEY:
				_give_money(a, ctx)
			GIVE_XP:
				var amount := clampi(JsonRead.get_int(a, "amount"), 0, 100000)
				if ctx.party != null and amount > 0:
					ctx.party.give_xp(amount)
					ctx.requests.append({"notice": NOTICE_XP, "amount": amount})
			JOIN_PARTY, LEAVE_PARTY:
				_party_change(a, ctx, kind == JOIN_PARTY)
			_:
				if FOR_GAME.has(kind):
					ctx.requests.append(a.duplicate(true))


static func _set_quest(a: Dictionary, ctx: EventContext) -> void:
	var quest := JsonRead.get_str(a, "quest")
	var stage := JsonRead.get_str(a, "stage")
	var current: Variant = ctx.flags.get_flag(quest_flag(quest))
	# Не начатый квест — false, не строка.
	if typeof(current) != TYPE_STRING or str(current) != stage:
		ctx.flags.set_flag(quest_flag(quest), stage)
		ctx.quests.append(quest)


static func _give_item(a: Dictionary, ctx: EventContext) -> void:
	var who := ctx.receiver_id()
	if who == "" or not ctx.party.inventories.has(who):
		return
	var item := JsonRead.get_str(a, "item")
	var count := maxi(JsonRead.get_int(a, "count", 1), 1)
	ctx.party.inventories[who].add(item, count)
	ctx.requests.append({"notice": NOTICE_ITEM, "item": item, "count": count, "to": who})


## Забирает у отряда (сначала у получателя, затем по порядку) сколько найдётся.
static func _take_item(a: Dictionary, ctx: EventContext) -> void:
	if ctx.party == null:
		return
	var item := JsonRead.get_str(a, "item")
	var left := maxi(JsonRead.get_int(a, "count", 1), 1)
	var order: Array[String] = [ctx.receiver_id()]
	for id in ctx.party.members:
		if not order.has(id):
			order.append(id)
	var taken := 0
	for id in order:
		if left <= 0 or not ctx.party.inventories.has(id):
			continue
		var inv := ctx.party.inventories[id]
		var here := mini(inv.count_of(item), left)
		if here > 0 and inv.remove(item, here):
			left -= here
			taken += here
	if taken > 0:
		ctx.requests.append({"notice": NOTICE_LOST, "item": item, "count": taken})


static func _give_money(a: Dictionary, ctx: EventContext) -> void:
	var who := ctx.receiver_id()
	if who == "":
		return
	var kuny := JsonRead.get_int(a, "kuny")
	if kuny >= 0:
		ctx.party.inventories[who].purse += kuny
	else:
		var left := -kuny
		for id in ctx.party.members:
			var inv := ctx.party.inventories[id]
			var here := mini(inv.purse, left)
			inv.purse -= here
			left -= here
		kuny = -(-kuny - left)
	ctx.requests.append({"notice": NOTICE_MONEY, "kuny": kuny})


static func _party_change(a: Dictionary, ctx: EventContext, join: bool) -> void:
	var id := JsonRead.get_str(a, "character")
	ctx.flags.set_flag(party_flag(id), join)
	if ctx.party == null or not ctx.party.inventories.has(id):
		return
	var changed := ctx.party.join(id) if join else ctx.party.leave(id)
	if changed:
		ctx.requests.append({"notice": NOTICE_JOINED if join else NOTICE_LEFT, "character": id})
