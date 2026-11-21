extends GutTest
## Предметы в бою (ADR-0024): оружие с пояса в руку при атаке, трата метательного
## и расходников, бесплатное действие с предметом, «достать из мешка» — действие.

var _db: RulesDb


func before_all() -> void:
	_db = CombatSim.rules()


## Ратник из данных против разбойника рядом.
func _fight(inventory: Dictionary) -> CombatState:
	var errors: Array[String] = []
	var data: Dictionary = _db.characters["ratnik"].duplicate(true)
	var hero := CombatantBuilder.from_character(_db, data, errors, Inventory.from_dict(inventory))
	assert_eq(errors, [] as Array[String])
	hero.team = "party"
	hero.column = Vector2i(1, 1)
	var foe := MiniCombat.unit("foe", "bandits", Vector2i(2, 1), 30, 5)
	return MiniCombat.make([hero, foe], ["ratnik", "foe"])


func test_attack_with_belt_weapon_draws_it() -> void:
	var s := _fight({"main_hand": "mech", "off_hand": "shchit", "belt": ["osinovy_kol"]})
	var hero := s.get_combatant("ratnik")
	MiniCombat.rolls(s, [15, 3])
	var events := MiniCombat.use(s, "ratnik", "osinovy_kol", "foe")
	var moved := MiniCombat.events_of(events, CombatEvent.ITEM_MOVED)
	assert_eq(moved.size(), 1)
	assert_eq(JsonRead.get_str(moved[0].data, "previous"), "mech")
	assert_eq(hero.inventory.main_hand, "osinovy_kol")
	assert_eq(hero.inventory.belt_count("mech"), 1, "sword went to the belt")
	assert_true(hero.inventory.in_hands("shchit"), "shield stays")


func test_thrown_weapon_is_spent_from_hand() -> void:
	var s := _fight({"main_hand": "mech", "belt": [{"item": "sulitsa", "count": 2}]})
	var hero := s.get_combatant("ratnik")
	# Метательное вплотную к врагу — с помехой: два d20, затем урон.
	MiniCombat.rolls(s, [15, 15, 3])
	MiniCombat.use(s, "ratnik", "sulitsa", "foe")
	assert_eq(hero.inventory.main_hand, "", "the javelin flew away")
	assert_eq(hero.inventory.belt_count("sulitsa"), 1)
	assert_eq(hero.item_count(hero.get_action("sulitsa")), 1)


func test_potion_is_spent_from_belt() -> void:
	var s := _fight({"main_hand": "mech", "belt": ["otvar"]})
	var hero := s.get_combatant("ratnik")
	hero.hp = 5
	MiniCombat.rolls(s, [2, 2])
	MiniCombat.use(s, "ratnik", "use_otvar", "ratnik")
	assert_eq(hero.hp, 11)
	assert_eq(hero.inventory.belt_count("otvar"), 0)
	assert_eq(
		UseActionCommand.new("ratnik", "use_otvar", "ratnik").validate(s),
		ActionResolver.ERR_BONUS_USED
	)
	s.bonus_used = false
	assert_eq(
		UseActionCommand.new("ratnik", "use_otvar", "ratnik").validate(s),
		ActionResolver.ERR_ITEM_NOT_READY
	)


func test_bag_items_need_fetching() -> void:
	var s := _fight({"main_hand": "mech", "bag": ["otvar", "osinovy_kol"]})
	var hero := s.get_combatant("ratnik")
	assert_eq(
		UseActionCommand.new("ratnik", "osinovy_kol", "foe").validate(s),
		ActionResolver.ERR_ITEM_NOT_READY
	)
	var fetch := ItemCommand.new("ratnik", "osinovy_kol", ItemCommand.OP_FETCH)
	assert_eq(fetch.validate(s), "")
	fetch.apply(s)
	assert_eq(s.actions_left, 0, "fetching costs the action")
	assert_eq(hero.inventory.belt_count("osinovy_kol"), 1)
	assert_eq(
		ItemCommand.new("ratnik", "otvar", ItemCommand.OP_FETCH).validate(s),
		ActionResolver.ERR_ACTION_USED
	)


func test_free_draw_and_stow_once_per_turn() -> void:
	var s := _fight({"main_hand": "mech", "off_hand": "shchit", "belt": ["osinovy_kol"]})
	var hero := s.get_combatant("ratnik")
	var draw := ItemCommand.new("ratnik", "osinovy_kol", ItemCommand.OP_DRAW)
	assert_eq(draw.validate(s), "")
	draw.apply(s)
	assert_eq(hero.inventory.main_hand, "osinovy_kol")
	assert_eq(
		ItemCommand.new("ratnik", "", ItemCommand.OP_STOW).validate(s), ItemCommand.ERR_FREE_USED
	)
	assert_eq(s.actions_left, 1, "free")


func test_two_handed_weapon_needs_free_off_hand() -> void:
	var errors: Array[String] = []
	var data: Dictionary = _db.characters["lovchiy"].duplicate(true)
	var inv := Inventory.from_dict(
		{"main_hand": "serebryany_nozh", "off_hand": "nozh", "belt": ["luk"]}
	)
	var hero := CombatantBuilder.from_character(_db, data, errors, inv)
	hero.team = "party"
	var foe := MiniCombat.unit("foe", "bandits", Vector2i(4, 4))
	var s := MiniCombat.make([hero, foe], ["lovchiy", "foe"])
	assert_eq(UseActionCommand.new("lovchiy", "luk", "foe").validate(s), Inventory.ERR_HANDS_BUSY)


func test_item_command_round_trip() -> void:
	var cmd := ItemCommand.new("a", "otvar", ItemCommand.OP_FETCH)
	var back := CombatCommand.from_dict(cmd.to_dict()) as ItemCommand
	assert_eq(back.item, "otvar")
	assert_eq(back.op, ItemCommand.OP_FETCH)
