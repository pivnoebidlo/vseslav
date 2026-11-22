extends GutTest
## События v1 (ADR-0042): действия с вещами, деньгами и составом отряда, запросы
## к игре, события области (вход в область и в зону, однократность), жители по условию.

var _db: RulesDb


func before_all() -> void:
	_db = RulesDb.load_dir(CombatSim.RULES_DIR)


func _ctx() -> EventContext:
	var party := Party.from_db(_db)
	var start: Array[String] = ["ratnik", "lovchiy", "volkhv"]
	party.set_members(start)
	var ctx := EventContext.new(WorldFlags.new(), party, _db)
	ctx.receiver = "lovchiy"
	return ctx


func test_items_and_money_go_to_the_receiver_and_back() -> void:
	var ctx := _ctx()
	var inv := ctx.party.inventories["lovchiy"]
	var purse := inv.purse
	(
		EventActions
		. run(
			[
				{"action": "give_item", "item": "otvar", "count": 2},
				{"action": "give_money", "kuny": 30},
			],
			ctx
		)
	)
	assert_eq(inv.bag_count("otvar"), 2)
	assert_eq(inv.purse, purse + 30)
	var notices := ctx.take_requests()
	assert_eq(notices.size(), 2)
	assert_eq(JsonRead.get_str(notices[0], "notice"), EventActions.NOTICE_ITEM)
	EventActions.run([{"action": "take_item", "item": "otvar", "count": 5}], ctx)
	assert_eq(inv.count_of("otvar"), 0, "takes from everyone, as much as there is")
	var all_money := 0
	for id in ctx.party.members:
		all_money += ctx.party.inventories[id].purse
	EventActions.run([{"action": "give_money", "kuny": -100000}], ctx)
	var left := 0
	for id in ctx.party.members:
		left += ctx.party.inventories[id].purse
	assert_eq(left, 0)
	var last: Dictionary = ctx.take_requests()[-1]
	assert_eq(JsonRead.get_int(last, "kuny"), -all_money, "reports what was actually taken")


func test_join_and_leave_the_party() -> void:
	var ctx := _ctx()
	EventActions.run([{"action": "join_party", "character": "tat"}], ctx)
	assert_true(ctx.party.members.has("tat"))
	assert_eq(str(ctx.flags.get_flag("party.tat")), "true")
	EventActions.run([{"action": "leave_party", "character": "ratnik"}], ctx)
	assert_false(ctx.party.members.has("ratnik"))
	assert_eq(str(ctx.flags.get_flag("party.ratnik")), "false")
	var restored := Party.from_dict(ctx.party.to_dict(), _db)
	assert_eq(restored.members, ctx.party.members, "members survive saving")
	var old := Party.from_dict({"format": 2, "heroes": {}}, _db)
	assert_eq(old.members.size(), _db.characters.size(), "old saves: everyone")


func test_party_limits() -> void:
	var party := Party.from_db(_db)
	assert_eq(party.members.size(), 6)
	assert_false(party.join("tat"), "already in")
	var one: Array[String] = ["volkhv"]
	party.set_members(one)
	assert_false(party.leave("volkhv"), "the last one stays")


func test_scene_actions_become_requests_in_order() -> void:
	var ctx := _ctx()
	(
		EventActions
		. run(
			[
				{"action": "message", "text": "MSG_X"},
				{"action": "set_flag", "flag": "seen"},
				{"action": "start_dialog", "dialog": "starosta"},
				{"action": "teleport", "area": "izba", "spawn": "door"},
			],
			ctx
		)
	)
	var kinds: Array[String] = []
	for r in ctx.take_requests():
		kinds.append(JsonRead.get_str(r, "action"))
	assert_eq(kinds, ["message", "start_dialog", "teleport"] as Array[String])
	assert_eq(str(ctx.flags.get_flag("seen")), "true")


func _area() -> AreaMap:
	return (
		AreaMap
		. from_dict(
			"pole",
			{
				"title_key": "T",
				"map": ["......", "......", "......"],
				"spawns": {"start": [0, 0]},
				"npcs":
				[
					{"id": "ded", "name_key": "D", "at": [1, 1]},
					{
						"id": "tat",
						"name_key": "T",
						"at": [2, 1],
						"if": [{"flag": "party.tat", "eq": false}]
					}
				],
				"events":
				[
					{
						"id": "hello",
						"on": "enter_area",
						"then": [{"action": "message", "text": "M"}]
					},
					{
						"id": "trap",
						"on": "enter_zone",
						"zone": [4, 0, 2, 3],
						"if": [{"flag": "warned", "eq": true}],
						"then": [{"action": "give_money", "kuny": 5}]
					},
					{
						"id": "spring",
						"on": "enter_zone",
						"zone": [4, 0, 2, 3],
						"once": false,
						"then": [{"action": "set_flag", "flag": "drank"}]
					}
				],
			}
		)
	)


func test_area_events_fire_once_by_zone_and_condition() -> void:
	var area := _area()
	var ctx := _ctx()
	var on_enter := AreaEvents.due(area, "enter_area", Vector2i.ZERO, ctx.flags)
	assert_eq(on_enter.size(), 1)
	AreaEvents.fire(area, on_enter[0], ctx)
	assert_true(AreaEvents.due(area, "enter_area", Vector2i.ZERO, ctx.flags).is_empty(), "once")
	assert_eq(AreaEvents.due(area, "enter_zone", Vector2i(1, 1), ctx.flags).size(), 0, "outside")
	var inside := AreaEvents.due(area, "enter_zone", Vector2i(4, 1), ctx.flags)
	assert_eq(inside.size(), 1, "the trap waits for its condition")
	assert_eq(inside[0].id, "spring")
	AreaEvents.fire(area, inside[0], ctx)
	assert_eq(AreaEvents.due(area, "enter_zone", Vector2i(4, 1), ctx.flags).size(), 1, "repeats")
	ctx.flags.set_flag("warned", true)
	assert_eq(AreaEvents.due(area, "enter_zone", Vector2i(5, 2), ctx.flags).size(), 2)


func test_npcs_present_by_condition() -> void:
	var area := _area()
	var flags := WorldFlags.new()
	assert_eq(AreaEvents.present_npcs(area, flags).size(), 2)
	flags.set_flag("party.tat", true)
	var present := AreaEvents.present_npcs(area, flags)
	assert_eq(present.size(), 1)
	assert_eq(present[0].id, "ded")


func test_dialog_answers_can_recruit_and_give() -> void:
	var data := {
		"start": "a",
		"nodes":
		{
			"a":
			{
				"text": "A",
				"options":
				[
					{
						"text": "B",
						"then":
						[
							{"action": "join_party", "character": "tat"},
							{"action": "give_item", "item": "verevka"},
						]
					}
				]
			}
		}
	}
	var ctx := _ctx()
	var runner := DialogRunner.start("d", data, ctx.flags, ctx)
	runner.choose(0)
	assert_true(ctx.party.members.has("tat"))
	assert_eq(runner.take_requests().size(), 2, "joined + item notices")
