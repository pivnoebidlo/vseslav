class_name RestScreen
extends PanelContainer
## Отдых между боями (ADR-0027): короткий — кости хитов по одной и восстановление
## зарядов в конце; длинный — еда, полные хиты и кости, все заряды.

signal closed(changed: bool)

var _db: RulesDb
var _party: Party
var _heroes: Array[String] = []
var _rng: Rng
var _changed := false

var _short_list := VBoxContainer.new()
var _food := Label.new()
var _log := Label.new()


func _init() -> void:
	add_theme_stylebox_override(
		"panel", UiStyle.box(Color(0.12, 0.13, 0.15), Color(0.45, 0.5, 0.6), 1, 8)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(600, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = TranslationServer.translate("UI_REST")
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("UI_EQ_CLOSE", ActionDef.COST_REACTION, _on_close))

	box.add_child(_heading("UI_REST_SHORT"))
	box.add_child(_hint("UI_REST_SHORT_HINT"))
	_short_list.add_theme_constant_override("separation", 4)
	box.add_child(_short_list)
	var finish := _button("UI_REST_SHORT_FINISH", ActionDef.COST_BONUS, _on_finish_short)
	finish.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(finish)
	box.add_child(HSeparator.new())

	box.add_child(_heading("UI_REST_LONG"))
	box.add_child(_hint("UI_REST_LONG_HINT"))
	_food.add_theme_font_size_override("font_size", 13)
	box.add_child(_food)
	var night := _button("UI_REST_LONG_DO", ActionDef.COST_ACTION, _on_long)
	night.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(night)
	box.add_child(HSeparator.new())
	_log.add_theme_font_size_override("font_size", 13)
	_log.add_theme_color_override("font_color", UiStyle.HP_GOOD)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_log)
	visible = false


func open(db: RulesDb, party: Party, heroes: Array[String], rng: Rng) -> void:
	_db = db
	_party = party
	_heroes = heroes
	_rng = rng
	_changed = false
	_log.text = ""
	visible = true
	_rebuild()


func _rebuild() -> void:
	for child in _short_list.get_children():
		_short_list.remove_child(child)
		child.queue_free()
	var food := 0
	for id in _heroes:
		var hero := _party.build_hero(_db, id)
		var state := _party.state_of(id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		if state.dead:
			label.text = CombatLogFormat.tr_fmt("UI_REST_DEAD", {"name": _name(id)})
			label.modulate = Color(1, 1, 1, 0.5)
		else:
			label.text = (
				CombatLogFormat
				. tr_fmt(
					"UI_REST_HERO",
					{
						"name": _name(id),
						"hp": hero.hp,
						"max": hero.max_hp,
						"dice": Rest.hit_dice_left(_db, _party, id),
						"level": hero.level,
						"die": Rest.hit_die_size(_db, id),
					}
				)
			)
		row.add_child(label)
		var roll := _button("UI_REST_ROLL", ActionDef.COST_FREE, _on_roll.bind(id))
		roll.disabled = state.dead
		row.add_child(roll)
		_short_list.add_child(row)
		for s in _party.inventories[id].bag:
			if _db.items.has(s.item):
				var item: Dictionary = _db.items[s.item]
				if JsonRead.get_bool(item, "food"):
					food += s.count
	_food.text = CombatLogFormat.tr_fmt("UI_REST_FOOD", {"food": food, "heroes": _alive()})


func _on_roll(id: String) -> void:
	var result := Rest.spend_hit_die(_db, _party, id, _rng)
	if result.error != "":
		_log.text = TranslationServer.translate(result.error)
	else:
		_changed = true
		_log.text = CombatLogFormat.tr_fmt(
			"LOG_REST_HIT_DIE",
			{
				"name": _name(id),
				"die": Rest.hit_die_size(_db, id),
				"roll": result.roll,
				"con": CombatLogFormat.signed(result.con),
				"healed": result.healed
			}
		)
	_rebuild()


func _on_finish_short() -> void:
	Rest.finish_short(_db, _party)
	_changed = true
	_log.text = TranslationServer.translate("LOG_REST_SHORT_DONE")
	_rebuild()


func _on_long() -> void:
	var hungry := Rest.long_rest(_db, _party)
	_changed = true
	if hungry.is_empty():
		_log.text = TranslationServer.translate("LOG_REST_LONG_DONE")
	else:
		var names: PackedStringArray = []
		for id in hungry:
			names.append(_name(id))
		_log.text = CombatLogFormat.tr_fmt("LOG_REST_LONG_HUNGRY", {"names": ", ".join(names)})
	_rebuild()


func _on_close() -> void:
	visible = false
	closed.emit(_changed)


func _alive() -> int:
	var n := 0
	for id in _heroes:
		if not _party.state_of(id).dead:
			n += 1
	return n


func _name(id: String) -> String:
	if not _db.characters.has(id):
		return id
	var data: Dictionary = _db.characters[id]
	return TranslationServer.translate(JsonRead.get_str(data, "name_key", id))


func _heading(key: String) -> Label:
	var label := Label.new()
	label.text = TranslationServer.translate(key)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiStyle.ACTIVE)
	return label


func _hint(key: String) -> Label:
	var label := Label.new()
	label.text = TranslationServer.translate(key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return label


func _button(key: String, cost: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = TranslationServer.translate(key)
	b.add_theme_font_size_override("font_size", 13)
	UiStyle.style_cost_button(b, cost, false)
	b.pressed.connect(handler)
	return b
