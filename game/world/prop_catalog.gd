class_name PropCatalog
extends RefCounted
## Модели окружения из модулей (props/props.json, ADR-0033). Каждая модель грузится
## один раз через CharacterLoader и разбирается на меши с их положением — их размножает
## MultiMesh в AreaView, поэтому сотни деревьев стоят как одна отрисовка на меш.

const SPIN_NONE := "none"
const SPIN_QUARTER := "quarter"
const SPIN_FREE := "free"


## Разобранная модель: меши, их положение в модели и габариты.
class Prop:
	extends RefCounted
	var meshes: Array[Mesh] = []
	var transforms: Array[Transform3D] = []
	var aabb := AABB()
	var fit := 1.0
	var jitter := 0.0
	var spin := SPIN_NONE


var errors: Array[String] = []

var _data: Dictionary[String, Dictionary] = {}
var _dirs: Dictionary[String, String] = {}
var _loaded: Dictionary[String, Prop] = {}


static func from_content(content: ModuleContent) -> PropCatalog:
	var c := PropCatalog.new()
	c._data = content.props
	c._dirs = content.prop_dirs
	return c


func has(id: String) -> bool:
	return _data.has(id)


## Модель по id (загружается при первом обращении); null — нет или не загрузилась.
func get_prop(id: String) -> Prop:
	if _loaded.has(id):
		return _loaded[id]
	if not _data.has(id):
		return null
	var d := _data[id]
	var path := _dirs[id].path_join(JsonRead.get_str(d, "file"))
	var profiles: Array[RigProfile] = []
	var model := CharacterLoader.load_file(path, profiles)
	if not model.ok():
		for err in model.errors:
			errors.append("%s: %s" % [path, err["key"]])
		if model.root != null:
			model.root.free()
		_loaded[id] = null
		return null
	var p := Prop.new()
	p.fit = _float(d, "fit", 1.0)
	p.jitter = _float(d, "jitter", 0.0)
	p.spin = JsonRead.get_str(d, "spin", SPIN_NONE)
	var first := true
	for m in _meshes(model.root, Transform3D.IDENTITY):
		var mi: MeshInstance3D = m[0]
		var xf: Transform3D = m[1]
		p.meshes.append(mi.mesh)
		p.transforms.append(xf)
		var box := xf * mi.mesh.get_aabb()
		p.aabb = box if first else p.aabb.merge(box)
		first = false
	model.root.free()
	_loaded[id] = p
	return p


## Дробное число из данных облика (в правилах ядра дробей нет — здесь только вид).
static func _float(d: Dictionary, key: String, default: float) -> float:
	var v: Variant = d.get(key, default)
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return default
	var f: float = v
	return f


func _meshes(node: Node, parent: Transform3D) -> Array[Array]:
	var out: Array[Array] = []
	var xf := parent
	var n3 := node as Node3D
	if n3 != null:
		xf = parent * n3.transform
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null and mi.visible:
		out.append([mi, xf])
	for child in node.get_children():
		out.append_array(_meshes(child, xf))
	return out
