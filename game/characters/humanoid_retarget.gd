class_name HumanoidRetarget
extends Node
## Ретаргетинг поз со скелета-источника на скелет цели. После каждого обновления источника
## позы записываются в скелет цели напрямую (как делает встроенный RetargetModifier3D).
## Кости сопоставляются по именам (оба рига переименованы в SkeletonProfileHumanoid).
##
## Почему не встроенный RetargetModifier3D (проверено спайком этапа 0):
## - в локальном режиме переносится разница поз покоя — у модели в A-позе руки «задираются»;
## - в глобальном режиме копируются и позиции костей — модель получает пропорции источника.
## Почему не свой SkeletonModifier3D: в Godot 4.3+ результат модификатора временный
## (только для отрисовки), а нам нужна настоящая поза — для логики и тестов.
##
## Формула для каждой сопоставленной кости (всё в пространстве модели):
##   поворот_цели = Δисточника × выравнивание × покой_цели,
##   где Δисточника = поза_источника × покой_источника⁻¹,
##   выравнивание — поворот, переводящий направление кости цели в покое
##   в направление той же кости источника в покое (A-поза → T-поза и т. п.).
## Длины костей берутся у цели; смещение таза масштабируется по соотношению высоты таза.

const HIPS := "Hips"

var source: Skeleton3D

var _target: Skeleton3D

## [индекс в цели, индекс в источнике], родители раньше детей.
var _pairs: Array[Vector2i] = []
## Для каждой пары: выравнивание × покой_цели (в пространстве модели).
var _target_rest_aligned: Array[Quaternion] = []
var _source_rest_inv: Array[Quaternion] = []
var _hips_target := -1
var _hips_source := -1
var _hips_scale := 1.0


## Сопоставляет кости источника и цели и подписывается на обновления источника.
func setup(p_source: Skeleton3D, target: Skeleton3D) -> void:
	source = p_source
	_target = target
	if not source.skeleton_updated.is_connected(apply):
		source.skeleton_updated.connect(apply)
	_pairs.clear()
	_target_rest_aligned.clear()
	_source_rest_inv.clear()
	for t_idx in _by_depth(target):
		var s_idx := source.find_bone(target.get_bone_name(t_idx))
		if s_idx < 0:
			continue
		_pairs.append(Vector2i(t_idx, s_idx))
	for pair in _pairs:
		var t_rest := target.get_bone_global_rest(pair.x).basis.get_rotation_quaternion()
		var s_rest := source.get_bone_global_rest(pair.y).basis.get_rotation_quaternion()
		_target_rest_aligned.append(_alignment(target, source, pair) * t_rest)
		_source_rest_inv.append(s_rest.inverse())
	_hips_target = target.find_bone(HIPS)
	_hips_source = source.find_bone(HIPS)
	if _hips_target >= 0 and _hips_source >= 0:
		var t_height := target.get_bone_global_rest(_hips_target).origin.y
		var s_height := source.get_bone_global_rest(_hips_source).origin.y
		_hips_scale = t_height / s_height if absf(s_height) > 0.0001 else 1.0


## Переносит текущую позу источника на цель.
func apply() -> void:
	var target := _target
	if not is_instance_valid(target) or not is_instance_valid(source) or _pairs.is_empty():
		return
	for i in _pairs.size():
		var pair := _pairs[i]
		var s_pose := source.get_bone_global_pose(pair.y).basis.get_rotation_quaternion()
		var wanted := s_pose * _source_rest_inv[i] * _target_rest_aligned[i]
		var parent := target.get_bone_parent(pair.x)
		var parent_rot := Quaternion.IDENTITY
		if parent >= 0:
			parent_rot = target.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		target.set_bone_pose_rotation(pair.x, (parent_rot.inverse() * wanted).normalized())
	if _hips_target >= 0 and _hips_source >= 0:
		var s_offset := (
			source.get_bone_pose_position(_hips_source) - source.get_bone_rest(_hips_source).origin
		)
		var t_rest := target.get_bone_rest(_hips_target).origin
		target.set_bone_pose_position(_hips_target, t_rest + s_offset * _hips_scale)


## Поворот, переводящий направление кости цели (в покое) в направление той же кости источника.
## Направление — к первой сопоставленной дочерней кости; у концевых костей — как у родителя.
func _alignment(target: Skeleton3D, src: Skeleton3D, pair: Vector2i) -> Quaternion:
	var t_child := _mapped_child(target, src, pair.x)
	if t_child < 0:
		var parent := target.get_bone_parent(pair.x)
		while parent >= 0:
			var s_parent := src.find_bone(target.get_bone_name(parent))
			if s_parent >= 0:
				return _alignment(target, src, Vector2i(parent, s_parent))
			parent = target.get_bone_parent(parent)
		return Quaternion.IDENTITY
	var s_child := src.find_bone(target.get_bone_name(t_child))
	var t_dir := (
		target.get_bone_global_rest(t_child).origin - target.get_bone_global_rest(pair.x).origin
	)
	var s_dir := src.get_bone_global_rest(s_child).origin - src.get_bone_global_rest(pair.y).origin
	if t_dir.length() < 0.0001 or s_dir.length() < 0.0001:
		return Quaternion.IDENTITY
	return Quaternion(t_dir.normalized(), s_dir.normalized())


func _mapped_child(target: Skeleton3D, src: Skeleton3D, bone: int) -> int:
	for child in target.get_bone_children(bone):
		if src.find_bone(target.get_bone_name(child)) >= 0:
			return child
	return -1


## Индексы костей так, чтобы родитель всегда шёл раньше детей.
static func _by_depth(skeleton: Skeleton3D) -> Array[int]:
	var order: Array[int] = []
	var queue: Array[int] = []
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_parent(i) < 0:
			queue.append(i)
	while not queue.is_empty():
		var bone: int = queue.pop_front()
		order.append(bone)
		for child in skeleton.get_bone_children(bone):
			queue.append(child)
	return order
