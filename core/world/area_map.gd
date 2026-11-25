class_name AreaMap
extends RefCounted
## Область для исследования (areas/<id>.json, ADR-0029): символьная карта, точки
## появления, жители и энкаунтеры (ADR-0032). Проходимость — та же BattleGrid,
## что и в бою: путь ищет тот же Pathfinder, а бой идёт по этой же сетке.

const GROUND := "."
const ROAD := ","
const BUILDING := "#"
const TREE := "T"
const FENCE := "="
const GRAVE := "+"
const TILES: Array[String] = [GROUND, ROAD, BUILDING, TREE, FENCE, GRAVE]
const SURFACE_GROUND := "ground"
const SURFACE_ROAD := "road"
const SURFACE_WALL := "wall"
const SURFACE_CLIFF := "cliff"


## Житель области.
class Npc:
	extends RefCounted
	var id: String = ""
	var name_key: String = ""
	var at: Vector2i = Vector2i.ZERO
	## Облик — id из models/models.json.
	var look: String = ""
	var dialog: String = ""
	## Торговец (ADR-0050): нужна запись с тем же id в merchants.json;
	## у такого жителя в разговоре есть кнопка «Торг».
	var merchant := false
	## Когда житель на месте (флаги); пусто — всегда (ADR-0042). Например, будущий
	## спутник стоит в деревне, пока не принят в отряд.
	var conditions: Array = []


## Именованная зона-триггер (SPEC §8): событие trigger_entered ссылается на неё по id.
class Trigger:
	extends RefCounted
	var id: String = ""
	var zone: Rect2i = Rect2i()


## Событие области (ADR-0042): при входе в область, в зону или в триггер, с условиями;
## по умолчанию срабатывает один раз (флаг event.<область>.<id>).
class AreaEvent:
	extends RefCounted
	const ON_ENTER_AREA := "enter_area"
	const ON_ENTER_ZONE := "enter_zone"
	const ON_TRIGGER_ENTERED := "trigger_entered"
	var id: String = ""
	var on: String = ON_ENTER_AREA
	var zone: Rect2i = Rect2i()
	## Для trigger_entered: id триггера этой области.
	var source: String = ""
	var conditions: Array = []
	var actions: Array = []
	var once: bool = true


## Выход в другую область.
class Exit:
	extends RefCounted
	var id: String = ""
	var name_key: String = ""
	var at: Vector2i = Vector2i.ZERO
	var to_area: String = ""
	var to_spawn: String = ""


## Сундук: содержимое (как мешок: items, purse) и действия при первом открытии.
class Chest:
	extends RefCounted
	var id: String = ""
	var name_key: String = ""
	var at: Vector2i = Vector2i.ZERO
	var prop: String = ""
	var contents: Dictionary = {}
	var on_open: Array = []


var id: String = ""
var title_key: String = ""
## Внутри помещения: стены ниже, чтобы камера видела комнату (ADR-0034).
var interior := false
var rows: Array[String] = []
var grid: BattleGrid = BattleGrid.new()
var spawns: Dictionary[String, Vector2i] = {}
var npcs: Array[Npc] = []
var events: Array[AreaEvent] = []
## Именованные зоны-триггеры (SPEC §8): на них ссылается source событий.
var triggers: Array[Trigger] = []
var encounters: Array[Encounter] = []
## Выходы в другие области (ADR-0034): клетка → область и точка появления.
var exits: Array[Exit] = []
## Сундуки и другие вместилища: стоят в клетке, как жители, — к ним подходят.
var containers: Array[Chest] = []
## Облик (ADR-0033): какие модели ставить на символы карты и явные объекты.
var style: Dictionary = {}
var objects: Array[Dictionary] = []
## Текстуры земли и дороги (ADR-0036): SURFACE_* → id поверхности.
var surfaces: Dictionary = {}
## Строки уровней высоты (ADR-0037); пусто — область плоская.
var heights: Array[String] = []


## Область из уже проверенных схемой данных.
static func from_dict(p_id: String, data: Dictionary) -> AreaMap:
	var a := AreaMap.new()
	a.id = p_id
	a.title_key = JsonRead.get_str(data, "title_key")
	a.rows = JsonRead.get_str_array(data, "map")
	var width := 0
	for row in a.rows:
		width = maxi(width, row.length())
	a.grid = BattleGrid.new(width, a.rows.size())
	for z in a.rows.size():
		for x in width:
			var c := Vector2i(x, z)
			match a.tile(c):
				BUILDING, TREE:
					a.grid.set_blocked(c, true)
				FENCE, GRAVE:
					a.grid.set_low_obstacle(c, true)
	# Рельеф (ADR-0037): цифра — уровень клетки, 5 футов на уровень.
	a.heights = JsonRead.get_str_array(data, "heights")
	for z in mini(a.heights.size(), a.rows.size()):
		var line := a.heights[z]
		for x in mini(line.length(), width):
			if line[x].is_valid_int():
				a.grid.set_level(Vector2i(x, z), line[x].to_int())
	var spawn_data := JsonRead.get_dict(data, "spawns")
	var names: Array[String] = []
	names.assign(spawn_data.keys())
	names.sort()
	for name in names:
		a.spawns[name] = JsonRead.to_vec2i(spawn_data[name])
	for raw: Variant in JsonRead.get_array(data, "npcs"):
		var d: Dictionary = raw
		var npc := Npc.new()
		npc.id = JsonRead.get_str(d, "id")
		npc.name_key = JsonRead.get_str(d, "name_key")
		npc.at = JsonRead.to_vec2i(d.get("at", []))
		npc.look = JsonRead.get_str(d, "look")
		npc.dialog = JsonRead.get_str(d, "dialog")
		npc.merchant = JsonRead.get_bool(d, "merchant")
		npc.conditions = JsonRead.get_array(d, "if")
		a.npcs.append(npc)
	for raw: Variant in JsonRead.get_array(data, "events"):
		var d: Dictionary = raw
		var ev := AreaEvent.new()
		ev.id = JsonRead.get_str(d, "id")
		ev.on = JsonRead.get_str(d, "on", AreaEvent.ON_ENTER_AREA)
		ev.zone = Encounter.rect_of(JsonRead.get_array(d, "zone"))
		ev.source = JsonRead.get_str(d, "source")
		ev.conditions = JsonRead.get_array(d, "if")
		ev.actions = JsonRead.get_array(d, "then")
		ev.once = JsonRead.get_bool(d, "once", true)
		a.events.append(ev)
	for raw: Variant in JsonRead.get_array(data, "triggers"):
		var d: Dictionary = raw
		var t := Trigger.new()
		t.id = JsonRead.get_str(d, "id")
		t.zone = Encounter.rect_of(JsonRead.get_array(d, "zone"))
		a.triggers.append(t)
	a.style = JsonRead.get_dict(data, "style")
	a.surfaces = JsonRead.get_dict(data, "surfaces")
	a.interior = JsonRead.get_bool(data, "interior")
	for raw: Variant in JsonRead.get_array(data, "exits"):
		var d: Dictionary = raw
		var x := Exit.new()
		x.id = JsonRead.get_str(d, "id")
		x.name_key = JsonRead.get_str(d, "name_key")
		x.at = JsonRead.to_vec2i(d.get("at", []))
		var to := JsonRead.get_dict(d, "to")
		x.to_area = JsonRead.get_str(to, "area")
		x.to_spawn = JsonRead.get_str(to, "spawn")
		a.exits.append(x)
	for raw: Variant in JsonRead.get_array(data, "containers"):
		var d: Dictionary = raw
		var box := Chest.new()
		box.id = JsonRead.get_str(d, "id")
		box.name_key = JsonRead.get_str(d, "name_key")
		box.at = JsonRead.to_vec2i(d.get("at", []))
		box.prop = JsonRead.get_str(d, "prop")
		box.contents = {
			"bag": JsonRead.get_array(d, "items"), "purse": JsonRead.get_int(d, "purse")
		}
		box.on_open = JsonRead.get_array(d, "then")
		a.containers.append(box)
	for raw: Variant in JsonRead.get_array(data, "objects"):
		var o: Dictionary = raw
		a.objects.append(o)
	for raw: Variant in JsonRead.get_array(data, "encounters"):
		var e: Dictionary = raw
		a.encounters.append(Encounter.from_dict(e))
	return a


func width() -> int:
	return grid.width


func depth() -> int:
	return grid.depth


## Символ клетки; за пределами карты и в коротких строках — земля.
func tile(c: Vector2i) -> String:
	if c.y < 0 or c.y >= rows.size() or c.x < 0 or c.x >= rows[c.y].length():
		return GROUND
	return rows[c.y][c.x]


func get_encounter(encounter_id: String) -> Encounter:
	for e in encounters:
		if e.id == encounter_id:
			return e
	return null


func get_trigger(trigger_id: String) -> Trigger:
	for t in triggers:
		if t.id == trigger_id:
			return t
	return null


func get_npc(npc_id: String) -> Npc:
	for npc in npcs:
		if npc.id == npc_id:
			return npc
	return null


## Клетки, занятые жителями и сундуками: сквозь них не ходят.
func npc_cells() -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for npc in npcs:
		cells[npc.at] = true
	for box in containers:
		cells[box.at] = true
	return cells


func get_exit(exit_id: String) -> Exit:
	for x in exits:
		if x.id == exit_id:
			return x
	return null


func get_container(container_id: String) -> Chest:
	for box in containers:
		if box.id == container_id:
			return box
	return null


## Ближайшие к точке появления свободные клетки для [param count] героев.
func spawn_cells(spawn: String, count: int) -> Array[Vector2i]:
	var taken := npc_cells()
	var out: Array[Vector2i] = []
	var at: Vector2i = spawns.get(spawn, Vector2i.ZERO)
	for i in count:
		var c := Encounter.nearest_free(grid, at, taken)
		taken[c] = true
		out.append(c)
	return out


## Путь до клетки [param to] в обход построек, жителей и клеток [param blocked]
## (например, противников на карте).
func path(from: Vector2i, to: Vector2i, blocked: Dictionary[Vector2i, bool] = {}) -> PathResult:
	var occupied := npc_cells()
	occupied.merge(blocked)
	return Pathfinder.find_path(grid, from, to, occupied)


## Кратчайший путь к соседней с жителем клетке; пустой — подойти нельзя или уже рядом
## (тогда [method is_next_to] вернёт true).
func approach(
	from: Vector2i, npc_id: String, blocked: Dictionary[Vector2i, bool] = {}
) -> PathResult:
	var npc := get_npc(npc_id)
	if npc == null:
		return PathResult.new()
	return approach_cell(from, npc.at, blocked)


## Кратчайший путь к соседней с [param target] клетке (житель, сундук).
func approach_cell(
	from: Vector2i, target: Vector2i, blocked: Dictionary[Vector2i, bool] = {}
) -> PathResult:
	var best := PathResult.new()
	if is_next_to(from, target):
		return best
	for step in Pathfinder.NEIGHBORS:
		var p := path(from, target + step, blocked)
		if p.found() and (not best.found() or p.total_cost() < best.total_cost()):
			best = p
	return best


static func is_next_to(a: Vector2i, b: Vector2i) -> bool:
	return a != b and BattleGrid.chebyshev(a, b) == 1
