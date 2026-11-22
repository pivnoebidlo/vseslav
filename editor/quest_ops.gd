class_name QuestOps
extends RefCounted
## Правки квестов (ADR-0039): новый квест, стадии, тексты, последняя стадия.
## Ключи строк создаются сами: QUEST_<ID> и QUEST_<ID>_<СТАДИЯ>.

const KIND := ModuleDoc.KIND_QUEST
const FIRST_STAGE := "started"


static func title_key(quest_id: String) -> String:
	return ("QUEST_%s" % quest_id).replace(".", "_").to_upper()


static func stage_key(quest_id: String, stage_id: String) -> String:
	return ("QUEST_%s_%s" % [quest_id, stage_id]).replace(".", "_").to_upper()


static func new_quest(doc: ModuleDoc, quest_id: String, title: String) -> DocEdit:
	var stage := stage_key(quest_id, FIRST_STAGE)
	var data := {
		"title_key": title_key(quest_id),
		"stages": [{"id": FIRST_STAGE, "text_key": stage}],
	}
	var edit := DocEdit.new("new quest")
	edit.set_value(doc, KIND, quest_id, [], data)
	edit.set_text(doc, title_key(quest_id), "ru", title)
	edit.set_text(doc, stage, "ru", "")
	return edit


static func delete_quest(doc: ModuleDoc, quest_id: String) -> DocEdit:
	var edit := DocEdit.new("delete quest")
	var keys: Array[String] = [title_key(quest_id)]
	for raw: Variant in stages_of(doc, quest_id):
		var s: Dictionary = raw
		keys.append(JsonRead.get_str(s, "text_key"))
	for key in keys:
		for lang in ModuleDoc.LANGS:
			if doc.text(key, lang) != "":
				edit.set_text(doc, key, lang, "")
	edit.set_value(doc, KIND, quest_id, [], null)
	return edit


static func add_stage(doc: ModuleDoc, quest_id: String, stage_id: String, text: String) -> DocEdit:
	var stages := stages_of(doc, quest_id)
	var key := stage_key(quest_id, stage_id)
	stages.append({"id": stage_id, "text_key": key})
	var edit := DocEdit.new("add stage")
	edit.set_value(doc, KIND, quest_id, ["stages"], stages)
	edit.set_text(doc, key, "ru", text)
	return edit


static func remove_stage(doc: ModuleDoc, quest_id: String, index: int) -> DocEdit:
	var stages := stages_of(doc, quest_id)
	var edit := DocEdit.new("remove stage")
	if index < 0 or index >= stages.size() or stages.size() <= 1:
		return edit
	var removed: Dictionary = stages[index]
	var key := JsonRead.get_str(removed, "text_key")
	for lang in ModuleDoc.LANGS:
		if doc.text(key, lang) != "":
			edit.set_text(doc, key, lang, "")
	stages.remove_at(index)
	edit.set_value(doc, KIND, quest_id, ["stages"], stages)
	return edit


## Отмечает стадию [param index] последней (квест выполнен) или снимает отметку.
static func set_final(doc: ModuleDoc, quest_id: String, index: int, final: bool) -> DocEdit:
	var stages := stages_of(doc, quest_id)
	var edit := DocEdit.new("final stage")
	if index < 0 or index >= stages.size():
		return edit
	var s: Dictionary = stages[index]
	if final:
		s["final"] = true
	else:
		s.erase("final")
	edit.set_value(doc, KIND, quest_id, ["stages"], stages)
	return edit


## Свободный id стадии: stage_2, stage_3…
static func free_stage_id(doc: ModuleDoc, quest_id: String) -> String:
	var used: Dictionary[String, bool] = {}
	for raw: Variant in stages_of(doc, quest_id):
		var s: Dictionary = raw
		used[JsonRead.get_str(s, "id")] = true
	var n := used.size() + 1
	while used.has("stage_%d" % n):
		n += 1
	return "stage_%d" % n


static func stages_of(doc: ModuleDoc, quest_id: String) -> Array:
	var value: Variant = doc.get_value(KIND, quest_id, ["stages"])
	if not value is Array:
		return []
	var a: Array = value
	return a.duplicate(true)
