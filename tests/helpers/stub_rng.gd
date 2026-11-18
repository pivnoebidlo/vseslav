class_name StubRng
extends Rng
## Подставной RNG для тестов: возвращает заранее заданные броски по порядку.

var _queue: Array[int] = []


func _init(rolls: Array[int] = []) -> void:
	super(0)
	_queue = rolls.duplicate()


func roll(sides: int) -> int:
	assert(not _queue.is_empty(), "StubRng: no more rolls")
	var value: int = _queue.pop_front()
	assert(value >= 1 and value <= sides, "StubRng: roll %d does not fit d%d" % [value, sides])
	return value


func remaining() -> int:
	return _queue.size()
