class_name GameSave
extends RefCounted
## Сохранение игры (SPEC §9, ADR-0032): модуль, режим (исследование или бой), область,
## клетки героев, выбранный и сцепка, флаги, партия, RNG вне боя и — посреди боя —
## энкаунтер и CombatState. JSON из простых типов; [constant SAVE_FORMAT] растёт при
## изменении формата, старые версии читаются миграцией.

const SAVE_FORMAT := 1
const GAME_VERSION := "0.1.0"
const MODE_EXPLORATION := "exploration"
const MODE_COMBAT := "combat"

const ERR_FORMAT := "err_save_format"
const ERR_MODULE := "err_save_module"
const ERR_DATA := "err_save_data"

var module_id: String = ""
var module_version: String = ""
var mode: String = MODE_EXPLORATION
var area: String = ""
## Клетка каждого героя на карте; пусто — герои встают у точки появления [member spawn]
## (переход в другую область).
var heroes: Dictionary[String, Vector2i] = {}
var spawn: String = ""
## Содержимое открытых сундуков: "<область>.<id>" → мешок (Inventory.to_dict).
var containers: Dictionary = {}
var selected: String = ""
var chained: Dictionary[String, bool] = {}
var flags := WorldFlags.new()
## Партия (Party.to_dict) — снаряжение и состояние героев.
var party: Dictionary = {}
var rng: Dictionary = {}
## Посреди боя: id энкаунтера и состояние боя (CombatState.to_dict).
var encounter: String = ""
var combat: Dictionary = {}


func to_dict() -> Dictionary:
	var hero_cells := {}
	var ids: Array[String] = []
	ids.assign(heroes.keys())
	ids.sort()
	var chain := {}
	for id in ids:
		hero_cells[id] = [heroes[id].x, heroes[id].y]
		chain[id] = chained.get(id, true)
	return {
		"save_format": SAVE_FORMAT,
		"game_version": GAME_VERSION,
		"module": {"id": module_id, "version": module_version},
		"mode": mode,
		"game_state":
		{
			"area": area,
			"heroes": hero_cells,
			"spawn": spawn,
			"containers": containers,
			"selected": selected,
			"chained": chain,
			"flags": flags.to_dict(),
			"party": party,
			"rng": rng,
		},
		"encounter": encounter,
		"combat_state": combat if mode == MODE_COMBAT else null,
	}


## Сохранение из JSON. Ошибка (ключ локализации) — в [param errors], тогда null.
static func from_dict(data: Dictionary, errors: Array[String]) -> GameSave:
	var format := JsonRead.get_int(data, "save_format")
	if format < 1 or format > SAVE_FORMAT:
		errors.append(ERR_FORMAT)
		return null
	var s := GameSave.new()
	var module := JsonRead.get_dict(data, "module")
	s.module_id = JsonRead.get_str(module, "id")
	s.module_version = JsonRead.get_str(module, "version")
	s.mode = JsonRead.get_str(data, "mode", MODE_EXPLORATION)
	var state := JsonRead.get_dict(data, "game_state")
	s.area = JsonRead.get_str(state, "area")
	var cells := JsonRead.get_dict(state, "heroes")
	var chain := JsonRead.get_dict(state, "chained")
	for key: Variant in cells:
		var id := str(key)
		s.heroes[id] = JsonRead.to_vec2i(cells[key])
		s.chained[id] = JsonRead.get_bool(chain, id, true)
	s.selected = JsonRead.get_str(state, "selected")
	s.spawn = JsonRead.get_str(state, "spawn")
	s.containers = JsonRead.get_dict(state, "containers")
	s.flags = WorldFlags.from_dict(JsonRead.get_dict(state, "flags"))
	s.party = JsonRead.get_dict(state, "party")
	s.rng = JsonRead.get_dict(state, "rng")
	s.encounter = JsonRead.get_str(data, "encounter")
	if s.mode == MODE_COMBAT:
		s.combat = JsonRead.get_dict(data, "combat_state")
		if s.encounter == "" or s.combat.is_empty():
			errors.append(ERR_DATA)
			return null
	if s.area == "" or (s.heroes.is_empty() and s.spawn == ""):
		errors.append(ERR_DATA)
		return null
	return s


## Подходит ли сохранение к загруженным модулям: модуль есть, область есть.
func check(content: ModuleContent, errors: Array[String]) -> void:
	if not content.has_module(module_id):
		errors.append(ERR_MODULE)
	elif content.area(area) == null:
		errors.append(ERR_DATA)
