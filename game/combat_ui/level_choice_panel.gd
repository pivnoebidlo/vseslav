class_name LevelChoicePanel
extends PanelContainer
## Выбор при повышении уровня в окне «Герой» (ADR-0044): +2 к одной характеристике,
## +1 к двум или черта из доступных герою. «Принять» горит, только когда выбор
## годится (LevelChoice.problem); результат — [signal chosen] с выбором для Party.level_up.

signal chosen(pick: Dictionary)
signal cancelled

const MODE_PLUS_TWO := "plus_two"
const MODE_PLUS_ONE := "plus_one"

var _db: RulesDb
var _data: Dictionary
var _abilities: Abilities
var _mode := MODE_PLUS_TWO
var _feat := ""
var _first := OptionButton.new()
var _second := OptionButton.new()
var _third := OptionButton.new()
var _accept := Button.new()
var _group := ButtonGroup.new()
## Нужна ли черта/характеристики на этом уровне; сколько заговоров (x) и заклинаний (y).
var _feat_needed := false
var _counts := Vector2i.ZERO
var _spells: Array[String] = []
var _spell_hint := Label.new()


## [param data] — данные персонажа с его выборами, [param abilities] — нынешние значения.
func setup(db: RulesDb, data: Dictionary, abilities: Abilities, level: int) -> void:
	_db = db
	_data = data
	_abilities = abilities
	var style := UiStyle.box(Color(0.16, 0.15, 0.13), UiStyle.ACTIVE.darkened(0.3), 1, 6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(760, 0)
	add_child(box)
	_feat_needed = LevelChoice.feat_needed(db, data, level)
	_counts = LevelChoice.spells_to_pick(db, data, level)
	var title := Label.new()
	var title_key := "UI_LEVEL_CHOICE" if _feat_needed else "UI_LEVEL_CHOICE_SPELLS"
	title.text = TranslationServer.translate(title_key).format({"level": level})
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	if _feat_needed:
		_feat_section(box)
	if _counts.x + _counts.y > 0:
		_spell_section(box, level)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = TranslationServer.translate("UI_ED_CANCEL")
	cancel.focus_mode = Control.FOCUS_NONE
	UiStyle.style_cost_button(cancel, ActionDef.COST_REACTION, false)
	cancel.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel)
	_accept.text = TranslationServer.translate("UI_LEVEL_ACCEPT")
	_accept.focus_mode = Control.FOCUS_NONE
	UiStyle.style_cost_button(_accept, ActionDef.COST_ACTION, false)
	_accept.pressed.connect(func() -> void: chosen.emit(pick()))
	buttons.add_child(_accept)
	_refresh()


func _feat_section(box: VBoxContainer) -> void:
	var plus_two := _radio(box, "UI_LEVEL_PLUS_TWO", MODE_PLUS_TWO, "")
	plus_two.add_child(_abilities_picker(_first))
	var plus_one := _radio(box, "UI_LEVEL_PLUS_ONE", MODE_PLUS_ONE, "")
	plus_one.add_child(_abilities_picker(_second))
	plus_one.add_child(_abilities_picker(_third))
	_third.select(1)
	var feats := LevelChoice.feats_for(_db, _data)
	if not feats.is_empty():
		var head := Label.new()
		head.text = TranslationServer.translate("UI_LEVEL_FEATS")
		head.add_theme_color_override("font_color", UiStyle.ACTIVE.darkened(0.1))
		box.add_child(head)
	for id in feats:
		var feat: Dictionary = _db.feats[id]
		var row := _radio(box, JsonRead.get_str(feat, "name_key"), "", id)
		var desc := Label.new()
		desc.text = TranslationServer.translate(JsonRead.get_str(feat, "desc_key"))
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc)


## Заговоры и заклинания на выбор: флажки; сколько нужно — в подсказке.
func _spell_section(box: VBoxContainer, level: int) -> void:
	var head := Label.new()
	head.text = TranslationServer.translate("UI_LEVEL_SPELLS")
	head.add_theme_color_override("font_color", UiStyle.ACTIVE.darkened(0.1))
	box.add_child(head)
	_spell_hint.add_theme_font_size_override("font_size", 12)
	box.add_child(_spell_hint)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	var options: Array[String] = []
	if _counts.x > 0:
		options.append_array(LevelChoice.spell_options(_db, _data, level, true))
	if _counts.y > 0:
		options.append_array(LevelChoice.spell_options(_db, _data, level, false))
	for id in options:
		var raw: Dictionary = _db.actions[id]
		var check := CheckBox.new()
		var circle := JsonRead.get_int(raw, "spell_level")
		var name := TranslationServer.translate(JsonRead.get_str(raw, "name_key", id))
		check.text = (
			TranslationServer.translate("UI_LEVEL_CANTRIP").format({"name": name})
			if circle == 0
			else TranslationServer.translate("UI_LEVEL_CIRCLE").format({"name": name, "n": circle})
		)
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(
			func(on: bool) -> void:
				if on and not _spells.has(id):
					_spells.append(id)
				elif not on:
					_spells.erase(id)
				_refresh()
		)
		grid.add_child(check)


## Выбор в виде, который понимает Party.level_up.
func pick() -> Dictionary:
	var out := _feat_pick() if _feat_needed else {}
	if not _spells.is_empty():
		out[LevelChoice.SPELLS] = _spells.duplicate()
	return out


func _feat_pick() -> Dictionary:
	if _feat != "":
		return {LevelChoice.FEAT: _feat}
	if _mode == MODE_PLUS_TWO:
		return {LevelChoice.ASI: {_ability(_first): 2}}
	var a := _ability(_second)
	var b := _ability(_third)
	if a == b:
		return {LevelChoice.ASI: {a: 2}}
	return {LevelChoice.ASI: {a: 1, b: 1}}


func _radio(box: VBoxContainer, label_key: String, mode: String, feat: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var check := CheckBox.new()
	check.button_group = _group
	check.text = TranslationServer.translate(label_key)
	check.focus_mode = Control.FOCUS_NONE
	check.custom_minimum_size = Vector2(250, 0)
	check.button_pressed = mode == MODE_PLUS_TWO
	check.toggled.connect(
		func(on: bool) -> void:
			if on:
				_mode = mode
				_feat = feat
				_refresh()
	)
	row.add_child(check)
	box.add_child(row)
	return row


func _abilities_picker(option: OptionButton) -> OptionButton:
	for id in Abilities.ALL:
		option.add_item(
			"%s %d" % [TranslationServer.translate("UI_ABN_" + id.to_upper()), _abilities.score(id)]
		)
	option.focus_mode = Control.FOCUS_NONE
	option.item_selected.connect(func(_i: int) -> void: _refresh())
	return option


func _ability(option: OptionButton) -> String:
	return Abilities.ALL[clampi(option.selected, 0, Abilities.ALL.size() - 1)]


## «Принять» — только для годного выбора (например, не выше 20).
func _refresh() -> void:
	_accept.disabled = LevelChoice.problem(_db, _data, pick(), _abilities) != ""
	_spell_hint.text = TranslationServer.translate("UI_LEVEL_SPELLS_HINT").format(
		{"cantrips": _counts.x, "spells": _counts.y, "chosen": _spells.size()}
	)
