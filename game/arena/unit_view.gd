class_name UnitView
extends Node3D
## Фигура участника боя: капсула, подпись с именем и здоровьем, коллайдер для клика.

const TEAM_COLORS: Dictionary[String, Color] = {
	"party": Color(0.25, 0.45, 0.85),
	"bandits": Color(0.75, 0.25, 0.2),
	"beasts": Color(0.55, 0.4, 0.25),
	"nechist": Color(0.45, 0.6, 0.35),
}

var unit_id: String = ""

var _body_mat: StandardMaterial3D = StandardMaterial3D.new()
var _label: Label3D = Label3D.new()
var _base_color: Color = Color.WHITE
var _ground_y: float = 0.0


func setup(id: String, team: String) -> void:
	unit_id = id
	_base_color = TEAM_COLORS.get(team, Color.GRAY)
	_body_mat.albedo_color = _base_color

	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	mesh.mesh = capsule
	mesh.material_override = _body_mat
	mesh.position.y = 0.8
	add_child(mesh)

	var body := StaticBody3D.new()
	body.set_meta("unit_id", id)
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.7
	shape.shape = capsule_shape
	shape.position.y = 0.85
	body.add_child(shape)
	add_child(body)

	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.1
	_label.font_size = 48
	_label.pixel_size = 0.009
	_label.outline_size = 12
	_label.no_depth_test = true
	add_child(_label)


## Подпись: имя, хиты и состояния; поза — стоит, лежит (0 хитов) или погиб.
func refresh(display_name: String, c: Combatant) -> void:
	var text := "%s\n%d/%d" % [display_name, c.hp, c.max_hp]
	var conds: PackedStringArray = []
	for cond in c.conditions:
		if cond.id != Conditions.UNCONSCIOUS:
			conds.append(CombatLogFormat.condition_name(cond.id))
	if not conds.is_empty():
		text += "\n" + ", ".join(conds)
	_label.text = text
	var down := c.hp == 0
	rotation_degrees.x = 90.0 if down else 0.0
	position.y = _ground_y + (0.35 if down else 0.0)
	_label.modulate = Color(1, 1, 1, 0.35 if c.dead else 1.0)
	_body_mat.albedo_color = _base_color.darkened(0.7) if c.dead else _base_color
	if c.dead:
		for child in get_children():
			if child is StaticBody3D:
				child.queue_free()


## Высота клетки, на которой стоит фигура (лежащая фигура приподнимается от неё).
func place(at: Vector3) -> void:
	_ground_y = at.y
	position = at


func set_active(active: bool) -> void:
	_body_mat.emission_enabled = active
	_body_mat.emission = _base_color * 0.6


func flash() -> void:
	var tween := create_tween()
	tween.tween_property(_body_mat, "albedo_color", Color.WHITE, 0.08)
	tween.tween_property(_body_mat, "albedo_color", _base_color, 0.2)
