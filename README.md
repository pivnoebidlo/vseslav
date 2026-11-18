# Vseslav (рабочее название)

Однопользовательская 3D RPG на Руси времён Всеслава Полоцкого (XI век) — летописная хроника, в которой нечисть из сказок реальна. Windows, Linux и macOS: realtime-исследование, пошаговый бой на квадратной сетке по переработанным правилам d20, собственный редактор приключений и модули контента.

Движок — Godot 4.x, язык — строго типизированный GDScript.

> Статус: этап 0 закрыт, дальше — этап 1, боевой срез ([ROADMAP](docs/ROADMAP.md)). Есть тестовая арена с пошаговым боем и просмотрщик моделей с ретаргетингом анимаций.

## Запуск

```sh
godot --path .                 # тестовая арена: ЛКМ по клетке — идти, по врагу — атаковать
tools/fetch_sample_models.sh   # скачать образцы моделей в пользовательскую папку
godot --path . res://game/spikes/model_viewer.tscn   # просмотр моделей и ретаргетинг анимаций
tools/test.sh                  # тесты
tools/lint.sh                  # линтер
tools/export.sh                # сборки для macOS, Windows, Linux в build/
```

## Документы

| Документ | Что внутри |
|---|---|
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | Что за игра: сеттинг, тон, классы, бестиарий |
| [docs/SPEC.md](docs/SPEC.md) | Техническое задание |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Этапы и критерии приёмки |
| [docs/adr/](docs/adr/) | Принятые решения и их причины |
| [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md) | Что ещё надо решить |
| [docs/LICENSING.md](docs/LICENSING.md) | Что можно и нельзя брать из чужого контента |
| [AGENTS.md](AGENTS.md) | Инструкции для AI-агентов |

## Как мы работаем

1. Задача берётся из текущего этапа ROADMAP.
2. Код пишет агент; он следует [AGENTS.md](AGENTS.md) и скилам в `.agents/skills/`.
3. Любое изменение проходит тесты и линт (`tools/test.sh`, `tools/lint.sh`) и ревью человеком.
4. Новое решение → ADR + обновление SPEC в том же PR.

## Требования для разработки

- Godot 4.7.2 ([ADR-0015](docs/adr/0015-toolchain-versions.md)), доступный как `godot` или через `GODOT=/путь/к/godot`, и шаблоны экспорта той же версии (для сборок). На macOS: `brew install --cask godot`.
- gdtoolkit 4.x: `brew install gdtoolkit` или `pip install "gdtoolkit==4.*"`.
- Git LFS.
- Blender — для работы с моделями.

## Лицензия

Код — [MIT](LICENSE). Контент (сюжет, тексты, правила-данные, уровни, арт, звук) — [CC BY-SA 4.0](LICENSES/CC-BY-SA-4.0.txt). Подробности — [LICENSES/README.md](LICENSES/README.md).

Правила игры основаны на System Reference Document 5.x от Wizards of the Coast, распространяемом под [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Проект не связан с Wizards of the Coast.
