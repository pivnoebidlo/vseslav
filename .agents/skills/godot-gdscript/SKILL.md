---
name: godot-gdscript
description: Правила написания строго типизированного GDScript для Godot 4 в этом проекте и таблица ловушек Godot 3 → 4. Использовать при написании или правке любого .gd файла.
---

# GDScript в проекте Vseslav

## Перед написанием кода

1. Проверь версию Godot в `project.godot` (`config/features`). Не используй API, которого в этой версии нет. Если не уверен, что метод существует, — проверь документацию этой версии, не полагайся на память.
2. Определи слой: `core/` (чистая логика), `game/` (ноды), `editor/` (логика редактора), `addons/vseslav_editor/` (UI плагина). Правила зависимостей — в `AGENTS.md`.

## Обязательный стиль

```gdscript
class_name AttackResolver
extends RefCounted
## Разрешает атаку по правилам ruleset. Документирующие комментарии — через ##.

const CRIT_THRESHOLD: int = 20

var _rng: Rng


func _init(rng: Rng) -> void:
	_rng = rng


func resolve(attacker: Creature, target: Creature, advantage: int) -> AttackResult:
	var roll: int = _roll_d20(advantage)
	var total := roll + attacker.attack_bonus()  # := только когда тип очевиден
	return AttackResult.new(roll, total, total >= target.armor_class())
```

- Типизировано всё: переменные, параметры, возвращаемые значения (`-> void` тоже), массивы (`Array[Creature]`).
- Отступы — табы (как в Godot); порядок в файле — как в официальном style guide: `class_name`, `extends`, doc, сигналы, enum, константы, `@export`, публичные, приватные (`_`), `@onready`, `_init`, `_ready`, прочие встроенные, публичные методы, приватные.
- Классы ядра наследуют `RefCounted`, не `Node`. Состояние сериализуется через `func to_dict() -> Dictionary` и `static func from_dict(data: Dictionary) -> T`.
- Сигналы — для `game/` и UI. В `core/` результаты возвращаются значениями/списками событий-результатов.
- Не оставляй `print()` в коммите; для логов — `push_warning()` / `push_error()` или наш логгер, когда появится.

## Строгий режим проекта: что он не пропускает

Эти ошибки уже ловились на этапе 0 — пиши сразу правильно:

- `for x in untyped_array:` — ошибка «iterator variable has no static type». Пиши `for x: String in ...` или итерируй типизированный массив.
- `int(variant)`, `bool(variant)`, `load(variant)` — ошибка «requires the subtype». Данные из JSON читай через `JsonRead` (`core/data/json_read.gd`): `JsonRead.get_int(data, "hp")`, `JsonRead.get_array(...)`, `JsonRead.to_vec2i(...)`.
- Вызов метода у `Variant` (`data["x"].size()`) — ошибка. Сначала присвой в типизированную переменную: `var rows: Array = data["map"]`.
- Присвоение `Variant` в типизированную переменную (`var d: Dictionary = parsed`) — допустимо: проверка будет во время выполнения.
- Новый `class_name` не виден другим скриптам, пока не обновлён кэш классов: `godot --headless --import` (`tools/test.sh` делает это сам).

## Ловушки, которые ломают код молча

- **JSON-числа приходят как `float`.** `JSON.parse_string("{\"hp\": 7}")["hp"]` — это `7.0`. В `from_dict` всегда явно приводи: `int(data["hp"])`, и проверяй наличие ключа.
- **Целочисленное деление округляет к нулю**, а не вниз: `-7 / 2 == -3`. Для правил используй хелпер `IntMath.floor_div(a, b)`.
- Деление `int / int` даёт предупреждение `integer_division` — если оно намеренное, используй хелпер, а не глушение.
- `Dictionary` сохраняет порядок вставки, но в `core/` порядок не должен влиять на результат — сортируй ключи.
- `==` между `int` и `float` работает, но `typeof` разный — в сравнении данных из JSON приводи типы заранее.
- `await` в `core/` не используется.
- `Array` и `Dictionary` передаются по ссылке; при копировании состояния используй `duplicate(true)`.

## Godot 3 → Godot 4 (агенты часто путают)

| Не пиши (Godot 3) | Пиши (Godot 4) |
|---|---|
| `yield(obj, "sig")` | `await obj.sig` |
| `export var x = 1` | `@export var x: int = 1` |
| `onready var n = $N` | `@onready var n: Node3D = $N` |
| `tool` | `@tool` |
| `Spatial`, `KinematicBody`, `RigidBody` | `Node3D`, `CharacterBody3D`, `RigidBody3D` |
| `move_and_slide(vel, up)` | `velocity = vel` и `move_and_slide()` |
| `scene.instance()` | `scene.instantiate()` |
| `connect("sig", self, "_on_sig")` | `sig.connect(_on_sig)` |
| `emit_signal("sig", a)` | `sig.emit(a)` |
| `funcref(obj, "m")` | `Callable(obj, "m")` или `obj.m` |
| `var x setget set_x` | `var x: int: set = _set_x` / блок `set(value):` |
| `File.new()`, `Directory.new()` | `FileAccess.open()`, `DirAccess.open()` |
| `to_json()`, `parse_json()` | `JSON.stringify()`, `JSON.parse_string()` (или `JSON.new().parse()` ради текста ошибки) |
| `PoolStringArray`, `PoolIntArray` | `PackedStringArray`, `PackedInt32Array` |
| `.empty()` | `.is_empty()` |
| `deg2rad`, `str2var`, `rand_range` | `deg_to_rad`, `str_to_var`, `randf_range` (в `core/` запрещён) |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` (в `core/` запрещён) |
| `Engine.editor_hint` | `Engine.is_editor_hint()` |
| `change_scene("res://...")` | `change_scene_to_file("res://...")` |
| `Transform`, `Quat` | `Transform3D`, `Quaternion` |
| `BUTTON_LEFT`, `KEY_*` как глобалы | `MOUSE_BUTTON_LEFT`, `KEY_*` (enum `Key`) |

## Перед сдачей

`tools/lint.sh` и `tools/test.sh` зелёные; новых предупреждений в выводе Godot нет.
