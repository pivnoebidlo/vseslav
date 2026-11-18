---
name: testing
description: Как писать и запускать тесты GUT в проекте: unit-тесты ядра, интеграционные тесты модулей и сейвов, golden-реплеи боёв, подставной RNG. Использовать при любом изменении в core/ или editor/ и при исправлении багов.
---

# Тесты

## Запуск

```sh
tools/test.sh                    # все тесты
tools/test.sh tests/unit/rules   # подпапка
```

Скрипт импортирует проект headless и запускает GUT (`addons/gut/gut_cmdln.gd`). Ненулевой код выхода = провал.

**Важно:** сам GUT пропускает тестовый файл с ошибкой разбора и всё равно пишет «All tests passed». `tools/test.sh` дополнительно падает, если в выводе есть `SCRIPT ERROR`, `Parse Error` или `Ignoring script`. Не запускай GUT в обход скрипта и проверяй число `Scripts` в сводке.

## Структура

```
tests/
  unit/<зеркало core/ или editor/>/test_<класс>.gd
  integration/test_<сценарий>.gd     загрузка модулей, сейвы, переходы режимов
  golden/<name>.json                 записанные реплеи
  golden/test_golden_replays.gd
  fixtures/                          мини-модули, карты, существа
```

```gdscript
extends GutTest


func test_natural_20_always_hits() -> void:
	var rng := StubRng.new([20])
	var result := AttackResolver.new(rng).resolve(Fixtures.goblin(), Fixtures.armored_knight(), 0)
	assert_true(result.hit)
	assert_true(result.critical)
```

## Правила

- Любое изменение в `core/` и `editor/` — с тестами. Баг-фикс — сначала падающий тест.
- Помощники: `tests/helpers/stub_rng.gd` (`StubRng`), `tests/helpers/combat_sim.gd` (`CombatSim`: прогон боя ИИ, сохранение через JSON).
- Случайность в unit-тестах — `StubRng` с заранее заданными бросками, а не `Rng` с seed, чтобы тест читался.
- Проверяй граничные случаи d20: натуральные 1 и 20, преимущество + помеха одновременно, нулевой/отрицательный урон, сопротивление/уязвимость, смерть на 0 HP, дубли состояний.
- Сериализация: для каждого `to_dict()` — тест «туда и обратно» (`from_dict(to_dict(x))` равно `x`), включая данные после `JSON.stringify` → `JSON.parse_string` (ловит int→float).
- Тесты не зависят от порядка, от времени и друг от друга; не пишут вне `user://test_tmp/`.
- Тесты `game/` — только на логику, которую нельзя вынести в `core/`; визуал и «ощущение» проверяет человек.

## Golden-реплеи

Файл `tests/golden/<name>.json`: `ruleset`, `seed`, начальное состояние (или ссылка на фикстуру), список команд, ожидаемое итоговое состояние (`to_dict()`).

- Запись golden: `tools/record_golden.sh` (сейчас — бой ИИ против ИИ на `modules/spike/arena.json`, seed 42).
- Падение golden-теста означает, что изменился детерминированный результат. **Не перезаписывай ожидание автоматически.** Выясни причину; если изменение намеренное (поменяли правило), обнови golden в том же коммите и объясни в описании.
- Новая механика боя → добавь или расширь golden-реплей, где она участвует.
