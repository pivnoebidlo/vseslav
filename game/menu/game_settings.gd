class_name GameSettings
extends RefCounted
## Настройки игрока (ADR-0035): журнал боя, сетка на карте. Хранятся в
## user://settings.cfg (ConfigFile) отдельно от сохранений; читаются при первом
## обращении. Пока SaveStore.disabled (дымовые проверки) — на диск не пишутся.

const PATH := "user://settings.cfg"
const SECTION := "interface"

## Показывать журнал боя (по умолчанию скрыт: он нужен для отладки).
static var show_combat_log := false
## Сетка на карте вне боя.
static var show_grid := false

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	show_combat_log = _bool(cfg, "combat_log", show_combat_log)
	show_grid = _bool(cfg, "grid", show_grid)


static func save() -> void:
	if SaveStore.disabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "combat_log", show_combat_log)
	cfg.set_value(SECTION, "grid", show_grid)
	cfg.save(PATH)


## Значение из файла; не bool (файл правили руками) — значение по умолчанию.
static func _bool(cfg: ConfigFile, key: String, fallback: bool) -> bool:
	var value: Variant = cfg.get_value(SECTION, key, fallback)
	return value if value is bool else fallback
