class_name PathHeap
extends RefCounted
## Двоичная куча узлов поиска пути (ADR-0040): ключ — целое, в котором упакованы
## [f, h, z, x, чётность] (Pathfinder._key), узел — индекс. Порядок извлечения тот же,
## что у полного перебора, — пути не меняются. Устаревшие записи пропускает поиск.

var _keys := PackedInt64Array()
var _nodes := PackedInt32Array()


func is_empty() -> bool:
	return _nodes.is_empty()


func push(key: int, node: int) -> void:
	_keys.append(key)
	_nodes.append(node)
	var i := _nodes.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if _keys[i] >= _keys[parent]:
			break
		_swap(i, parent)
		i = parent


func pop() -> int:
	var top := _nodes[0]
	var last := _nodes.size() - 1
	_swap(0, last)
	_keys.resize(last)
	_nodes.resize(last)
	var i := 0
	var n := _nodes.size()
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var best := i
		if left < n and _keys[left] < _keys[best]:
			best = left
		if right < n and _keys[right] < _keys[best]:
			best = right
		if best == i:
			break
		_swap(i, best)
		i = best
	return top


func _swap(a: int, b: int) -> void:
	var k := _keys[a]
	_keys[a] = _keys[b]
	_keys[b] = k
	var v := _nodes[a]
	_nodes[a] = _nodes[b]
	_nodes[b] = v
