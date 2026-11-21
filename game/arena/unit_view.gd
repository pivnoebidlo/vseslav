class_name UnitView
extends Node3D
## Фигура участника боя: модель с анимациями (или простая фигура, если модели нет),
## кольцо цвета команды, подпись с именем, хитами и состояниями, коллайдер для клика.
## Анимации выбираются по ролям (idle, walk, melee, …) — FigureCatalog.animation_for.

const TEAM_COLORS: Dictionary[String, Color] = {
	"party": Color(0.25, 0.5, 0.95),
	"bandits": Color(0.85, 0.2, 0.15),
	"beasts": Color(0.9, 0.55, 0.1),
	"nechist": Color(0.6, 0.25, 0.85),
}
## Роли, которые повторяются по кругу; остальные проигрываются один раз.
const LOOPED_ROLES: Array[String] = ["idle", "walk", "downed_idle", "prone_idle"]
const POSE_IDLE := "idle"
const POSE_PRONE := "prone"
const POSE_DOWNED := "downed"
## Модели KayKit выше человека на сетке 1.5 м — уменьшаем.
const MODEL_SCALE := 0.62
const BLEND := 0.15
## Сколько ждать удара от начала анимации атаки — не дольше этого, секунд.
const MAX_IMPACT_DELAY := 0.55

var unit_id: String = ""

var _entry: FigureCatalog.Entry = null
var _model: LoadedModel = null
var _player: AnimationPlayer = null
var _figure: Node3D = Node3D.new()
var _body_mat: StandardMaterial3D = StandardMaterial3D.new()
var _ring_mat: StandardMaterial3D = StandardMaterial3D.new()
var _label: Label3D = Label3D.new()
var _base_color: Color = Color.WHITE
var _team_color: Color = Color.GRAY
var _ground_y: float = 0.0
var _pose: String = ""
var _was_reviving: bool = false


## [param model] — уже загруженная модель облика (её корень станет дочерним) или null.
func setup(id: String, team: String, entry: FigureCatalog.Entry, model: LoadedModel) -> void:
	unit_id = id
	_entry = entry
	_team_color = TEAM_COLORS.get(team, Color.GRAY)
	add_child(_figure)
	_add_ring()
	if model != null:
		_model = model
		_player = model.animation_player
		model.root.scale = Vector3.ONE * MODEL_SCALE
		_figure.add_child(model.root)
		_setup_loops()
	else:
		_add_simple_figure(entry.figure if entry != null else FigureCatalog.FIGURE_HUMANOID)
	_add_collider()

	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.0
	_label.font_size = 36
	_label.pixel_size = 0.009
	_label.outline_size = 12
	_label.no_depth_test = true
	add_child(_label)
	_set_pose(POSE_IDLE, false)


## Подпись и поза по состоянию участника.
func refresh(display_name: String, c: Combatant) -> void:
	var conds: PackedStringArray = []
	for cond in c.conditions:
		if cond.id != Conditions.UNCONSCIOUS:
			conds.append(CombatLogFormat.condition_name(cond.id))
	var ratio := float(c.hp) / float(maxi(c.max_hp, 1))
	var hp_color := Color(0.45, 0.95, 0.45)
	if ratio <= 0.25:
		hp_color = Color(1.0, 0.4, 0.35)
	elif ratio <= 0.5:
		hp_color = Color(1.0, 0.85, 0.3)
	var text := "%s\n%d/%d" % [display_name, c.hp, c.max_hp]
	if not conds.is_empty():
		text += "\n" + ", ".join(conds)
	_label.text = text
	_label.modulate = Color(1, 1, 1, 0.35) if c.dead else hp_color.lerp(Color.WHITE, 0.35)

	var pose := POSE_IDLE
	if c.hp == 0 or c.dead:
		pose = POSE_DOWNED
	elif c.has_condition(Conditions.PRONE):
		pose = POSE_PRONE
	_set_pose(pose, true, _was_reviving and pose == POSE_IDLE)
	_was_reviving = c.reviving
	_ring_mat.albedo_color = _team_color.darkened(0.6) if c.dead else _team_color
	if c.dead:
		_body_mat.albedo_color = _base_color.darkened(0.7)
		for child in get_children():
			if child is StaticBody3D:
				child.queue_free()


## Высота клетки, на которой стоит фигура.
func place(at: Vector3) -> void:
	_ground_y = at.y
	position = at


## Повернуть лицом к точке (по горизонтали).
func face(at: Vector3) -> void:
	var d := at - position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	_figure.rotation.y = atan2(d.x, d.z)


func set_active(active: bool) -> void:
	_ring_mat.emission_enabled = active
	_ring_mat.emission = _team_color * 0.9
	_body_mat.emission_enabled = active
	_body_mat.emission = _base_color * 0.5


## Шаги: анимация ходьбы, пока [param on], затем — текущая поза.
func walk(on: bool) -> void:
	if _player == null:
		return
	if on:
		_play_role("walk", "")
	else:
		_play_role(_pose_loop(), "")


## Разовая анимация роли с возвратом в позу. Возвращает, сколько ждать «удара», с.
func play(role: String) -> float:
	if _player == null:
		_pulse()
		return 0.2
	var name := FigureCatalog.animation_for(_entry, _model, role)
	if name == "":
		return 0.2
	_play_role(role, _pose_loop())
	return minf(_player.get_animation(name).length * 0.5, MAX_IMPACT_DELAY)


## Попадание по фигуре: вздрагивает (если стоит).
func flash() -> void:
	if _pose == POSE_IDLE:
		play("hit")
	if _player == null:
		_pulse()


# --- Внутреннее ----------------------------------------------------------------


func _set_pose(pose: String, animate: bool, reviving: bool = false) -> void:
	if pose == _pose:
		return
	var previous := _pose
	_pose = pose
	if _player == null:
		_apply_simple_pose()
		return
	var loop := _pose_loop()
	if not animate:
		_play_role(loop, "")
		return
	match pose:
		POSE_DOWNED:
			_play_role("downed", loop)
		POSE_PRONE:
			_play_role("prone", loop)
		_:
			if previous == POSE_DOWNED or previous == POSE_PRONE:
				_play_role("revive" if reviving else "stand_up", loop)
			else:
				_play_role(loop, "")


func _pose_loop() -> String:
	match _pose:
		POSE_DOWNED:
			return "downed_idle"
		POSE_PRONE:
			return "prone_idle"
	return "idle"


## Играет роль [param role]; если задана [param then] — следом её (по кругу).
func _play_role(role: String, then: String) -> void:
	var name := FigureCatalog.animation_for(_entry, _model, role)
	if name == "":
		return
	_player.clear_queue()
	_player.play(name, BLEND)
	if then != "":
		var next := FigureCatalog.animation_for(_entry, _model, then)
		if next != "" and next != name:
			_player.queue(next)


func _setup_loops() -> void:
	if _player == null:
		return
	for role in LOOPED_ROLES:
		var name := FigureCatalog.animation_for(_entry, _model, role)
		if name != "":
			_player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	for role: String in ["downed", "prone", "stand_up", "revive", "hit", "melee", "ranged"]:
		var name := FigureCatalog.animation_for(_entry, _model, role)
		if name != "" and not LOOPED_ROLES.has(role):
			_player.get_animation(name).loop_mode = Animation.LOOP_NONE


func _add_ring() -> void:
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.04
	ring.mesh = disc
	_ring_mat.albedo_color = _team_color
	ring.material_override = _ring_mat
	ring.position.y = 0.03
	add_child(ring)


func _add_collider() -> void:
	var body := StaticBody3D.new()
	body.set_meta("unit_id", unit_id)
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.7
	shape.shape = capsule_shape
	shape.position.y = 0.85
	body.add_child(shape)
	add_child(body)


## Простая фигура без модели: человек — капсула, зверь — приземистое тело с головой,
## дух — светлый вытянутый конус.
func _add_simple_figure(kind: String) -> void:
	_base_color = _team_color.lerp(Color.WHITE, 0.15)
	match kind:
		FigureCatalog.FIGURE_BEAST:
			_base_color = Color(0.45, 0.42, 0.4)
			var body := BoxMesh.new()
			body.size = Vector3(0.45, 0.45, 1.0)
			_add_part(body, Vector3(0, 0.55, 0))
			var head := BoxMesh.new()
			head.size = Vector3(0.3, 0.3, 0.4)
			_add_part(head, Vector3(0, 0.8, 0.6))
			for x: float in [-0.15, 0.15]:
				for z: float in [-0.35, 0.35]:
					var leg := BoxMesh.new()
					leg.size = Vector3(0.1, 0.35, 0.1)
					_add_part(leg, Vector3(x, 0.17, z))
		FigureCatalog.FIGURE_SPIRIT:
			_base_color = Color(0.95, 0.93, 0.8)
			var robe := CylinderMesh.new()
			robe.top_radius = 0.12
			robe.bottom_radius = 0.45
			robe.height = 1.6
			_add_part(robe, Vector3(0, 0.8, 0))
			var head := SphereMesh.new()
			head.radius = 0.17
			head.height = 0.34
			_add_part(head, Vector3(0, 1.75, 0))
		_:
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.35
			capsule.height = 1.6
			_add_part(capsule, Vector3(0, 0.8, 0))
	_body_mat.albedo_color = _base_color


func _add_part(mesh: Mesh, at: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _body_mat
	part.position = at
	_figure.add_child(part)


func _apply_simple_pose() -> void:
	var down := _pose != POSE_IDLE
	_figure.rotation_degrees.x = 0.0
	_figure.rotation_degrees.z = 90.0 if down else 0.0
	_figure.position.y = 0.3 if down else 0.0


func _pulse() -> void:
	var tween := create_tween()
	tween.tween_property(_body_mat, "albedo_color", Color.WHITE, 0.08)
	tween.tween_property(_body_mat, "albedo_color", _base_color, 0.2)
