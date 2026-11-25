class_name ExplorationUi
extends RefCounted
## Интерфейс сцены исследования (ADR-0035, ADR-0042): колонка окон, портреты, меню,
## окна партии, диалог, события. Вынесено из Exploration, чтобы сцена не разрасталась;
## работает с её полями напрямую.


## Окна из колонки слева и по клавишам: вещи, отдых — только вне боя
## и разговора; журнал — всегда, кроме разговора; меню — всегда.
## Торг — не здесь: он открывается у купца из разговора (ADR-0049).
static func open_window(x: Exploration, id: String) -> void:
	if id == "menu":
		toggle_menu(x)
		return
	if x._dialog.is_open() or x._screens.is_open():
		return
	if id == "journal":
		x._journal.toggle(x._content.quests, Exploration.flags)
		return
	if x._in_combat():
		return
	x._path_preview.clear()
	match id:
		"hero":
			x._screens.open_hero_for(x._group.ids)
		"items":
			x._screens.open_equipment_for(x._group.ids)
		"rest":
			x._screens.open_rest_for(x._group.ids)


## Кнопка «Торг» в разговоре (ADR-0049): экран торга с этим купцом; разговор
## прячется до конца торга.
static func trade_with(x: Exploration, merchant_id: String) -> void:
	x._dialog.visible = false
	x._screens.open_trade_for(x._group.ids, "", merchant_id)


## Экран торга закрыли — вернуть спрятанный разговор, если он не кончился.
static func on_trade_closed(x: Exploration) -> void:
	if x._runner != null and not x._runner.ended():
		x._dialog.visible = true


static func toggle_menu(x: Exploration) -> void:
	if x._menu.is_open():
		x._menu.close()
		return
	var can_save := not x._in_combat() or x._session.can_save()
	x._menu.open(can_save and x._area != null, SaveStore.has_any())


static func apply_options(x: Exploration) -> void:
	x._session.set_log_visible(GameSettings.show_combat_log)
	if not x._in_combat() and x._area != null:
		x._area_view.set_grid_visible(GameSettings.show_grid)


## Бой: окна партии гаснут, портреты показывают хиты бойцов.
static func set_combat_ui(x: Exploration, on: bool) -> void:
	for id: String in ["hero", "items", "rest"]:
		x._side.set_item_enabled(id, not on)
	x._refresh_bar()


static func setup(x: Exploration) -> void:
	var layer := CanvasLayer.new()
	x.add_child(layer)
	# Слева сверху — название области и подсказка, под ними — колонка кнопок окон.
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(column)
	var panel := PanelContainer.new()
	UiStyle.panel(panel)
	column.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	x._title.add_theme_font_size_override("font_size", 20)
	box.add_child(x._title)
	x._hint.text = x.tr("UI_EXPLORE_HINT")
	x._hint.modulate = Color(1, 1, 1, 0.7)
	x._hint.add_theme_font_size_override("font_size", 12)
	x._hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	x._hint.custom_minimum_size = Vector2(300, 0)
	box.add_child(x._hint)
	x._side.add_item("hero", "C", "UI_SIDE_HERO")
	x._side.add_item("items", "I", "UI_SIDE_ITEMS")
	x._side.add_item("journal", "J", "UI_SIDE_JOURNAL")
	x._side.add_item("rest", "R", "UI_REST")
	x._side.add_item("menu", "Esc", "UI_SIDE_MENU")
	x._side.chosen.connect(func(id: String) -> void: open_window(x, id))
	x._side.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(x._side)
	layer.add_child(x._party_bar)
	x._party_bar.hero_selected.connect(x._select)
	x._party_bar.chain_toggled.connect(x._toggle_chain)
	x._session.setup(layer, x._board, x._world)
	x._session.show_ui(false)
	x._session.status_changed.connect(x._on_combat_status)
	x._session.turn_started.connect(func(id: String) -> void: x._combat_focus = id)
	x._session.ended.connect(x._on_combat_ended)
	x._screens.setup(x._content.rules, x._content.merchants_data())
	x._screens.dry_run = SaveStore.disabled
	# Вещи, отдых, уровень — портреты (хиты) пересчитываются.
	x._screens.changed.connect(x._refresh_bar)
	x._screens.xp_gained.connect(
		func(amount: int) -> void: x._notify(x.tr("LOG_COMBAT_XP").format({"amount": amount}))
	)
	layer.add_child(x._screens)
	layer.add_child(x._dialog)
	layer.add_child(x._game_over)
	x._game_over.load_pressed.connect(x._load_latest)
	x._game_over.menu_pressed.connect(
		func() -> void: x.get_tree().change_scene_to_file(MainMenu.SCENE)
	)
	layer.add_child(x._dice)
	x._journal = JournalPanel.new()
	layer.add_child(x._journal)
	x._menu.setup()
	layer.add_child(x._menu)
	x._menu.save_pressed.connect(x._quick_save)
	x._menu.load_pressed.connect(x._load_latest)
	x._menu.quit_pressed.connect(func() -> void: x.get_tree().change_scene_to_file(MainMenu.SCENE))
	x._menu.options_changed.connect(apply_options.bind(x))
	x._dialog.quests_changed.connect(x._quests_updated)
	x._dialog.setup(x._dice, Exploration.rng)
	x._dialog.finished.connect(x._on_dialog_finished)
	x._dialog.trade_pressed.connect(func(m: String) -> void: trade_with(x, m))
	x._screens.trade_closed.connect(func() -> void: on_trade_closed(x))
	x._events.setup()
	layer.add_child(x._events)
	x._events.notice.connect(x._notify)
	x._events.finished.connect(x._on_events_finished)
	x._events.dialog_requested.connect(
		func(dialog_id: String, speaker: String) -> void:
			x._talk(dialog_id, x.tr(speaker) if speaker != "" else speaker_of(x, dialog_id))
	)
	x._events.combat_requested.connect(
		func(id: String) -> void:
			var e := x._area.get_encounter(id)
			if e != null and not x._in_combat():
				x._start_combat(e)
	)
	x._events.teleport_requested.connect(x._teleport)
	x._events.item_name = func(id: String) -> String: return x._item_name(id)
	x._events.hero_name = func(id: String) -> String: return x._name_of(id)


## Имя говорящего для разговора из события: житель области с этим диалогом.
static func speaker_of(x: Exploration, dialog_id: String) -> String:
	for npc in x._area.npcs:
		if npc.dialog == dialog_id:
			return x.tr(npc.name_key)
	return ""
