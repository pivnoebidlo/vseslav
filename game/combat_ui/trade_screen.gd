class_name TradeScreen
extends PanelContainer
## Торг (ADR-0025): купца выбирают на карте, подходя к нему (ADR-0049, ADR-0050),
## здесь — только герой, который торгует; слева товар купца с ценой покупки,
## справа мешок героя с ценой продажи. Деньги — из кошелька выбранного героя.

signal closed(changed: bool)

var _db: RulesDb
var _party: Party
var _market: Market
var _heroes: Array[String] = []
var _hero := ""
var _merchant := ""
var _changed := false
var _note := ""

var _hero_tabs := HBoxContainer.new()
var _body := HBoxContainer.new()
var _note_label := Label.new()
var _status := Label.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.13, 0.15), Color(0.45, 0.5, 0.6), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_TRADE")
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = TranslationServer.translate("UI_EQ_CLOSE")
	UiStyle.style_cost_button(close, ActionDef.COST_REACTION, false)
	close.pressed.connect(_on_close)
	header.add_child(close)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	var who_label := Label.new()
	who_label.text = TranslationServer.translate("UI_TRADE_HERO")
	who.add_child(who_label)
	who.add_child(_hero_tabs)
	box.add_child(who)
	_note_label.add_theme_font_size_override("font_size", 12)
	_note_label.add_theme_color_override("font_color", UiStyle.HP_HURT)
	box.add_child(_note_label)
	_body.add_theme_constant_override("separation", 24)
	box.add_child(_body)
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UiStyle.HP_LOW)
	box.add_child(_status)
	visible = false


## [param merchant_id] — купец, к которому подошли (ADR-0050); торговать можно
## только с ним. Пусто — первый из списка (запасной путь, данных без купца нет).
func open(
	db: RulesDb,
	party: Party,
	market: Market,
	heroes: Array[String],
	note: String,
	merchant_id: String = ""
) -> void:
	_db = db
	_party = party
	_market = market
	_heroes = heroes
	if not _heroes.has(_hero):
		_hero = _heroes[0] if not _heroes.is_empty() else ""
	if merchant_id != "" and _market.order.has(merchant_id):
		_merchant = merchant_id
	if not _market.order.has(_merchant):
		_merchant = _market.order[0] if not _market.order.is_empty() else ""
	_changed = false
	_note = note
	_status.text = ""
	visible = true
	_rebuild()


func _rebuild() -> void:
	_note_label.text = _note
	_note_label.visible = _note != ""
	_fill_tabs(_hero_tabs, _heroes, _hero, _on_hero, false)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _hero == "" or _merchant == "":
		return
	var merchant := _market.get_merchant(_merchant)
	var hero := _party.inventories[_hero]
	_body.add_child(_goods_column(merchant, hero))
	_body.add_child(_bag_column(merchant, hero))


func _fill_tabs(
	tabs: HBoxContainer, ids: Array[String], current: String, handler: Callable, merchants: bool
) -> void:
	for child in tabs.get_children():
		tabs.remove_child(child)
		child.queue_free()
	for id in ids:
		var tab := Button.new()
		var key := _market.get_merchant(id).name_key if merchants else _hero_name_key(id)
		tab.text = TranslationServer.translate(key)
		UiStyle.style_cost_button(tab, ActionDef.COST_REACTION, id == current)
		tab.pressed.connect(handler.bind(id))
		tabs.add_child(tab)


func _goods_column(merchant: Merchant, hero: Inventory) -> VBoxContainer:
	var col := _column()
	col.add_child(
		_heading(
			CombatLogFormat.tr_fmt(
				"UI_TRADE_GOODS",
				{
					"name": TranslationServer.translate(merchant.name_key),
					"money": EquipmentScreen.money_text(merchant.goods.purse)
				}
			)
		)
	)
	if merchant.goods.bag.is_empty():
		col.add_child(_line("—"))
	for s in merchant.goods.bag:
		var item_id := s.item
		var price := merchant.price_to_buy(_db, item_id)
		var row := _row(
			_stack_text(s) + " · " + EquipmentScreen.money_text(price),
			"UI_TRADE_BUY",
			func() -> void: _apply(Trade.buy(_db, merchant, hero, _strength(), item_id))
		)
		col.add_child(row)
	return col


func _bag_column(merchant: Merchant, hero: Inventory) -> VBoxContainer:
	var col := _column()
	var cap := ItemInfo.carry_limit(_strength())
	(
		col
		. add_child(
			_heading(
				(
					CombatLogFormat
					. tr_fmt(
						"UI_TRADE_BAG",
						{
							"money": EquipmentScreen.money_text(hero.purse),
							"weight": EquipmentScreen.weight_text(hero.weight(_db)),
							"cap": EquipmentScreen.weight_text(cap),
						}
					)
				)
			)
		)
	)
	if hero.bag.is_empty():
		col.add_child(_line(TranslationServer.translate("UI_TRADE_BAG_EMPTY")))
	for s in hero.bag:
		var item_id := s.item
		var text := _stack_text(s)
		var price := merchant.price_to_sell(_db, item_id)
		var wanted := merchant.wants(_db, item_id) and price > 0
		if wanted:
			text += " · " + EquipmentScreen.money_text(price)
		else:
			text += " · " + TranslationServer.translate("UI_TRADE_NOT_WANTED")
		var row := _row(
			text,
			"UI_TRADE_SELL",
			func() -> void: _apply(Trade.sell(_db, merchant, hero, item_id)),
			wanted
		)
		col.add_child(row)
	return col


func _apply(err: String) -> void:
	if err == "":
		_changed = true
		_status.text = ""
	else:
		_status.text = TranslationServer.translate(err)
	_rebuild()


func _on_hero(id: String) -> void:
	_hero = id
	_status.text = ""
	_rebuild()


func _on_close() -> void:
	visible = false
	closed.emit(_changed)


func _strength() -> int:
	var errors: Array[String] = []
	var hero := CombatantBuilder.from_character(_db, _db.characters[_hero], errors)
	return hero.abilities.score(Abilities.STR)


func _stack_text(s: ItemStack) -> String:
	var text := TranslationServer.translate(_item_name_key(s.item))
	if s.count > 1:
		text += " ×%d" % s.count
	return text


func _item_name_key(item_id: String) -> String:
	if not _db.items.has(item_id):
		return item_id
	var item: Dictionary = _db.items[item_id]
	return JsonRead.get_str(item, "name_key", item_id)


func _hero_name_key(id: String) -> String:
	if not _db.characters.has(id):
		return id
	var data: Dictionary = _db.characters[id]
	return JsonRead.get_str(data, "name_key", id)


func _column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 6)
	return col


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	return label


func _row(
	text: String, button_key: String, handler: Callable, enabled: bool = true
) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _line(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var b := Button.new()
	b.text = TranslationServer.translate(button_key)
	b.add_theme_font_size_override("font_size", 12)
	UiStyle.style_cost_button(b, ActionDef.COST_FREE, false)
	b.disabled = not enabled
	b.pressed.connect(handler)
	row.add_child(b)
	return row
