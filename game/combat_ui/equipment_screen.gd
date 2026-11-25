class_name EquipmentScreen
extends PanelContainer
## Окно «Вещи» (ADR-0024, ADR-0035): вкладки героев; сверху — портрет, итоги и что
## надето (ячейки рук и доспеха, пояс), снизу — мешок сеткой. Клик по ячейке
## выбирает вещь, под мешком — её описание и действия. Все изменения — через
## Inventory; итоги (КД, атаки, скорость) пересчитывает сборщик бойца.

signal closed(changed: bool)

const BAG_COLUMNS := 10
const BAG_MIN_CELLS := 30
const BAG_CELL := Vector2(66, 56)
const SLOT_CELL := Vector2(112, 60)
const BELT_CELL := Vector2(82, 52)
const WHERE_SLOT := "slot"
const WHERE_BELT := "belt"
const WHERE_BAG := "bag"
const CELL_BG := Color(0.16, 0.15, 0.13)
const CELL_BORDER := Color(0.36, 0.33, 0.27)

var _db: RulesDb
var _party: Party
var _heroes: Array[String] = []
var _current := ""
var _changed := false
var _note := ""
## Выбранная ячейка: где (WHERE_*) и что — слот или id вещи.
var _sel_where := ""
var _sel_key := ""

var _tabs := HBoxContainer.new()
var _body := VBoxContainer.new()
var _status := Label.new()
var _note_label := Label.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.12, 0.13), Color(0.45, 0.42, 0.35), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_SIDE_ITEMS")
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
	_body.add_theme_constant_override("separation", 10)
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
	_select("", "")
	visible = true
	_rebuild()


func _rebuild() -> void:
	_note_label.text = _note
	_note_label.visible = _note != ""
	_status.visible = _status.text != ""
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
	_drop_stale_selection(inv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	top.add_child(_hero_column(inv))
	top.add_child(_worn_column(inv))
	_body.add_child(top)
	_body.add_child(HSeparator.new())
	_body.add_child(_bag_grid(inv))
	_body.add_child(_details(inv))
	_body.add_child(_footer(inv))
	_recenter.call_deferred()


## Размер меняется с содержимым: подогнать под него и снова поставить по центру.
func _recenter() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


# --- Верх: герой и что надето ----------------------------------------------------


## Портрет (пока буква имени), итоги и атаки.
func _hero_column(inv: Inventory) -> VBoxContainer:
	var col := _column(220)
	var hero := _party.build_hero(_db, _current)
	var face := Label.new()
	face.text = TranslationServer.translate(_hero_name_key(_current)).left(1)
	face.custom_minimum_size = Vector2(0, 70)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.add_theme_font_size_override("font_size", 34)
	face.add_theme_color_override("font_color", Color(0.75, 0.68, 0.52))
	face.add_theme_stylebox_override("normal", UiStyle.box(Color(0.2, 0.18, 0.15), CELL_BORDER, 1))
	col.add_child(face)
	var stats := Label.new()
	stats.text = CombatLogFormat.tr_fmt(
		"UI_EQ_STATS",
		{"ac": hero.armor_class, "hp": "%d/%d" % [hero.hp, hero.max_hp], "speed": hero.speed}
	)
	stats.add_theme_font_size_override("font_size", 13)
	col.add_child(stats)
	col.add_child(_heading("UI_EQ_ATTACKS"))
	for a in hero.actions:
		if a.kind != ActionDef.KIND_ATTACK or not hero.item_ready(a):
			continue
		var bonus := a.attack_bonus.value_range(hero.formula_vars(a)).x
		var dmg := Vector2i.ZERO
		for part in a.damage:
			dmg += part.formula.value_range(hero.formula_vars(a))
		var line := Label.new()
		line.text = (
			"%s  %s · %d–%d"
			% [TranslationServer.translate(a.name_key), CombatLogFormat.signed(bonus), dmg.x, dmg.y]
		)
		if a.item != "" and inv.in_hands(a.item):
			line.text = "✋ " + line.text
		line.add_theme_font_size_override("font_size", 12)
		col.add_child(line)
	return col


## Ячейки доспеха и рук, под ними — пояс.
func _worn_column(inv: Inventory) -> VBoxContainer:
	var col := _column(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_heading("UI_EQ_WORN"))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	for slot in Inventory.SLOTS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var caption := Label.new()
		caption.text = TranslationServer.translate("UI_SLOT_" + slot.to_upper())
		caption.add_theme_font_size_override("font_size", 11)
		caption.add_theme_color_override("font_color", Color(0.7, 0.66, 0.58))
		cell.add_child(caption)
		var item_id := inv.slot_item(slot)
		cell.add_child(
			_cell(
				_item_name(item_id) if item_id != "" else "",
				SLOT_CELL,
				_is_selected(WHERE_SLOT, slot),
				_select.bind(WHERE_SLOT, slot)
			)
		)
		slots.add_child(cell)
	col.add_child(slots)
	col.add_child(
		_heading_text(
			CombatLogFormat.tr_fmt("UI_EQ_BELT", {"n": inv.belt.size(), "max": Inventory.BELT_SIZE})
		)
	)
	var belt := HBoxContainer.new()
	belt.add_theme_constant_override("separation", 6)
	for i in Inventory.BELT_SIZE:
		if i < inv.belt.size():
			var s := inv.belt[i]
			belt.add_child(
				_cell(
					_stack_text(s),
					BELT_CELL,
					_is_selected(WHERE_BELT, s.item),
					_select.bind(WHERE_BELT, s.item)
				)
			)
		else:
			belt.add_child(_cell("", BELT_CELL, false, Callable()))
	col.add_child(belt)
	return col


# --- Низ: мешок, выбранная вещь, кошелёк и нагрузка ------------------------------


func _bag_grid(inv: Inventory) -> VBoxContainer:
	var col := _column(0)
	col.add_child(_heading("UI_EQ_BAG"))
	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var cells := maxi(BAG_MIN_CELLS, ceili(inv.bag.size() / float(BAG_COLUMNS)) * BAG_COLUMNS)
	for i in cells:
		if i < inv.bag.size():
			var s := inv.bag[i]
			var b := _cell(
				_stack_text(s),
				BAG_CELL,
				_is_selected(WHERE_BAG, s.item),
				_select.bind(WHERE_BAG, s.item)
			)
			b.tooltip_text = _row_text(s)
			grid.add_child(b)
		else:
			grid.add_child(_cell("", BAG_CELL, false, Callable()))
	col.add_child(grid)
	return col


## Описание выбранной вещи и что с ней можно сделать.
func _details(inv: Inventory) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.09, 0.09, 0.1), CELL_BORDER, 1))
	panel.custom_minimum_size = Vector2(0, 70)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	box.add_child(label)
	match _sel_where:
		WHERE_BAG:
			label.text = _row_text(_stack_in(inv.bag, _sel_key))
			box.add_child(_bag_buttons(inv, _sel_key))
		WHERE_BELT:
			label.text = _row_text(_stack_in(inv.belt, _sel_key))
			var to_bag := _small("UI_EQ_TO_BAG", func() -> void: _apply(inv.from_belt(_sel_key)))
			box.add_child(_row_of([to_bag]))
		WHERE_SLOT:
			var item_id := inv.slot_item(_sel_key)
			label.text = _row_text(ItemStack.new(item_id, 1))
			var slot := _sel_key
			var off := _small("UI_EQ_UNEQUIP", func() -> void: _apply(inv.unequip(slot)))
			box.add_child(_row_of([off]))
		_:
			label.text = TranslationServer.translate("UI_EQ_PICK")
			label.modulate = Color(1, 1, 1, 0.55)
	return panel


func _footer(inv: Inventory) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var purse := Label.new()
	purse.text = CombatLogFormat.tr_fmt("UI_EQ_PURSE", {"money": money_text(inv.purse)})
	purse.add_theme_font_size_override("font_size", 13)
	row.add_child(purse)
	if _heroes.size() > 1 and inv.purse > 0:
		row.add_child(_money_menu(inv))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var hero := _party.build_hero(_db, _current)
	var weight := inv.weight(_db)
	var cap := ItemInfo.carry_limit(hero.abilities.score(Abilities.STR))
	var load_box := VBoxContainer.new()
	load_box.custom_minimum_size = Vector2(240, 0)
	var load_label := Label.new()
	load_label.text = CombatLogFormat.tr_fmt(
		"UI_EQ_LOAD", {"weight": weight_text(weight), "cap": weight_text(cap)}
	)
	if weight > cap:
		load_label.text += " " + TranslationServer.translate("UI_EQ_OVERLOAD")
		load_label.add_theme_color_override("font_color", UiStyle.HP_LOW)
	load_label.add_theme_font_size_override("font_size", 12)
	load_box.add_child(load_label)
	load_box.add_child(_load_bar(weight, cap))
	row.add_child(load_box)
	return row


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


# --- Выбор ячейки ----------------------------------------------------------------


func _select(where: String, key: String) -> void:
	_sel_where = where
	_sel_key = key
	if visible and _current != "":
		_rebuild()


func _is_selected(where: String, key: String) -> bool:
	return _sel_where == where and _sel_key == key


## Вещь переложили, отдали или сняли — выбор снимается.
func _drop_stale_selection(inv: Inventory) -> void:
	var gone := false
	match _sel_where:
		WHERE_BAG:
			gone = inv.bag_count(_sel_key) == 0
		WHERE_BELT:
			gone = inv.belt_count(_sel_key) == 0
		WHERE_SLOT:
			gone = inv.slot_item(_sel_key) == ""
	if gone:
		_sel_where = ""
		_sel_key = ""


static func _stack_in(stacks: Array[ItemStack], item_id: String) -> ItemStack:
	for s in stacks:
		if s.item == item_id:
			return s
	return ItemStack.new(item_id, 0)


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
	_sel_where = ""
	_sel_key = ""
	_rebuild()


func _on_reset() -> void:
	var fresh := Party.from_db(_db)
	_party.inventories = fresh.inventories
	_changed = true
	_rebuild()


func close() -> void:
	_on_close()


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


## Ячейка с вещью; пустая ([param text] == "") не нажимается.
func _cell(text: String, size: Vector2, selected: bool, on_click: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.clip_text = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 11)
	var border := UiStyle.ACTIVE if selected else CELL_BORDER
	var normal := UiStyle.box(CELL_BG, border, 2 if selected else 1, 4)
	normal.set_content_margin_all(3)
	var hover := UiStyle.box(CELL_BG.lightened(0.08), UiStyle.ACTIVE.darkened(0.25), 1, 4)
	hover.set_content_margin_all(3)
	var empty := UiStyle.box(Color(0.1, 0.1, 0.1, 0.8), Color(0.22, 0.21, 0.19), 1, 4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("disabled", empty)
	if text == "" or not on_click.is_valid():
		b.disabled = true
	else:
		b.pressed.connect(on_click)
	return b


## «Кольчуга · 55 фунт. · 5 гривен».
func _row_text(s: ItemStack) -> String:
	return (
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


static func _row_of(controls: Array[Control]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for c in controls:
		row.add_child(c)
	return row


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
