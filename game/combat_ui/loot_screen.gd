class_name LootScreen
extends PanelContainer
## Добыча после победы (ADR-0026): каждую вещь и деньги забирает выбранный герой
## (вручную). Не взятое при закрытии остаётся на поле боя.

signal closed(changed: bool)

var _db: RulesDb
var _party: Party
var _pile: Inventory
var _heroes: Array[String] = []
var _changed := false

var _list := VBoxContainer.new()
var _loads := Label.new()
var _status := Label.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.13, 0.15), UiStyle.ACTIVE.darkened(0.3), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(620, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_LOOT")
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var done := Button.new()
	done.text = TranslationServer.translate("UI_EQ_CLOSE")
	UiStyle.style_cost_button(done, ActionDef.COST_REACTION, false)
	done.pressed.connect(_on_close)
	header.add_child(done)
	var hint := Label.new()
	hint.text = TranslationServer.translate("UI_LOOT_HINT")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	box.add_child(hint)
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)
	box.add_child(HSeparator.new())
	_loads.add_theme_font_size_override("font_size", 12)
	box.add_child(_loads)
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UiStyle.HP_LOW)
	box.add_child(_status)
	visible = false


func open(db: RulesDb, party: Party, pile: Inventory, heroes: Array[String]) -> void:
	_db = db
	_party = party
	_pile = pile
	_heroes = heroes
	_changed = false
	_status.text = ""
	visible = true
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _pile.purse > 0:
		var money := _pile.purse
		_list.add_child(
			_row(
				CombatLogFormat.tr_fmt(
					"UI_LOOT_MONEY", {"money": EquipmentScreen.money_text(money)}
				),
				func(hero: String) -> void: _apply(_pile.give_money(money, _inv(hero)))
			)
		)
	for s in _pile.bag:
		var item_id := s.item
		var text := (
			"%s%s · %s %s · %s"
			% [
				TranslationServer.translate(_item_name_key(item_id)),
				" ×%d" % s.count if s.count > 1 else "",
				EquipmentScreen.weight_text(ItemInfo.weight(_db, item_id)),
				TranslationServer.translate("UI_LB"),
				EquipmentScreen.money_text(ItemInfo.price(_db, item_id)),
			]
		)
		var take := func(hero: String) -> void: _take(item_id, hero)
		_list.add_child(_row(text, take))
	if _pile.purse == 0 and _pile.bag.is_empty():
		var empty := Label.new()
		empty.text = TranslationServer.translate("UI_LOOT_EMPTY")
		_list.add_child(empty)
	var loads: PackedStringArray = []
	for hero in _heroes:
		(
			loads
			. append(
				(
					"%s: %s / %s"
					% [
						TranslationServer.translate(_hero_name_key(hero)),
						EquipmentScreen.weight_text(_inv(hero).weight(_db)),
						EquipmentScreen.weight_text(ItemInfo.carry_limit(_strength(hero))),
					]
				)
			)
		)
	_loads.text = CombatLogFormat.tr_fmt("UI_LOOT_LOADS", {"list": " · ".join(loads)})


func _take(item_id: String, hero: String) -> void:
	_apply(_pile.give(_db, item_id, 1, _inv(hero), _strength(hero)))


## Строка добычи: текст и по кнопке на каждого героя.
func _row(text: String, take: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	for hero in _heroes:
		var b := Button.new()
		b.text = "→ " + TranslationServer.translate(_hero_name_key(hero))
		b.add_theme_font_size_override("font_size", 12)
		UiStyle.style_cost_button(b, ActionDef.COST_FREE, false)
		b.pressed.connect(take.bind(hero))
		row.add_child(b)
	return row


func _apply(err: String) -> void:
	if err == "":
		_changed = true
		_status.text = ""
	else:
		_status.text = TranslationServer.translate(err)
	_rebuild()


func _on_close() -> void:
	visible = false
	closed.emit(_changed)


func _inv(hero: String) -> Inventory:
	return _party.inventories[hero]


func _strength(hero: String) -> int:
	var errors: Array[String] = []
	return CombatantBuilder.from_character(_db, _db.characters[hero], errors).abilities.score(
		Abilities.STR
	)


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
