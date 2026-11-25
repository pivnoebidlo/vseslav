class_name HeroScreen
extends PanelContainer
## Окно «Герой» (ADR-0043, макет — ADR-0035): вкладки героев; сверху — портрет, класс,
## путь, уровень, опыт и кнопка «Повысить уровень» с тем, что он даст; ниже —
## характеристики, спасброски, боевые числа и умения. Числа считает сборщик бойца,
## опыт и уровень — Party.

signal closed(changed: bool)

const CARD_BG := Color(0.16, 0.15, 0.13)
const CARD_BORDER := Color(0.36, 0.33, 0.27)
const DIM := Color(1, 1, 1, 0.55)

var _db: RulesDb
var _party: Party
var _heroes: Array[String] = []
var _current := ""
var _changed := false
## Идёт выбор для следующего уровня (вместо листа — панель выбора).
var _choosing := false

var _tabs := HBoxContainer.new()
var _body := VBoxContainer.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.12, 0.13), Color(0.45, 0.42, 0.35), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_SIDE_HERO")
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	header.add_child(_tabs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = TranslationServer.translate("UI_EQ_CLOSE")
	close.focus_mode = Control.FOCUS_NONE
	UiStyle.style_cost_button(close, ActionDef.COST_REACTION, false)
	close.pressed.connect(_on_close)
	header.add_child(close)
	_body.add_theme_constant_override("separation", 12)
	box.add_child(_body)
	visible = false


func open(db: RulesDb, party: Party, heroes: Array[String]) -> void:
	_db = db
	_party = party
	_heroes = heroes
	if not _heroes.has(_current):
		_current = _heroes[0] if not _heroes.is_empty() else ""
	_changed = false
	visible = true
	_rebuild()


## Tab — следующий герой.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or not key.pressed or _heroes.is_empty():
		return
	if key.keycode == KEY_TAB:
		_current = _heroes[(_heroes.find(_current) + 1) % _heroes.size()]
		_choosing = false
		_rebuild()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE or key.keycode == KEY_C:
		_on_close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for id in _heroes:
		var tab := Button.new()
		tab.text = TranslationServer.translate(_name_key(id))
		tab.focus_mode = Control.FOCUS_NONE
		if _party.can_level_up(_db, id):
			tab.text += " ▲"
		UiStyle.style_cost_button(tab, ActionDef.COST_REACTION, id == _current)
		tab.pressed.connect(_on_tab.bind(id))
		_tabs.add_child(tab)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _current == "":
		return
	var hero := _party.build_hero(_db, _current)
	if hero == null:
		return
	_body.add_child(_card(hero))
	if _choosing:
		var panel := LevelChoicePanel.new()
		panel.setup(_db, _party.character_data(_db, _current), hero.abilities, hero.level + 1)
		panel.chosen.connect(_on_choice)
		panel.cancelled.connect(
			func() -> void:
				_choosing = false
				_rebuild()
		)
		_body.add_child(panel)
		_recenter.call_deferred()
		return
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.add_child(_abilities(hero))
	left.add_child(_saves(hero))
	left.add_child(_combat(hero))
	columns.add_child(left)
	columns.add_child(_features(hero))
	_body.add_child(columns)
	_recenter.call_deferred()


func _recenter() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


# --- Карточка: кто это, опыт, повышение уровня -----------------------------------


func _card(hero: Combatant) -> PanelContainer:
	var card := _framed()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(84, 96)
	portrait.add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.22, 0.2, 0.17), UiStyle.ACTIVE.darkened(0.35), 1, 6)
	)
	var letter := Label.new()
	letter.text = TranslationServer.translate(hero.name_key).left(1)
	letter.add_theme_font_size_override("font_size", 40)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(letter)
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = TranslationServer.translate(hero.name_key)
	name_label.add_theme_font_size_override("font_size", 24)
	info.add_child(name_label)
	info.add_child(_dim(_identity_line(hero), 14))
	var xp := _party.state_of(_current).xp
	var next_xp := Progression.xp_for(_db, hero.level + 1)
	var at_cap := hero.level >= Progression.max_level(_db)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(420, 8)
	var from_xp := Progression.xp_for(_db, hero.level)
	bar.max_value = maxi(next_xp - from_xp, 1)
	bar.value = bar.max_value if at_cap else clampi(xp - from_xp, 0, next_xp - from_xp)
	bar.add_theme_stylebox_override(
		"background", UiStyle.box(Color(0, 0, 0, 0.5), Color.TRANSPARENT, 0, 3)
	)
	bar.add_theme_stylebox_override(
		"fill", UiStyle.box(UiStyle.ACTIVE.darkened(0.15), Color.TRANSPARENT, 0, 3)
	)
	info.add_child(bar)
	var xp_text := (
		_fmt("UI_HERO_XP_MAX", {"xp": xp})
		if at_cap
		else _fmt("UI_HERO_XP", {"xp": xp, "next": next_xp, "level": hero.level + 1})
	)
	info.add_child(_dim(xp_text, 13))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	var up := Button.new()
	up.text = TranslationServer.translate("UI_HERO_LEVEL_UP")
	up.focus_mode = Control.FOCUS_NONE
	up.custom_minimum_size = Vector2(220, 40)
	up.disabled = not _party.can_level_up(_db, _current)
	UiStyle.style_cost_button(up, ActionDef.COST_ACTION, false)
	up.pressed.connect(_on_level_up)
	side.add_child(up)
	if not at_cap:
		var gain := _dim(_gain_text(hero), 12)
		gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gain.custom_minimum_size = Vector2(220, 0)
		side.add_child(gain)
	return card


## «Ратник · путь Дружинника · 3 уровень · варяг».
func _identity_line(hero: Combatant) -> String:
	var data: Dictionary = _db.characters[_current]
	var cls: Dictionary = _db.classes.get(JsonRead.get_str(data, "class"), {})
	var origin: Dictionary = _db.origins.get(JsonRead.get_str(data, "origin"), {})
	var values := {
		"class": TranslationServer.translate(JsonRead.get_str(cls, "name_key")),
		"level": hero.level,
		"origin": TranslationServer.translate(JsonRead.get_str(origin, "name_key")),
	}
	var path := _path(cls, JsonRead.get_str(data, "path"))
	if path.is_empty() or hero.level < JsonRead.get_int(path, "level", 3):
		return _fmt("UI_HERO_LINE", values)
	values["path"] = TranslationServer.translate(JsonRead.get_str(path, "name_key"))
	return _fmt("UI_HERO_LINE_PATH", values)


## Что даст следующий уровень: хиты и новые умения из данных класса и пути.
func _gain_text(hero: Combatant) -> String:
	var next := hero.level + 1
	var data := _party.character_data(_db, _current)
	data["level"] = next
	var errors: Array[String] = []
	var after := CombatantBuilder.from_character(_db, data, errors)
	var hp := after.max_hp - hero.max_hp if after != null else 0
	var names: Array[String] = []
	var cls: Dictionary = _db.classes.get(JsonRead.get_str(data, "class"), {})
	_feature_names(JsonRead.get_dict(JsonRead.get_dict(cls, "levels"), str(next)), names)
	var path := _path(cls, JsonRead.get_str(data, "path"))
	if JsonRead.get_int(path, "level", 3) == next:
		_feature_names(path, names)
	var counts := LevelChoice.spells_to_pick(_db, _party.character_data(_db, _current), next)
	if counts.x + counts.y > 0:
		names.append(_fmt("UI_HERO_GAIN_SPELLS", {"n": counts.x + counts.y}))
	if after != null and after.proficiency > hero.proficiency:
		names.append(_fmt("UI_HERO_GAIN_PROF", {"bonus": "+%d" % after.proficiency}))
	var text := _fmt("UI_HERO_GAIN", {"level": next, "hp": hp})
	if not names.is_empty():
		text += "\n" + ", ".join(names)
	return text


func _feature_names(source: Dictionary, into: Array[String]) -> void:
	for id in JsonRead.get_str_array(source, "actions"):
		if _db.actions.has(id):
			into.append(
				TranslationServer.translate(JsonRead.get_str(_db.actions[id], "name_key", id))
			)
	for raw: Variant in JsonRead.get_array(source, "traits"):
		if typeof(raw) == TYPE_DICTIONARY:
			var t: Dictionary = raw
			if JsonRead.get_str(t, "name_key") != "":
				into.append(TranslationServer.translate(JsonRead.get_str(t, "name_key")))


# --- Колонка слева: характеристики, спасброски, бой ------------------------------


func _abilities(hero: Combatant) -> PanelContainer:
	var card := _framed()
	var box := _section(card, "UI_HERO_ABILITIES")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var cls: Dictionary = _db.classes.get(_class_id(), {})
	var main := JsonRead.get_str(cls, "spell_ability")
	for id in Abilities.ALL:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(86, 0)
		var border := UiStyle.ACTIVE.darkened(0.2) if id == main else CARD_BORDER
		cell.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.1, 0.1), border, 1, 5))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		cell.add_child(col)
		var short := _dim(TranslationServer.translate("UI_AB_" + id.to_upper()), 11)
		short.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(short)
		var mod := Label.new()
		mod.text = _signed(hero.ability_mod(id))
		mod.add_theme_font_size_override("font_size", 22)
		mod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(mod)
		var score := _dim(str(hero.abilities.score(id)), 12)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(score)
		grid.add_child(cell)
	return card


func _saves(hero: Combatant) -> PanelContainer:
	var card := _framed()
	var box := _section(card, "UI_HERO_SAVES")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	box.add_child(grid)
	for id in Abilities.ALL:
		var mark := "●" if hero.save_proficiencies.has(id) else "○"
		var name_text := TranslationServer.translate("UI_ABN_" + id.to_upper())
		var line := _row("%s %s" % [mark, name_text], _signed(hero.save_modifier(id)), 160)
		if not hero.save_proficiencies.has(id):
			line.modulate = Color(1, 1, 1, 0.65)
		grid.add_child(line)
	return card


func _combat(hero: Combatant) -> PanelContainer:
	var card := _framed()
	var box := _section(card, "UI_HERO_COMBAT")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	box.add_child(grid)
	var dice := Rest.hit_dice_left(_db, _party, _current)
	var die := Rest.hit_die_size(_db, _current)
	var pairs: Array[Array] = [
		["UI_HERO_AC", str(hero.armor_class)],
		["UI_HERO_HP", "%d / %d" % [hero.hp, hero.max_hp]],
		["UI_HERO_SPEED", _fmt("UI_HERO_SPEED_VALUE", {"n": hero.speed})],
		["UI_HERO_INIT", _signed(hero.initiative_bonus)],
		["UI_HERO_PROF", _signed(hero.proficiency)],
		[
			"UI_HERO_HIT_DICE",
			_fmt("UI_HERO_HIT_DICE_VALUE", {"left": dice, "n": hero.level, "die": die})
		],
	]
	for pair in pairs:
		grid.add_child(_row(TranslationServer.translate(str(pair[0])), str(pair[1]), 160))
	return card


# --- Умения ----------------------------------------------------------------------


## Умения класса и пути (с ценой — цветом полоски), черты и заговоры.
func _features(hero: Combatant) -> PanelContainer:
	var card := _framed()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := _section(card, "UI_HERO_FEATURES")
	box.custom_minimum_size = Vector2(330, 0)
	var data := _party.character_data(_db, _current)
	var cls: Dictionary = _db.classes.get(JsonRead.get_str(data, "class"), {})
	var sources: Array[Dictionary] = []
	var levels := JsonRead.get_dict(cls, "levels")
	for lvl in range(1, hero.level + 1):
		sources.append(JsonRead.get_dict(levels, str(lvl)))
	var path := _path(cls, JsonRead.get_str(data, "path"))
	if not path.is_empty() and hero.level >= JsonRead.get_int(path, "level", 3):
		sources.append(path)
	var seen: Array[String] = []
	for source in sources:
		for id in JsonRead.get_str_array(source, "actions"):
			var action := hero.get_action(id)
			if action != null and not seen.has(id):
				seen.append(id)
				box.add_child(_feature(action.name_key, action.cost))
		for raw: Variant in JsonRead.get_array(source, "traits"):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var t: Dictionary = raw
			var key := JsonRead.get_str(t, "name_key")
			if key != "" and not seen.has(key):
				seen.append(key)
				box.add_child(_feature(key, ""))
	var spells := JsonRead.get_str_array(data, "spells")
	if not spells.is_empty():
		box.add_child(_dim(TranslationServer.translate("UI_HERO_SPELLS"), 12))
		for id in spells:
			var action := hero.get_action(id)
			if action != null:
				box.add_child(_feature(action.name_key, action.cost))
	if box.get_child_count() == 1:
		box.add_child(_dim(TranslationServer.translate("UI_HERO_NONE"), 13))
	return card


## Строка умения: цветная полоска цены (пусто — постоянная черта) и название.
func _feature(name_key: String, cost: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(4, 22)
	strip.color = UiStyle.cost_color(cost) if cost != "" else CARD_BORDER
	row.add_child(strip)
	var label := Label.new()
	label.text = TranslationServer.translate(name_key)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	return row


# --- Мелочи ----------------------------------------------------------------------


func _framed() -> PanelContainer:
	var p := PanelContainer.new()
	var style := UiStyle.box(CARD_BG, CARD_BORDER, 1, 6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", style)
	return p


func _section(card: PanelContainer, title_key: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var title := Label.new()
	title.text = TranslationServer.translate(title_key)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UiStyle.ACTIVE.darkened(0.1))
	box.add_child(title)
	return box


func _row(left: String, right: String, width: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(width, 0)
	var a := Label.new()
	a.text = left
	a.add_theme_font_size_override("font_size", 13)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(a)
	var b := Label.new()
	b.text = right
	b.add_theme_font_size_override("font_size", 14)
	row.add_child(b)
	return row


func _dim(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", DIM)
	return l


func _path(cls: Dictionary, path_id: String) -> Dictionary:
	for raw: Variant in JsonRead.get_array(cls, "paths"):
		if typeof(raw) == TYPE_DICTIONARY:
			var p: Dictionary = raw
			if JsonRead.get_str(p, "id") == path_id:
				return p
	return {}


func _class_id() -> String:
	var data: Dictionary = _db.characters.get(_current, {})
	return JsonRead.get_str(data, "class")


func _name_key(id: String) -> String:
	var data: Dictionary = _db.characters.get(id, {})
	return JsonRead.get_str(data, "name_key", id)


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else "−%d" % absi(n)


static func _fmt(key: String, values: Dictionary) -> String:
	return TranslationServer.translate(key).format(values)


func _on_tab(id: String) -> void:
	_current = id
	_choosing = false
	_rebuild()


func _on_level_up() -> void:
	if _party.choice_needed(_db, _current):
		_choosing = true
		_rebuild()
	elif _party.level_up(_db, _current):
		_changed = true
		_rebuild()


func _on_choice(pick: Dictionary) -> void:
	if _party.level_up(_db, _current, pick):
		_changed = true
	_choosing = false
	_rebuild()


func close() -> void:
	_on_close()


func _on_close() -> void:
	visible = false
	closed.emit(_changed)
