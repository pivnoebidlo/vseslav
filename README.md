# Vseslav (рабочее название)

Однопользовательская 3D RPG на Руси времён Всеслава Полоцкого (XI век) — летописная хроника, в которой нечисть из сказок реальна. Windows, Linux и macOS: realtime-исследование, пошаговый бой на квадратной сетке по переработанным правилам d20, собственный редактор приключений и модули контента.

Движок — Godot 4.x, язык — строго типизированный GDScript.

> Статус: проектирование. Кода пока нет, текущий этап — [этап 0](docs/ROADMAP.md#этап-0--каркас-и-спайки-12-недели).

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

- Godot 4.x (версия — [OPEN_QUESTIONS](docs/OPEN_QUESTIONS.md) №1), доступный как `godot` или через `GODOT=/путь/к/godot`.
- Python 3 + `pip install "gdtoolkit==4.*"`.
- Git LFS.
- Blender — для работы с моделями.

Правила игры основаны на System Reference Document 5.x, распространяемом под [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/). Проект не связан с Wizards of the Coast.
