class_name AreaMap
extends RefCounted
## Область для исследования (areas/<id>.json, ADR-0029): символьная карта, точки
## появления и жители. Проходимость — та же BattleGrid, что и в бою, поэтому путь
## ищет тот же Pathfinder, а бой в области позже построится по этой же сетке.

const GROUND := "."
const ROAD := ","
const BUILDING := "#"
const TREE := "T"
const FENCE := "="
const TILES: Array[String] = [GROUND, ROAD, BUILDING, TREE, FENCE]


## Житель области.
class Npc:
	extends RefCounted
	var id: String = ""
	var name_key: String = ""
	var at: Vector2i = Vector2i.ZERO
	## Облик — id из models/models.json.
	var look: String = ""
	var dialog: String = ""


var id: String = ""
var title_key: String = ""
var rows: Array[String] = []
var grid: BattleGrid = BattleGrid.new()
var spawns: Dictionary[String, Vector2i] = {}
var npcs: Array[Npc] = []


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
				FENCE:
					a.grid.set_low_obstacle(c, true)
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
		a.npcs.append(npc)
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


func get_npc(npc_id: String) -> Npc:
	for npc in npcs:
		if npc.id == npc_id:
			return npc
	return null


## Клетки, занятые жителями: сквозь них не ходят.
func npc_cells() -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for npc in npcs:
		cells[npc.at] = true
	return cells


## Путь до клетки [param to] в обход построек и жителей.
func path(from: Vector2i, to: Vector2i) -> PathResult:
	return Pathfinder.find_path(grid, from, to, npc_cells())


## Кратчайший путь к соседней с жителем клетке; пустой — подойти нельзя или уже рядом
## (тогда [method is_next_to] вернёт true).
func approach(from: Vector2i, npc_id: String) -> PathResult:
	var npc := get_npc(npc_id)
	var best := PathResult.new()
	if npc == null or is_next_to(from, npc.at):
		return best
	for step in Pathfinder.NEIGHBORS:
		var p := path(from, npc.at + step)
		if p.found() and (not best.found() or p.total_cost() < best.total_cost()):
			best = p
	return best


static func is_next_to(a: Vector2i, b: Vector2i) -> bool:
	return a != b and BattleGrid.chebyshev(a, b) == 1
