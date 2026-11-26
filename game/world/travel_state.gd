class_name TravelState
extends RefCounted
## Глобальная карта: день пути (ADR-0051). Город не хранится отдельно — его даёт текущая
## область (WorldMap.city_in_area), а в сохранение он пишется для сведения. Живёт, пока
## запущена игра, как флаги исследования.

static var day := 1


static func reset() -> void:
	day = 1


static func fill_save(s: GameSave, city: String) -> void:
	s.day = day
	s.city = city


static func apply_save(s: GameSave) -> void:
	day = s.day
