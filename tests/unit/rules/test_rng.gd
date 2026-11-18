extends GutTest


func _sequence(rng: Rng, n: int) -> Array[int]:
	var result: Array[int] = []
	for i in n:
		result.append(rng.roll(20))
	return result


func test_same_seed_same_sequence() -> void:
	assert_eq(_sequence(Rng.new(123), 50), _sequence(Rng.new(123), 50))


func test_different_seed_different_sequence() -> void:
	assert_ne(_sequence(Rng.new(1), 50), _sequence(Rng.new(2), 50))


func test_rolls_in_range() -> void:
	var rng := Rng.new(7)
	for i in 1000:
		var r := rng.roll(6)
		assert_between(r, 1, 6)


func test_saved_state_continues_sequence_through_json() -> void:
	var rng := Rng.new(99)
	_sequence(rng, 17)
	var text := JSON.stringify(rng.to_dict())
	var parsed: Dictionary = JSON.parse_string(text)
	var restored := Rng.from_dict(parsed)
	assert_eq(_sequence(restored, 30), _sequence(rng, 30))
