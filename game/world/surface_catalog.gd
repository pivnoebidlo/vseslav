class_name SurfaceCatalog
extends RefCounted
## Поверхности земли и пола из модулей (surfaces/surfaces.json, ADR-0036): текстуры
## цвета, нормалей и шероховатости. Модуль — недоверенные данные: только PNG, размер
## файла и стороны ограничены, сторона — степень двойки. Ошибки — в [member errors],
## поверхность с ошибкой не используется (земля рисуется цветом).

const MAX_BYTES := 16 * 1024 * 1024
const MAX_SIDE := 2048
const DEFAULT_TILE := 3.0


## Загруженная поверхность; [member normal] и [member roughness] могут быть null.
class Surface:
	extends RefCounted
	var color: Texture2D
	var normal: Texture2D
	var roughness: Texture2D
	var tile := DEFAULT_TILE


var errors: Array[String] = []

var _data: Dictionary[String, Dictionary] = {}
var _dirs: Dictionary[String, String] = {}
var _loaded: Dictionary[String, Surface] = {}


static func from_content(content: ModuleContent) -> SurfaceCatalog:
	var c := SurfaceCatalog.new()
	c._data = content.surfaces
	c._dirs = content.surface_dirs
	return c


## Поверхность по id (грузится при первом обращении); null — нет или не загрузилась.
func get_surface(id: String) -> Surface:
	if id == "" or not _data.has(id):
		return null
	if _loaded.has(id):
		return _loaded[id]
	var d := _data[id]
	var s := Surface.new()
	s.color = _texture(id, d, "color")
	s.normal = _texture(id, d, "normal")
	s.roughness = _texture(id, d, "roughness")
	var tile: Variant = d.get("tile", DEFAULT_TILE)
	if tile is float or tile is int:
		s.tile = tile
	if s.color == null:
		s = null
	_loaded[id] = s
	return s


func _texture(id: String, d: Dictionary, key: String) -> Texture2D:
	var file := JsonRead.get_str(d, key)
	if file == "":
		return null
	var path := _dirs[id].path_join(file)
	var tex := load_png(path)
	if tex == null:
		errors.append("%s: not loaded (PNG up to %d px, sides a power of two)" % [path, MAX_SIDE])
	return tex


## PNG из модуля с проверкой размера; null — не PNG, слишком большой или сторона
## не степень двойки.
static func load_png(path: String) -> ImageTexture:
	if path.get_extension().to_lower() != "png" or not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	var w := img.get_width()
	var h := img.get_height()
	if w > MAX_SIDE or h > MAX_SIDE or not _pow2(w) or not _pow2(h):
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _pow2(n: int) -> bool:
	return n > 0 and (n & (n - 1)) == 0
