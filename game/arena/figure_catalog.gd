class_name FigureCatalog
extends RefCounted
## Облик участников боя из modules/<модуль>/models/models.json: какая модель, что в руках,
## какие анимации на какие роли. Модели грузятся только через CharacterLoader.
## Формат — ADR-0022, схема schemas/models.schema.json (ADR-0028).

const FIGURE_HUMANOID := "humanoid"
const FIGURE_BEAST := "beast"
const FIGURE_SPIRIT := "spirit"


## Описание облика одного персонажа или существа.
class Entry:
	extends RefCounted
	## Путь к GLB; пусто — простая фигура [member figure].
	var path: String = ""
	var hold: Array[String] = []
	var animations: Dictionary[String, PackedStringArray] = {}
	var figure: String = FIGURE_HUMANOID


var entries: Dictionary[String, Entry] = {}
var errors: Array[String] = []

var _profiles: Array[RigProfile] = []


static func load_dir(models_dir: String, profiles: Array[RigProfile]) -> FigureCatalog:
	var catalog := FigureCatalog.new()
	catalog._profiles = profiles
	var path := models_dir.path_join("models.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		catalog.errors.append("%s: not a JSON object" % path)
		return catalog
	var data: Dictionary = parsed
	var figures := JsonRead.get_dict(data, "figures")
	for key: Variant in figures:
		var raw: Variant = figures[key]
		if typeof(raw) != TYPE_DICTIONARY:
			catalog.errors.append("%s: %s is not an object" % [path, key])
			continue
		var d: Dictionary = raw
		catalog._add(str(key), d, models_dir)
	return catalog


## Облик из загруженных модулей (уже проверен схемой и ссылками).
static func from_content(content: ModuleContent, profiles: Array[RigProfile]) -> FigureCatalog:
	var catalog := FigureCatalog.new()
	catalog._profiles = profiles
	var ids: Array[String] = []
	ids.assign(content.figures.keys())
	ids.sort()
	for id in ids:
		catalog._add(id, content.figures[id], content.figure_dirs[id])
	return catalog


func _add(id: String, d: Dictionary, models_dir: String) -> void:
	var e := Entry.new()
	var file := JsonRead.get_str(d, "file")
	if file != "":
		if file.contains("..") or file.contains("/") or file.get_extension() != "glb":
			errors.append("%s: bad file name %s" % [id, file])
			return
		e.path = models_dir.path_join(file)
	e.figure = JsonRead.get_str(d, "figure", FIGURE_HUMANOID)
	e.hold = JsonRead.get_str_array(d, "hold")
	var anims := JsonRead.get_dict(d, "animations")
	for role: Variant in anims:
		e.animations[str(role)] = PackedStringArray(JsonRead.get_str_array(anims, str(role)))
	entries[id] = e


func entry(template_id: String) -> Entry:
	return entries.get(template_id, null)


## Загружает модель облика и прячет снаряжение, которого нет в [member Entry.hold].
## null — у облика нет модели или она не загрузилась (ошибка — в [member errors]).
func instantiate(e: Entry) -> LoadedModel:
	if e == null or e.path == "":
		return null
	var model := CharacterLoader.load_file(e.path, _profiles)
	if not model.ok():
		for err in model.errors:
			errors.append("%s: %s" % [e.path, err["key"]])
		if model.root != null:
			model.root.free()
		return null
	if model.rig != null:
		for slot_name in model.rig.attachment_slots:
			for slot in model.root.find_children(slot_name, "", true, false):
				for child in slot.get_children():
					if child is Node3D:
						(child as Node3D).visible = e.hold.has(child.name)
	return model


## Имя анимации для роли: сначала из облика, затем из профиля рига; пусто — нет такой.
static func animation_for(e: Entry, model: LoadedModel, role: String) -> String:
	if model == null or model.animation_player == null:
		return ""
	var candidates := PackedStringArray()
	if e != null and e.animations.has(role):
		candidates.append_array(e.animations[role])
	if model.rig != null and model.rig.animations.has(role):
		candidates.append_array(model.rig.animations[role])
	for name in candidates:
		if model.animation_player.has_animation(name):
			return name
	return ""
