class_name Rng
extends RefCounted
## Единственный источник случайности в ядре (ADR-0006).
## Глобальные randi()/randf()/randomize() в core/ запрещены.
## Seed и состояние сохраняются строками: 64-битные целые теряют точность в JSON.

var _seed: int = 0
var _gen: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_seed = seed_value
	_gen.seed = seed_value


func get_seed() -> int:
	return _seed


## Бросок кости с [param sides] гранями, результат от 1 до sides.
func roll(sides: int) -> int:
	assert(sides >= 1, "sides must be >= 1")
	return _gen.randi_range(1, sides)


func to_dict() -> Dictionary:
	return {"seed": str(_seed), "state": str(_gen.state)}


func load_dict(data: Dictionary) -> void:
	set_seed(str(data["seed"]).to_int())
	_gen.state = str(data["state"]).to_int()


static func from_dict(data: Dictionary) -> Rng:
	var rng := Rng.new()
	rng.load_dict(data)
	return rng
