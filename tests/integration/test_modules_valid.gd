extends GutTest
## Встроенные модули загружаются без единой ошибки, схемы согласованы с кодом (ADR-0028).

var _content: ModuleContent
var _schema: JsonSchema


func before_all() -> void:
	_content = ModuleLoader.load_all(["res://modules"])
	var errors: Array[String] = []
	_schema = JsonSchema.load_dir(ModuleLoader.SCHEMA_DIR, errors)
	assert_eq(errors, [] as Array[String])


func test_all_builtin_modules_load_cleanly() -> void:
	assert_eq(_content.errors, [] as Array[String])
	assert_eq(_content.failed, [] as Array[String])
	var ids: Array[String] = []
	for m in _content.modules:
		ids.append(m.id)
	assert_eq(ids, ["vseslav.base", "vseslav.spike"] as Array[String])
	assert_eq(_content.rules.errors, [] as Array[String])
	var start := _content.start()
	assert_eq(JsonRead.get_str(start, "area"), "derevnya")
	assert_eq(
		JsonRead.get_str_array(start, "party"), ["ratnik", "lovchiy", "volkhv"] as Array[String]
	)
	assert_eq(_content.area("derevnya").npcs.size(), 6, "3 villagers + 3 future companions")
	assert_eq(_content.area("derevnya").encounters.size(), 2)
	var world := _content.world_map([] as Array[String])
	assert_eq(world.sorted_ids(), ["minsk", "polotsk"] as Array[String])
	assert_eq(world.days_between("polotsk", "minsk"), 2)
	assert_gte(_content.props.size(), 20, "KayKit props")


func test_schemas_use_only_supported_keywords() -> void:
	var errors: Array[String] = []
	_schema.check_schema(errors)
	assert_eq(errors, [] as Array[String])


func test_loaded_rules_match_the_plain_rules_folder() -> void:
	var db := RulesDb.load_dir("res://modules/base/rules")
	assert_eq(_content.rules.items.keys().size(), db.items.keys().size())
	assert_eq(_content.rules.creatures.keys().size(), db.creatures.keys().size())


func _enum(path: Array[String]) -> Array[String]:
	var node: Variant = _schema.schemas["common.schema.json"]["$defs"]
	for key in path:
		var d: Dictionary = node
		node = d[key]
	var d2: Dictionary = node
	var values: Array[String] = []
	for v: Variant in d2["enum"]:
		values.append(str(v))
	values.sort()
	return values


func _sorted(values: Array[String]) -> Array[String]:
	var copy := values.duplicate()
	copy.sort()
	return copy


## Перечисления в схемах повторяют константы кода — иначе схема и игра разойдутся.
func test_schema_enums_match_code() -> void:
	assert_eq(_enum(["ability"]), _sorted(Abilities.ALL))
	assert_eq(_enum(["damage_type"]), _sorted(DamageRules.TYPES))
	assert_eq(_enum(["condition"]), _sorted(Conditions.ALL))
	assert_eq(_enum(["trait", "properties", "type"]), _sorted(TraitDef.TYPES))
	assert_eq(_enum(["action", "properties", "kind"]), _sorted(ActionDef.KINDS))
	assert_eq(_enum(["action", "properties", "cost"]), _sorted(ActionDef.COSTS))
	assert_eq(_enum(["action", "properties", "target"]), _sorted(ActionDef.TARGETS))
	assert_eq(_enum(["action", "properties", "special"]), _sorted(ActionDef.SPECIALS))
	assert_eq(_enum(["action", "properties", "mastery"]), _sorted(ActionDef.MASTERIES))
	var abilities := Abilities.ALL.duplicate()
	abilities.append("spell")
	assert_eq(_enum(["action", "properties", "ability"]), _sorted(abilities))
