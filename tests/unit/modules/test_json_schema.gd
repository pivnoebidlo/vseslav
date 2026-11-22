extends GutTest
## Валидатор подмножества JSON Schema (ADR-0028).

var _js: JsonSchema


func before_each() -> void:
	_js = JsonSchema.new()
	_js.schemas["common.schema.json"] = {
		"$defs": {"id": {"type": "string", "pattern": "^[a-z_]+$"}},
	}
	_js.schemas["thing.schema.json"] = {
		"type": "object",
		"required": ["id", "count"],
		"additionalProperties": false,
		"properties":
		{
			"id": {"$ref": "common.schema.json#/$defs/id"},
			"count": {"type": "integer", "minimum": 1, "maximum": 4},
			"weight": {"type": "number", "minimum": 0},
			"kind": {"enum": ["a", "b"]},
			"tags": {"type": "array", "items": {"$ref": "#/$defs/tag"}, "maxItems": 2},
			"stack":
			{
				"anyOf":
				[
					{"$ref": "common.schema.json#/$defs/id"},
					{
						"type": "object",
						"required": ["item"],
						"properties": {"item": {"type": "string"}},
					},
				],
			},
			"levels":
			{
				"type": "object",
				"propertyNames": {"pattern": "^[0-9]+$"},
				"additionalProperties": {"type": "integer"},
			},
		},
		"$defs": {"tag": {"type": "string", "maxLength": 5}},
	}


func _errors(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	_js.validate(value, "thing.schema.json", "f.json", errors)
	return errors


func _parsed(text: String) -> Variant:
	return JSON.parse_string(text)


func test_valid_value_passes() -> void:
	var v: Variant = _parsed(
		(
			'{"id": "topor", "count": 2, "weight": 0.5, "kind": "a", "tags": ["x"],'
			+ ' "stack": {"item": "y"}, "levels": {"1": 3}}'
		)
	)
	assert_eq(_errors(v), [] as Array[String])


func test_reports_missing_unknown_and_wrong_type_with_path() -> void:
	var errors := _errors(_parsed('{"id": "topor", "cuont": 2, "weight": "heavy"}'))
	assert_has(errors, "f.json: $: missing 'count'")
	assert_has(errors, "f.json: $.cuont: unknown field")
	assert_has(errors, "f.json: $.weight: expected number, got string")


func test_integer_rejects_fractions_from_json() -> void:
	# JSON отдаёт все числа как float: 2 — целое, 2.5 — нет.
	assert_eq(_errors(_parsed('{"id": "a", "count": 2}')), [] as Array[String])
	assert_has(
		_errors(_parsed('{"id": "a", "count": 2.5}')),
		"f.json: $.count: expected integer, got number"
	)


func test_bounds_enum_pattern_and_lengths() -> void:
	var errors := _errors(
		_parsed('{"id": "Topor", "count": 9, "kind": "c", "tags": ["toolong", "b", "c"]}')
	)
	assert_has(errors, "f.json: $.id: 'Topor' does not match ^[a-z_]+$")
	assert_has(errors, "f.json: $.count: greater than 4")
	assert_has(errors, 'f.json: $.kind: "c" is not one of ["a", "b"]')
	assert_has(errors, "f.json: $.tags: at most 2 items")
	assert_has(errors, "f.json: $.tags[0]: longer than 5")


func test_any_of_explains_the_variant_of_matching_type() -> void:
	assert_eq(_errors(_parsed('{"id": "a", "count": 1, "stack": "topor"}')), [] as Array[String])
	assert_has(
		_errors(_parsed('{"id": "a", "count": 1, "stack": {"count": 2}}')),
		"f.json: $.stack: missing 'item'"
	)
	assert_has(
		_errors(_parsed('{"id": "a", "count": 1, "stack": 5}')),
		"f.json: $.stack: matches none of the allowed forms"
	)


func test_property_names_and_additional_schema() -> void:
	var errors := _errors(_parsed('{"id": "a", "count": 1, "levels": {"x": 1, "2": "y"}}'))
	assert_has(errors, "f.json: $.levels.x: 'x' does not match ^[0-9]+$")
	assert_has(errors, "f.json: $.levels.2: expected integer, got string")


func test_unknown_schema_name() -> void:
	var errors: Array[String] = []
	_js.validate({}, "missing.schema.json", "f.json", errors)
	assert_eq(errors, ["f.json: no schema missing.schema.json"] as Array[String])


func test_check_schema_flags_unsupported_keywords_and_bad_refs() -> void:
	_js.schemas["bad.schema.json"] = {
		"type": "object",
		"properties":
		{
			"a": {"type": "string", "format": "email"},
			"b": {"$ref": "#/$defs/nope"},
		},
	}
	var errors: Array[String] = []
	_js.check_schema(errors)
	assert_has(errors, "bad.schema.json.properties.a: unsupported keyword 'format'")
	assert_has(errors, "bad.schema.json.properties.b: unresolved $ref #/$defs/nope")
	assert_eq(errors.size(), 2, "the good schemas are clean")
