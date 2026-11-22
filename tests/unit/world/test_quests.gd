extends GutTest
## Действия событий и журнал квестов (ADR-0034).

const QUESTS: Dictionary[String, Dictionary] = {
	"krysy":
	{
		"title_key": "Q",
		"stages":
		[
			{"id": "started", "text_key": "S"},
			{"id": "cleared", "text_key": "C"},
			{"id": "done", "text_key": "D", "final": true},
		],
	},
	"ogni": {"title_key": "O", "stages": [{"id": "seen", "text_key": "O1"}]},
}


func _stage(stage: String) -> Array:
	return [{"action": "set_quest", "quest": "krysy", "stage": stage}]


func test_set_quest_from_nothing_reports_change() -> void:
	var flags := WorldFlags.new()
	assert_eq(EventActions.apply(_stage("started"), flags), ["krysy"] as Array[String])
	assert_true(flags.matches({"flag": "quest.krysy", "eq": "started"}))
	assert_eq(EventActions.apply(_stage("started"), flags), [] as Array[String], "same stage")
	assert_eq(EventActions.apply(_stage("cleared"), flags), ["krysy"] as Array[String])


func test_set_flag_still_works() -> void:
	var flags := WorldFlags.new()
	var changed := EventActions.apply([{"action": "set_flag", "flag": "a", "value": 3}], flags)
	assert_eq(changed, [] as Array[String])
	assert_true(flags.matches({"flag": "a", "eq": 3}))


func test_journal_lists_started_quests_active_first() -> void:
	var flags := WorldFlags.new()
	assert_eq(Journal.entries(QUESTS, flags).size(), 0)
	EventActions.apply(_stage("done"), flags)
	EventActions.apply([{"action": "set_quest", "quest": "ogni", "stage": "seen"}], flags)
	var entries := Journal.entries(QUESTS, flags)
	assert_eq(entries.size(), 2)
	assert_eq(entries[0].quest, "ogni", "unfinished first")
	assert_false(entries[0].done)
	assert_eq(entries[1].text_key, "D")
	assert_true(entries[1].done)


func test_unknown_stage_is_not_listed() -> void:
	var flags := WorldFlags.new()
	flags.set_flag("quest.krysy", "nope")
	assert_eq(Journal.entries(QUESTS, flags).size(), 0)


func test_dialog_reports_quest_changes() -> void:
	var dialog := {
		"start": "a",
		"nodes":
		{
			"a": {"text": "A", "options": [{"text": "T", "next": "b", "then": _stage("started")}]},
			"b": {"text": "B", "then": _stage("cleared")},
		},
	}
	var r := DialogRunner.start("d", dialog, WorldFlags.new())
	r.choose(0)
	assert_eq(r.quests_changed, ["krysy", "krysy"] as Array[String])
