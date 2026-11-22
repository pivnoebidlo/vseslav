class_name MapPoints
extends Node3D
## Точки карты, с которыми можно что-то сделать (ADR-0034): выходы в другие области
## (светящееся кольцо и подпись всегда видны) и сундуки (подпись — при наведении).
## Клик попадает в StaticBody3D с метаданными "point" = "exit:<id>" или "chest:<id>".

const EXIT := "exit"
const CHEST := "chest"
const CELL := BattleGrid.CELL_SIZE_M
const EXIT_COLOR := Color(1.0, 0.85, 0.45, 0.8)

var _labels: Dictionary[String, Label3D] = {}


func build(area: AreaMap) -> void:
	for x in area.exits:
		_add(EXIT + ":" + x.id, x.at, tr(x.name_key), true)
	for box in area.containers:
		_add(CHEST + ":" + box.id, box.at, tr(box.name_key), false)


## Наведение на точку [param key] (или "" — ни на что).
func set_hovered(key: String) -> void:
	for k: String in _labels:
		if k.begins_with(CHEST + ":"):
			_labels[k].visible = k == key
		else:
			_labels[k].modulate = Color.WHITE if k == key else Color(1, 1, 1, 0.75)


static func kind_of(key: String) -> String:
	return key.get_slice(":", 0)


static func id_of(key: String) -> String:
	return key.get_slice(":", 1)


func _add(key: String, cell: Vector2i, text: String, exit: bool) -> void:
	var at := Vector3(cell.x * CELL, 0.0, cell.y * CELL)
	var body := StaticBody3D.new()
	body.set_meta("point", key)
	body.position = at + Vector3(0.0, 0.6, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL * 0.9, 1.2, CELL * 0.9)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	if exit:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.45
		torus.outer_radius = 0.6
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.15, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = EXIT_COLOR
		ring.material_override = mat
		ring.position = at + Vector3(0.0, 0.05, 0.0)
		add_child(ring)
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 30
	label.pixel_size = 0.008
	label.outline_size = 10
	label.position = at + Vector3(0.0, 1.4 if exit else 1.1, 0.0)
	label.modulate = Color(1, 1, 1, 0.75)
	label.visible = exit
	add_child(label)
	_labels[key] = label
