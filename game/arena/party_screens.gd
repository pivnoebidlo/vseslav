class_name PartyScreens
extends Control
## Снаряжение и торг партии между боями (ADR-0024, ADR-0025): держит партию
## и купцов, открывает их экраны, сохраняет изменения. Сигнал [signal changed] —
## снаряжение изменилось (арена начинает бой заново, если он идёт).

signal changed
signal message(text: String)

var party: Party
var market: Market
## Не сохранять на диск (дымовые прогоны ИИ).
var dry_run := false

var _db: RulesDb
var _equipment: EquipmentScreen
var _trade: TradeScreen
var _loot: LootScreen
var _rest: RestScreen


func setup(db: RulesDb) -> void:
	_db = db
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	party = PartyStore.load_party(db)
	var errors: Array[String] = []
	market = MarketStore.load_market(db, errors)
	for err in errors:
		push_warning("Merchants: %s" % err)
	# Экраны создаются здесь, а не при объявлении: к этому моменту язык уже выбран.
	_equipment = EquipmentScreen.new()
	_trade = TradeScreen.new()
	_loot = LootScreen.new()
	_rest = RestScreen.new()
	for screen: PanelContainer in [_equipment, _trade, _loot, _rest]:
		screen.set_anchors_preset(Control.PRESET_CENTER)
		screen.grow_horizontal = Control.GROW_DIRECTION_BOTH
		screen.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(screen)
	_equipment.closed.connect(_on_closed)
	_trade.closed.connect(_on_closed)
	_loot.closed.connect(_on_loot_closed)
	_rest.closed.connect(_on_rest_closed)


## Герои партии, которые участвуют в бою [param state].
static func heroes_of(state: CombatState, p: Party) -> Array[String]:
	var heroes: Array[String] = []
	for c in state.combatants:
		if c.inventory != null and p.inventories.has(c.template):
			heroes.append(c.template)
	return heroes


func open_equipment(state: CombatState) -> void:
	_trade.visible = false
	_equipment.open(_db, party, heroes_of(state, party), _note(state))


func open_trade(state: CombatState) -> void:
	_equipment.visible = false
	_trade.open(_db, party, market, heroes_of(state, party), _note(state))


## Отдых — только между боями; false — бой ещё идёт.
func open_rest(state: CombatState) -> bool:
	if not state.ended:
		return false
	_equipment.visible = false
	_trade.visible = false
	_rest.open(_db, party, heroes_of(state, party), Rng.new(randi()))
	return true


## После боя: добыча (если победили), затем потраченное списывается из снаряжения.
## Добыча считается отдельным генератором — копией генератора боя, — состояние
## боя не меняется. В дымовом прогоне окно добычи не открывается.
func after_combat(state: CombatState) -> void:
	# Поражение на арене не сохраняется: партия остаётся такой, как перед боем.
	if not Loot.heroes_won(state):
		return
	var pile := Loot.collect(state, _db, party, Rng.from_dict(state.rng.to_dict()))
	party.take_from_combat(state)
	save()
	if dry_run or (pile.purse == 0 and pile.bag.is_empty()):
		return
	_equipment.visible = false
	_trade.visible = false
	var heroes := heroes_of(state, party)
	_loot.open(_db, party, pile, heroes)


func save() -> void:
	if dry_run:
		return
	PartyStore.save_party(party)
	MarketStore.save_market(market)


func _note(state: CombatState) -> String:
	return "" if state.ended else TranslationServer.translate("UI_EQ_RESTART_NOTE")


func _on_rest_closed(was_changed: bool) -> void:
	if was_changed:
		save()
		message.emit(TranslationServer.translate("LOG_REST_SAVED"))


func _on_loot_closed(was_changed: bool) -> void:
	if was_changed:
		save()
		message.emit(TranslationServer.translate("LOG_LOOT_TAKEN"))


func _on_closed(was_changed: bool) -> void:
	if not was_changed:
		return
	save()
	message.emit(TranslationServer.translate("LOG_EQUIPMENT_SAVED"))
	changed.emit()
