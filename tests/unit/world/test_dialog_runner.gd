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
