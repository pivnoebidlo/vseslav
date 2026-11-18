class_name LoadedModel
extends RefCounted
## Результат загрузки модели. При ошибке [member root] равен null, а [member errors] не пуст.

var path: String = ""
var root: Node3D = null
var skeleton: Skeleton3D = null
var animation_player: AnimationPlayer = null
## Профиль рига; null — риг не распознан (модель показывается, но без ретаргетинга).
var rig: RigProfile = null
## Ошибки и предупреждения: {"key": ключ локализации, "args": Dictionary}.
var errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
var triangles: int = 0
var bones: int = 0
var file_bytes: int = 0


func ok() -> bool:
	return errors.is_empty() and root != null


func add_error(key: String, args: Dictionary = {}) -> void:
	errors.append({"key": key, "args": args})


func add_warning(key: String, args: Dictionary = {}) -> void:
	warnings.append({"key": key, "args": args})


func animations() -> PackedStringArray:
	if animation_player == null:
		return PackedStringArray()
	return animation_player.get_animation_list()
