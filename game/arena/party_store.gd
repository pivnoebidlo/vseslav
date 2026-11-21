class_name PartyStore
extends RefCounted
## Сохранение снаряжения партии между боями (user://saves/party.json, ADR-0024).

const PATH := "user://saves/party.json"


## Сохранённая партия или партия по умолчанию из данных.
static func load_party(db: RulesDb) -> Party:
	if not FileAccess.file_exists(PATH):
		return Party.from_db(db)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return Party.from_db(db)
	var data: Dictionary = parsed
	var errors: Array[String] = []
	var party := Party.from_dict(data, db, errors)
	for err in errors:
		push_warning("Party save: %s" % err)
	return party


static func save_party(party: Party) -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(party.to_dict(), "  ", true))
	file.close()
