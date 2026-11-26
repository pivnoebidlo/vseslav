class_name TravelState
extends RefCounted
## Глобальная карта: день и город отряда (ADR-0051). Живёт, пока запущена игра, как флаги
## исследования; попадает в GameSave и возвращается при загрузке.

static var day := 1
## Город карты, где отряд сейчас; пусто — не в городе карты.
static var city := ""


static func reset() -> void:
	day = 1
	city = ""


static func fill_save(s: GameSave) -> void:
	s.day = day
	s.city = city


static func apply_save(s: GameSave) -> void:
	day = s.day
	city = s.city
