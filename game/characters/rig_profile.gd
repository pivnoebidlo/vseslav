class_name RigProfile
extends RefCounted
## Профиль семейства ригов: как имена костей источника (KayKit, Mixamo, …)
## переводятся в имена SkeletonProfileHumanoid. Профили — данные в game/characters/rigs/.

const RIG_FILES: Array[String] = [
	"res://game/characters/rigs/humanoid.json",
	"res://game/characters/rigs/kaykit.json",
	"res://game/characters/rigs/mixamo.json",
]

var id: String = ""
var title: String = ""
## Нормализованные имена костей, по которым узнаётся риг.
var detect: Array[String] = []
## Нормализованное имя кости → имя в SkeletonProfileHumanoid.
var bones: Dictionary[String, String] = {}
## Имена уже гуманоидные: переименование не нужно, только сопоставление.
var identity: bool = false

var _strip: RegEx = null


static func from_dict(data: Dictionary) -> RigProfile:
	var p := RigProfile.new()
	p.id = JsonRead.get_str(data, "id")
	p.title = JsonRead.get_str(data, "title", p.id)
	p.identity = JsonRead.get_bool(data, "identity")
	var strip := JsonRead.get_str(data, "strip_prefix")
	if strip != "":
		p._strip = RegEx.create_from_string(strip)
	for name: Variant in JsonRead.get_array(data, "detect"):
		p.detect.append(str(name).to_lower())
	var map := JsonRead.get_dict(data, "bones")
	for key: Variant in map:
		p.bones[str(key).to_lower()] = str(map[key])
	return p


## Все профили из RIG_FILES в фиксированном порядке.
static func load_all() -> Array[RigProfile]:
	var result: Array[RigProfile] = []
	for path in RIG_FILES:
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Bad rig profile: %s" % path)
			continue
		var data: Dictionary = parsed
		result.append(from_dict(data))
	return result


## Первый профиль, все кости-признаки которого есть среди [param bone_names]; иначе null.
static func detect_profile(profiles: Array[RigProfile], bone_names: Array[String]) -> RigProfile:
	for p in profiles:
		var normalized: Dictionary[String, bool] = {}
		for name in bone_names:
			normalized[p.normalize(name)] = true
		var ok := true
		for needed in p.detect:
			if not normalized.has(needed):
				ok = false
				break
		if ok:
			return p
	return null


## Нормализация имени: нижний регистр, без префикса рига, ':' и '/' → '_'.
func normalize(bone_name: String) -> String:
	var n := bone_name.to_lower()
	if _strip != null:
		n = _strip.sub(n, "")
	return n.replace(":", "_").replace("/", "_")


## Гуманоидное имя для кости или пустая строка, если кость не сопоставлена.
func humanoid_name(bone_name: String) -> String:
	if identity:
		return bone_name
	return bones.get(normalize(bone_name), "")
