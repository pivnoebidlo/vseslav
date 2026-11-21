class_name EquipmentScreen
extends PanelContainer
## Экран снаряжения партии (ADR-0024): вкладки героев, что надето, пояс, мешок,
## характеристики, нагрузка и кошелёк. Все изменения — через Inventory; итоги
## (КД, атаки, скорость) пересчитывает сборщик бойца.

signal closed(changed: bool)

const COLUMN_GAP := 18

var _db: RulesDb
var _party: Party
var _heroes: Array[String] = []
var _current := ""
var _changed := false
var _note := ""

var _tabs := HBoxContainer.new()
var _body := HBoxContainer.new()
var _status := Label.new()
var _note_label := Label.new()


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
	title.text = TranslationServer.translate("UI_EQUIPMENT")
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	header.add_child(_tabs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_button("UI_EQ_RESET", ActionDef.COST_FREE, _on_reset))
	header.add_child(_button("UI_EQ_CLOSE", ActionDef.COST_REACTION, _on_close))
	_note_label.add_theme_font_size_override("font_size", 12)
	_note_label.add_theme_color_override("font_color", UiStyle.HP_HURT)
	box.add_child(_note_label)
	_body.add_theme_constant_override("separation", COLUMN_GAP)
	box.add_child(_body)
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UiStyle.HP_LOW)
	box.add_child(_status)
	visible = false


## Открывает экран. [param note] — предупреждение (например, что бой начнётся заново).
func open(db: RulesDb, party: Party, heroes: Array[String], note: String) -> void:
	_db = db
	_party = party
	_heroes = heroes
	if not _heroes.has(_current):
		_current = _heroes[0] if not _heroes.is_empty() else ""
	_changed = false
	_note = note
	_status.text = ""
	visible = true
	_rebuild()


func _rebuild() -> void:
	_note_label.text = _note
	_note_label.visible = _note != ""
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for id in _heroes:
		var tab := Button.new()
		tab.text = TranslationServer.translate(_hero_name_key(id))
		tab.toggle_mode = true
		tab.button_pressed = id == _current
		UiStyle.style_cost_button(tab, ActionDef.COST_REACTION, id == _current)
		tab.pressed.connect(_on_tab.bind(id))
		_tabs.add_child(tab)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _current == "":
		return
	var inv := _party.inventories[_current]
	_body.add_child(_worn_column(inv))
	_body.add_child(_bag_column(inv))
	_body.add_child(_stats_column(inv))


# --- Колонки ---------------------------------------------------------------------


func _worn_column(inv: Inventory) -> VBoxContainer:
	var col := _column(260)
	col.add_child(_heading("UI_EQ_WORN"))
	for slot in Inventory.SLOTS:
		var row := HBoxContainer.new()
		var label := Label.new()
		var item_id := inv.slot_item(slot)
		label.text = (
			"%s: %s"
			% [
				TranslationServer.translate("UI_SLOT_" + slot.to_upper()),
				_item_name(item_id) if item_id != "" else "—"
			]
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		if item_id != "":
			row.add_child(_small("UI_EQ_UNEQUIP", func() -> void: _apply(inv.unequip(slot))))
		col.add_child(row)
	col.add_child(HSeparator.new())
	col.add_child(
		_heading_text(
			CombatLogFormat.tr_fmt("UI_EQ_BELT", {"n": inv.belt.size(), "max": Inventory.BELT_SIZE})
		)
	)
	for s in inv.belt:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _stack_text(s)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var item_id := s.item
		row.add_child(_small("UI_EQ_TO_BAG", func() -> void: _apply(inv.from_belt(item_id))))
		col.add_child(row)
	col.add_child(HSeparator.new())
	var purse_row := HBoxContainer.new()
	var purse := Label.new()
	purse.text = CombatLogFormat.tr_fmt("UI_EQ_PURSE", {"money": money_text(inv.purse)})
	purse.add_theme_font_size_override("font_size", 13)
	purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purse_row.add_child(purse)
	if _heroes.size() > 1 and inv.purse > 0:
		purse_row.add_child(_money_menu(inv))
	col.add_child(purse_row)
	return col


## «Передать деньги»: каждому из остальных героев — 1 куна, 1 гривна или всё.
func _money_menu(inv: Inventory) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = TranslationServer.translate("UI_EQ_GIVE") + " ▾"
	menu.flat = false
	UiStyle.style_cost_button(menu, ActionDef.COST_FREE, false)
	menu.add_theme_font_size_override("font_size", 12)
	var choices: Array[Array] = []
	for id in _heroes:
		if id == _current:
			continue
		var amounts: Array[int] = []
		for amount: int in [1, Money.KUNY_PER_GRIVNA, inv.purse]:
			if amount <= inv.purse and not amounts.has(amount):
				amounts.append(amount)
		for amount in amounts:
			var label := CombatLogFormat.tr_fmt(
				"UI_EQ_GIVE_MONEY",
				{
					"hero": TranslationServer.translate(_hero_name_key(id)),
					"money": money_text(amount)
				}
			)
			menu.get_popup().add_item(label)
			choices.append([id, amount])
	menu.get_popup().index_pressed.connect(
		func(index: int) -> void:
			var to: String = choices[index][0]
			var amount: int = choices[index][1]
			_apply(inv.give_money(amount, _party.inventories[to]))
	)
	return menu


func _bag_column(inv: Inventory) -> VBoxContainer:
	var col := _column(360)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_heading("UI_EQ_BAG"))
	if inv.bag.is_empty():
		var empty := Label.new()
		empty.text = "—"
		col.add_child(empty)
	for s in inv.bag:
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 2)
		var label := Label.new()
		label.text = (
			CombatLogFormat
			. tr_fmt(
				"UI_EQ_ROW",
				{
					"name": _stack_text(s),
					"weight": weight_text(ItemInfo.weight(_db, s.item)),
					"price": money_text(ItemInfo.price(_db, s.item)),
				}
			)
		)
		label.add_theme_font_size_override("font_size", 13)
		line.add_child(label)
		line.add_child(_bag_buttons(inv, s.item))
		col.add_child(line)
	return col


func _bag_buttons(inv: Inventory, item_id: String) -> HFlowContainer:
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 4)
	match ItemInfo.item_type(_db, item_id):
		"armor":
			buttons.add_child(
				_small(
					"UI_EQ_WEAR",
					func() -> void: _apply(inv.equip(_db, item_id, Inventory.SLOT_ARMOR))
				)
			)
		"shield":
			buttons.add_child(
				_small(
					"UI_EQ_OFF", func() -> void: _apply(inv.equip(_db, item_id, Inventory.SLOT_OFF))
				)
			)
		"weapon":
			buttons.add_child(
				_small(
					"UI_EQ_MAIN",
					func() -> void: _apply(inv.equip(_db, item_id, Inventory.SLOT_MAIN))
				)
			)
			if ItemInfo.has_property(_db, item_id, "light"):
				buttons.add_child(
					_small(
						"UI_EQ_OFF",
						func() -> void: _apply(inv.equip(_db, item_id, Inventory.SLOT_OFF))
					)
				)
	if ItemInfo.fits_belt(_db, item_id):
		buttons.add_child(
			_small("UI_EQ_BELT_PUT", func() -> void: _apply(inv.to_belt(_db, item_id)))
		)
	if _heroes.size() > 1:
		buttons.add_child(_give_menu(inv, item_id))
	return buttons


func _give_menu(inv: Inventory, item_id: String) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = TranslationServer.translate("UI_EQ_GIVE") + " ▾"
	menu.flat = false
	UiStyle.style_cost_button(menu, ActionDef.COST_FREE, false)
	menu.add_theme_font_size_override("font_size", 12)
	var others: Array[String] = []
	for id in _heroes:
		if id != _current:
			others.append(id)
			menu.get_popup().add_item(TranslationServer.translate(_hero_name_key(id)))
	menu.get_popup().index_pressed.connect(
		func(index: int) -> void:
			var to := others[index]
			_apply(inv.give(_db, item_id, 1, _party.inventories[to], _strength(to)))
	)
	return menu


func _stats_column(inv: Inventory) -> VBoxContainer:
	var col := _column(240)
	col.add_child(_heading("UI_EQ_STATS_TITLE"))
	var hero := _party.build_hero(_db, _current)
	var stats := Label.new()
	stats.text = CombatLogFormat.tr_fmt(
		"UI_EQ_STATS",
		{"ac": hero.armor_class, "hp": "%d/%d" % [hero.hp, hero.max_hp], "speed": hero.speed}
	)
	stats.add_theme_font_size_override("font_size", 14)
	col.add_child(stats)
	col.add_child(_heading("UI_EQ_ATTACKS"))
	for a in hero.actions:
		if a.kind != ActionDef.KIND_ATTACK or not hero.item_ready(a):
			continue
		var bonus := a.attack_bonus.value_range(hero.formula_vars(a)).x
		var dmg := Vector2i.ZERO
		for part in a.damage:
			var r := part.formula.value_range(hero.formula_vars(a))
			dmg += r
		var line := Label.new()
		line.text = (
			"%s  %s · %d–%d"
			% [TranslationServer.translate(a.name_key), CombatLogFormat.signed(bonus), dmg.x, dmg.y]
		)
		if a.item != "" and inv.in_hands(a.item):
			line.text = "✋ " + line.text
		line.add_theme_font_size_override("font_size", 13)
		col.add_child(line)
	col.add_child(HSeparator.new())
	var weight := inv.weight(_db)
	var cap := ItemInfo.carry_limit(hero.abilities.score(Abilities.STR))
	var load_label := Label.new()
	load_label.text = CombatLogFormat.tr_fmt(
		"UI_EQ_LOAD", {"weight": weight_text(weight), "cap": weight_text(cap)}
	)
	load_label.add_theme_font_size_override("font_size", 13)
	col.add_child(load_label)
	col.add_child(_load_bar(weight, cap))
	if weight > cap:
		var over := Label.new()
		over.text = TranslationServer.translate("UI_EQ_OVERLOAD")
		over.add_theme_color_override("font_color", UiStyle.HP_LOW)
		over.add_theme_font_size_override("font_size", 12)
		col.add_child(over)
	return col


## Полоска нагрузки: доля от грузоподъёмности; жёлтая с половины, красная при перегрузе.
func _load_bar(weight: int, cap: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(cap, 1)
	bar.value = mini(weight, cap)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override(
		"background", UiStyle.box(Color(0, 0, 0, 0.55), Color.TRANSPARENT, 0, 2)
	)
	var color := UiStyle.HP_GOOD
	if weight > cap:
		color = UiStyle.HP_LOW
	elif weight * 2 > cap:
		color = UiStyle.HP_HURT
	var fill := UiStyle.box(color, Color.TRANSPARENT, 0, 2)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	return bar


# --- Действия --------------------------------------------------------------------


func _apply(err: String) -> void:
	if err == "":
		_changed = true
		_status.text = ""
	else:
		_status.text = TranslationServer.translate(err)
	_rebuild()


func _on_tab(id: String) -> void:
	_current = id
	_status.text = ""
	_rebuild()


func _on_reset() -> void:
	var fresh := Party.from_db(_db)
	_party.inventories = fresh.inventories
	_changed = true
	_rebuild()


func _on_close() -> void:
	visible = false
	closed.emit(_changed)


# --- Оформление ------------------------------------------------------------------


## «2 гривны 7 кун» с русскими падежами; в английском формы одинаковые.
static func money_text(kuny: int) -> String:
	var g := Money.grivny(kuny)
	var k := Money.remainder_kuny(kuny)
	var parts: PackedStringArray = []
	if g > 0:
		parts.append("%d %s" % [g, TranslationServer.translate("UI_GRIVNA_" + _plural_form(g))])
	if k > 0 or g == 0:
		parts.append("%d %s" % [k, TranslationServer.translate("UI_KUNA_" + _plural_form(k))])
	return " ".join(parts)


## Вес из десятых долей фунта: «55» или «0,5».
static func weight_text(tenths: int) -> String:
	if tenths % 10 == 0:
		return str(tenths / 10)
	return "%d,%d" % [tenths / 10, tenths % 10]


## Форма слова по числу: "1" (одна), "2" (две–четыре), "5" (пять и больше).
static func _plural_form(n: int) -> String:
	var tens := (n / 10) % 10
	var ones := n % 10
	if tens == 1:
		return "5"
	if ones == 1:
		return "1"
	if ones >= 2 and ones <= 4:
		return "2"
	return "5"


func _stack_text(s: ItemStack) -> String:
	var text := _item_name(s.item)
	if s.count > 1:
		text += " ×%d" % s.count
	return text


func _item_name(item_id: String) -> String:
	if not _db.items.has(item_id):
		return item_id
	var item: Dictionary = _db.items[item_id]
	return TranslationServer.translate(JsonRead.get_str(item, "name_key", item_id))


func _hero_name_key(id: String) -> String:
	if not _db.characters.has(id):
		return id
	var data: Dictionary = _db.characters[id]
	return JsonRead.get_str(data, "name_key", id)


func _strength(id: String) -> int:
	var errors: Array[String] = []
	var hero := CombatantBuilder.from_character(_db, _db.characters[id], errors)
	return hero.abilities.score(Abilities.STR)


func _column(width: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 6)
	return col


func _heading(key: String) -> Label:
	return _heading_text(TranslationServer.translate(key))


func _heading_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _button(key: String, cost: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = TranslationServer.translate(key)
	UiStyle.style_cost_button(b, cost, false)
	b.pressed.connect(handler)
	return b


func _small(key: String, handler: Callable) -> Button:
	var b := _button(key, ActionDef.COST_FREE, handler)
	b.add_theme_font_size_override("font_size", 12)
	return b
