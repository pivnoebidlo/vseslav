class_name Retarget
extends RefCounted
## Ретаргетинг во время игры: анимации одного рига проигрываются на модели с другим.
## Схема: модель цели остаётся как есть, внутрь неё кладётся невидимый источник
## с AnimationPlayer, а HumanoidRetarget переносит его позы на скелет цели.
## Оба рига должны быть распознаны (кости переименованы в SkeletonProfileHumanoid).


## Возвращает true, если цель подключена. После вызова модель цели — это [param target].root,
## анимации запускаются через [param source].animation_player.
static func attach(source: LoadedModel, target: LoadedModel) -> bool:
	if source.skeleton == null or target.skeleton == null:
		return false
	if source.rig == null or target.rig == null:
		return false
	if source.animation_player == null:
		return false
	for mesh in source.root.find_children("*", "MeshInstance3D", true, false):
		(mesh as Node3D).visible = false
	if target.animation_player != null:
		target.animation_player.active = false
	source.root.name = "AnimationSource"
	target.root.add_child(source.root)

	var retarget := HumanoidRetarget.new()
	retarget.name = "Retarget"
	target.root.add_child(retarget)
	retarget.setup(source.skeleton, target.skeleton)
	return true
