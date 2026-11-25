class_name Encounter
extends RefCounted
## Энкаунтер области (ADR-0032): противники на карте и что запускает бой — вход героя
## в зону или взгляд противника (радиус + линия видимости). Бой идёт на участке карты
## [member battle]: из него строится сетка боя, герои встают в ближайшие свободные
## клетки (SPEC §3.2).

const TRIGGER_ZONE := "zone"
const TRIGGER_SIGHT := "sight"
const TEAM_PARTY := "party"

var id: String = ""
var trigger: String = TRIGGER_ZONE
## Зона входа (для trigger = zone), клетки области.
var zone := Rect2i()
## Радиус взгляда в клетках (для trigger = sight).
var sight: int = 0
## Участок карты, где идёт бой.
var battle := Rect2i()
## Противники: {"id", "creature", "team", "at": [x, z] в клетках области}.
var combatants: Array[Dictionary] = []
## Действия при победе (ADR-0034), например смена стадии квеста.
var on_won: Array = []


static func from_dict(data: Dictionary) -> Encounter:
	var e := Encounter.new()
	e.id = JsonRead.get_str(data, "id")
	e.trigger = JsonRead.get_str(data, "trigger", TRIGGER_ZONE)
	e.zone = rect_of(JsonRead.get_array(data, "zone"))
	e.sight = JsonRead.get_int(data, "sight")
	e.battle = rect_of(JsonRead.get_array(data, "battle"))
	e.on_won = JsonRead.get_array(data, "then")
	for raw: Variant in JsonRead.get_array(data, "combatants"):
		var c: Dictionary = raw
		e.combatants.append(c)
	return e


## [x, z, ширина, глубина] → Rect2i.
static func rect_of(values: Array) -> Rect2i:
	if values.size() != 4:
		return Rect2i()
	return Rect2i(
		JsonRead.to_int(values[0]),
		JsonRead.to_int(values[1]),
		JsonRead.to_int(values[2]),
		JsonRead.to_int(values[3])
	)


## Флаг победы над этим энкаунтером.
func won_flag() -> String:
	return "encounter.%s.won" % id


func is_done(flags: WorldFlags) -> bool:
	return flags.matches({"flag": won_flag(), "eq": true})


## Клетка противника на карте.
func cell_of(combatant: Dictionary) -> Vector2i:
	return JsonRead.to_vec2i(combatant.get("at", []))


## Срабатывает ли энкаунтер, когда герои стоят в [param hero_cells].
func triggered(area: AreaMap, hero_cells: Array[Vector2i]) -> bool:
	for h in hero_cells:
		if trigger == TRIGGER_ZONE and zone.has_point(h):
			return true
		if trigger == TRIGGER_SIGHT:
			for c in combatants:
				var at := cell_of(c)
				if BattleGrid.chebyshev(at, h) <= sight and LineOfSight.can_see(area.grid, at, h):
					return true
	return false


## Данные боя в формате арены (для CombatLoader.new_combat): сетка — участок
## [member battle], герои [param heroes] (id → клетка области) встают в ближайшие
## свободные клетки участка. Координаты участников — клетки сетки боя.
func arena_data(area: AreaMap, heroes: Dictionary[String, Vector2i]) -> Dictionary:
	var rows: Array[String] = []
	var levels: Array[String] = []
	for z in battle.size.y:
		var row := ""
		var level_row := ""
		for x in battle.size.x:
			var c := battle.position + Vector2i(x, z)
			row += _battle_char(area, c)
			level_row += str(clampi(area.grid.level_at(c), 0, 9))
		rows.append(row)
		levels.append(level_row)
	var taken: Dictionary[Vector2i, bool] = {}
	var list: Array = []
	for c in combatants:
		var local := cell_of(c) - battle.position
		taken[local] = true
		var entry := c.duplicate()
		entry["at"] = [local.x, local.y]
		list.append(entry)
	var grid := BattleGrid.from_dict({"map": rows, "levels": levels})
	var ids: Array[String] = []
	ids.assign(heroes.keys())
	ids.sort()
	for hero in ids:
		var spot := nearest_free(grid, heroes[hero] - battle.position, taken)
		taken[spot] = true
		list.append({"id": hero, "character": hero, "team": TEAM_PARTY, "at": [spot.x, spot.y]})
	return {"id": "encounter." + id, "grid": {"map": rows, "levels": levels}, "combatants": list}


## Ближайшая к [param want] свободная проходимая клетка сетки (кольцами по Чебышёву,
## в кольце — по строкам, затем по столбцам: результат детерминирован).
static func nearest_free(
	grid: BattleGrid, want: Vector2i, taken: Dictionary[Vector2i, bool]
) -> Vector2i:
	var start := Vector2i(clampi(want.x, 0, grid.width - 1), clampi(want.y, 0, grid.depth - 1))
	for r in maxi(grid.width, grid.depth):
		for z in range(start.y - r, start.y + r + 1):
			for x in range(start.x - r, start.x + r + 1):
				var c := Vector2i(x, z)
				if BattleGrid.chebyshev(c, start) != r:
					continue
				if grid.is_walkable(c) and not taken.has(c):
					return c
	return start


static func _battle_char(area: AreaMap, c: Vector2i) -> String:
	if area.grid.is_low_obstacle(c):
		return "="
	if area.grid.is_blocked(c):
		return "#"
	return "."
