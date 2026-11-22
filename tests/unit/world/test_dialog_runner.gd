extends GutTest
## Диалоги: начало по условию, ответы по флагам, действия, конец разговора (ADR-0029).

const DIALOG := {
	"start": [{"if": [{"flag": "met", "eq": true}], "node": "again"}, {"node": "hello"}],
	"nodes":
	{
		"hello":
		{
			"text": "HELLO",
			"then": [{"action": "set_flag", "flag": "met", "value": true}],
			"options":
			[
				{"text": "ASK", "next": "news"},
				{"text": "SECRET", "next": "news", "if": [{"flag": "knows", "eq": true}]},
				{"text": "BYE"},
			],
		},
		"again": {"text": "AGAIN", "options": [{"text": "BYE"}]},
		"news":
		{
			"text": "NEWS",
			"options":
			[{"text": "OK", "then": [{"action": "set_flag", "flag": "visits", "value": 2}]}],
		},
	},
}

const CHECKED := {
	"start": "ask",
	"nodes":
	{
		"ask":
		{
			"text": "ASK",
			"options":
			[
				{
					"text": "CHARM",
					"check": {"ability": "cha", "dc": 15},
					"next": "yes",
					"fail": "no",
					"then": [{"action": "set_flag", "flag": "tried", "value": true}],
				},
				{"text": "BLUFF", "check": {"ability": "cha", "dc": 30}, "next": "yes"},
			],
		},
		"yes": {"text": "YES"},
		"no": {"text": "NO"},
	},
}


func test_first_meeting_then_repeat() -> void:
	var flags := WorldFlags.new()
	var r := DialogRunner.start("ded", DIALOG, flags)
	assert_eq(r.text_key(), "HELLO")
	assert_true(flags.matches({"flag": "met"}), "entering a node runs its actions")
	r.choose(1)
	assert_true(r.ended(), "option without next ends the talk")
	assert_eq(DialogRunner.start("ded", DIALOG, flags).text_key(), "AGAIN")


func _texts(r: DialogRunner) -> Array[String]:
	var texts: Array[String] = []
	for o in r.options():
		texts.append(JsonRead.get_str(o, "text"))
	return texts


func test_options_hidden_by_flags() -> void:
	var flags := WorldFlags.new()
	assert_eq(_texts(DialogRunner.start("ded", DIALOG, flags)), ["ASK", "BYE"] as Array[String])
	flags.set_flag("knows", true)
	flags.set_flag("met", false)
	assert_eq(
		_texts(DialogRunner.start("ded", DIALOG, flags)), ["ASK", "SECRET", "BYE"] as Array[String]
	)


func test_option_actions_and_next() -> void:
	var flags := WorldFlags.new()
	var r := DialogRunner.start("ded", DIALOG, flags)
	r.choose(0)
	assert_eq(r.node_id, "news")
	assert_eq(r.text_key(), "NEWS")
	r.choose(0)
	assert_true(r.ended())
	var visits: Variant = flags.get_flag("visits")
	assert_eq(typeof(visits), TYPE_INT, "JSON numbers stored as int")
	assert_true(flags.matches({"flag": "visits", "eq": 2}))


func test_bad_choice_is_ignored_and_empty_node_ends() -> void:
	var r := DialogRunner.start("ded", DIALOG, WorldFlags.new())
	r.choose(7)
	assert_eq(r.node_id, "hello")
	var silent := DialogRunner.start(
		"x", {"start": "a", "nodes": {"a": {"text": "A"}}}, WorldFlags.new()
	)
	assert_eq(silent.options().size(), 0)
	silent.choose(0)
	assert_true(silent.ended())


func test_unknown_start_ends_immediately() -> void:
	assert_true(DialogRunner.start("x", {"start": "nope", "nodes": {}}, WorldFlags.new()).ended())


func test_flags_from_json_numbers_and_round_trip() -> void:
	var parsed: Dictionary = JSON.parse_string('{"count": 3, "met": true, "name": "a"}')
	var flags := WorldFlags.from_dict(parsed)
	assert_true(flags.matches({"flag": "count", "eq": 3.0}))
	assert_true(flags.matches({"flag": "met"}), "eq defaults to true")
	assert_true(flags.matches({"flag": "unset", "eq": false}), "unset flag is false")
	assert_false(flags.matches({"flag": "count", "eq": "3"}))
	assert_eq(WorldFlags.from_dict(flags.to_dict()).to_dict(), flags.to_dict())


func _speaker(cha: int) -> Abilities:
	return Abilities.from_dict({"cha": cha})


func test_check_success_goes_to_next() -> void:
	var flags := WorldFlags.new()
	var r := DialogRunner.start("t", CHECKED, flags)
	r.choose(0, StubRng.new([13]), _speaker(14))
	assert_eq(r.text_key(), "YES", "13 + 2 = 15 meets DC 15")
	assert_eq(r.last_check.natural, 13)
	assert_eq(r.last_check.modifier, 2)
	assert_eq(r.last_check.total, 15)
	assert_true(r.last_check.success)
	assert_true(flags.matches({"flag": "tried"}), "actions run on either outcome")


func test_check_failure_goes_to_fail() -> void:
	var r := DialogRunner.start("t", CHECKED, WorldFlags.new())
	r.choose(0, StubRng.new([12]), _speaker(14))
	assert_eq(r.text_key(), "NO")
	assert_false(r.last_check.success)


func test_failure_without_fail_node_ends_talk() -> void:
	var r := DialogRunner.start("t", CHECKED, WorldFlags.new())
	r.choose(1, StubRng.new([20]), _speaker(10))
	assert_true(r.ended(), "natural 20 is no auto-success on checks")
	assert_eq(r.last_check.total, 20)


func test_option_without_check_clears_last_check() -> void:
	var r := DialogRunner.start("t", CHECKED, WorldFlags.new())
	r.choose(0, StubRng.new([20]), _speaker(10))
	r.choose(0)
	assert_null(r.last_check)
