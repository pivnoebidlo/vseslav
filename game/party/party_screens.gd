class_name PartyScreens
extends Control
## Снаряжение и торг партии между боями (ADR-0024, ADR-0025): держит партию
## и купцов, открывает их экраны, сохраняет изменения. Сигнал [signal changed] —
## снаряжение изменилось.

signal changed
signal message(text: String)
## Окно добычи закрыто (сундук на карте: что не взяли — остаётся в нём).
signal loot_finished
## Отряд получил опыт за победу (каждому по [param amount]).
signal xp_gained(amount: int)
## Экран торга закрыт (разговор с купцом продолжает сцена, ADR-0049).
signal trade_closed
## Выбран город на глобальной карте (ADR-0051); экран карты уже закрыт.
signal travel_chosen(city_id: String)

var party: Party
var market: Market
## Не сохранять на диск (дымовые прогоны ИИ).
var dry_run := false

var _db: RulesDb
var _equipment: EquipmentScreen
var _trade: TradeScreen
var _loot: LootScreen
var _rest: RestScreen
var _hero: HeroScreen
var _world: WorldMapScreen


## [param merchants] — купцы из модулей (ModuleContent.merchants_data).
func setup(db: RulesDb, merchants: Dictionary) -> void:
	_db = db
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	party = PartyStore.load_party(db)
	var errors: Array[String] = []
	market = MarketStore.load_market(db, merchants, errors)
	for err in errors:
		push_warning("Merchants: %s" % err)
	# Экраны создаются здесь, а не при объявлении: к этому моменту язык уже выбран.
	_equipment = EquipmentScreen.new()
	_trade = TradeScreen.new()
	_loot = LootScreen.new()
	_rest = RestScreen.new()
	_hero = HeroScreen.new()
	_world = WorldMapScreen.new()
	_world.travel_chosen.connect(_on_travel_chosen)
	for screen: PanelContainer in [_equipment, _trade, _loot, _rest, _hero, _world]:
		screen.set_anchors_preset(Control.PRESET_CENTER)
		screen.grow_horizontal = Control.GROW_DIRECTION_BOTH
		screen.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(screen)
	_equipment.closed.connect(_on_closed)
	_trade.closed.connect(_on_trade_closed)
	_loot.closed.connect(_on_loot_closed)
	_rest.closed.connect(_on_rest_closed)
	_hero.closed.connect(_on_hero_closed)


## Герои партии, которые участвуют в бою [param state].
static func heroes_of(state: CombatState, p: Party) -> Array[String]:
	var heroes: Array[String] = []
	for c in state.combatants:
		if c.inventory != null and p.inventories.has(c.template):
			heroes.append(c.template)
	return heroes


func open_equipment_for(heroes: Array[String], note: String = "") -> void:
	_trade.visible = false
	_rest.visible = false
	_equipment.open(_db, party, heroes, note)


## Вне боя (на карте): героев называет сцена. [param merchant_id] — купец, к
## которому подошли (ADR-0049); пусто — выбранный раньше или первый.
func open_trade_for(heroes: Array[String], note: String = "", merchant_id: String = "") -> void:
	_equipment.visible = false
	_rest.visible = false
	_trade.open(_db, party, market, heroes, note, merchant_id)


## Окно «Герой» (ADR-0043): лист персонажа, опыт, повышение уровня.
## Глобальная карта (ADR-0051): [param map] — схема, [param here] — город или пусто.
func open_map(map: WorldMap, here: String, day: int) -> void:
	_hide_all()
	_world.open(map, here, day)


func _on_travel_chosen(city_id: String) -> void:
	_world.close()
	travel_chosen.emit(city_id)


func open_hero_for(heroes: Array[String]) -> void:
	_hide_all()
	_hero.open(_db, party, heroes)


func _hide_all() -> void:
	for screen: Control in [_equipment, _trade, _rest, _loot, _hero, _world]:
		screen.visible = false


func open_rest_for(heroes: Array[String]) -> void:
	_equipment.visible = false
	_trade.visible = false
	_rest.open(_db, party, heroes, Rng.new(randi()))


## Содержимое сундука [param title]: делят герои [param heroes]; [param pile] меняется
## по мере взятия.
func open_chest(title: String, pile: Inventory, heroes: Array[String]) -> void:
	_equipment.visible = false
	_trade.visible = false
	_rest.visible = false
	_loot.open(_db, party, pile, heroes, title, "UI_CHEST_HINT")


func is_open() -> bool:
	return (
		_equipment.visible
		or _trade.visible
		or _rest.visible
		or _loot.visible
		or _hero.visible
		or _world.visible
	)


## Закрывает одно открытое окно (Esc на карте, ADR-0035). Видимое окно одно: открытие
## любого прячет остальные.
func close_top() -> void:
	if _world.visible:
		_world.close()
	elif _hero.visible:
		_hero.close()
	elif _trade.visible:
		_trade.close()
	elif _equipment.visible:
		_equipment.close()
	elif _rest.visible:
		_rest.close()
	elif _loot.visible:
		_loot.close()


## После боя: опыт за победу, добыча, затем потраченное списывается из снаряжения.
## Добыча считается отдельным генератором — копией генератора боя, — состояние
## боя не меняется. В дымовом прогоне окно добычи не открывается.
## Возвращает, сколько опыта получил каждый в отряде.
func after_combat(state: CombatState) -> int:
	# Поражение не сохраняется: партия остаётся такой, как перед боем.
	if not Loot.heroes_won(state):
		return 0
	var xp := Party.combat_xp(_db, state)
	party.give_xp(xp)
	if xp > 0:
		xp_gained.emit(xp)
	var pile := Loot.collect(state, _db, party, Rng.from_dict(state.rng.to_dict()))
	party.take_from_combat(state)
	save()
	if dry_run or (pile.purse == 0 and pile.bag.is_empty()):
		return xp
	_equipment.visible = false
	_trade.visible = false
	var heroes := heroes_of(state, party)
	_loot.open(_db, party, pile, heroes)
	return xp


func save() -> void:
	if dry_run:
		return
	PartyStore.save_party(party)
	MarketStore.save_market(market)


func _on_rest_closed(was_changed: bool) -> void:
	if was_changed:
		save()
		message.emit(TranslationServer.translate("LOG_REST_SAVED"))


func _on_hero_closed(was_changed: bool) -> void:
	if was_changed:
		save()
		message.emit(TranslationServer.translate("LOG_HERO_SAVED"))
		changed.emit()


func _on_loot_closed(was_changed: bool) -> void:
	if was_changed:
		save()
		message.emit(TranslationServer.translate("LOG_LOOT_TAKEN"))
	loot_finished.emit()


func _on_closed(was_changed: bool) -> void:
	if not was_changed:
		return
	save()
	message.emit(TranslationServer.translate("LOG_EQUIPMENT_SAVED"))
	changed.emit()


## Торг закрыт: сохранить, сообщить и вернуть сцене разговор с купцом.
func _on_trade_closed(was_changed: bool) -> void:
	if was_changed:
		save()
		message.emit(TranslationServer.translate("LOG_EQUIPMENT_SAVED"))
		changed.emit()
	trade_closed.emit()
