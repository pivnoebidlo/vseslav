# Благодарности и чужие материалы

Правила — [docs/LICENSING.md](docs/LICENSING.md). Каждый внешний материал записывается здесь в том же коммите, в котором добавлен.

## Правила игры

This work includes material from the System Reference Document 5.2 ("SRD 5.2") by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2 is licensed under the Creative Commons Attribution 4.0 International License.

## 3D-модели

Временные фигуры тестовых боёв (фэнтезийный облик — до своих моделей эпохи).

| Файлы | Автор | Источник | Лицензия | Проверено |
|---|---|---|---|---|
| `modules/base/models/knight.glb`, `mage.glb`, `rogue.glb`, `rogue_hooded.glb`, `barbarian.glb` | Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | [KayKit Character Pack: Adventurers 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) (`Characters/gltf`, `LICENSE.txt`) | CC0 1.0 | 2026-11-21 |
| `modules/base/models/skeleton_warrior.glb` | Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | [KayKit Character Pack: Skeletons 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) (`Characters/gltf`, `LICENSE.txt`) | CC0 1.0 | 2026-11-21 |

Файлы переименованы в `snake_case`, содержимое не менялось. Атрибуция для CC0 не обязательна, но мы её оставляем.

Окружение карты ([ADR-0033](docs/adr/0033-environment-props.md)): `.gltf` переведены в `.glb` скриптом `tools/import_kaykit_props.sh` (геометрия и текстура не менялись), имена — наши.

| Файлы | Автор | Источник | Лицензия | Проверено |
|---|---|---|---|---|
| `modules/base/props/`: `house_a`, `house_b`, `house_c`, `house_large`, `smithy`, `well`, `fence_wood`, `tree_a`, `tree_b`, `rock_a`, `rock_b`, `tent`, `barrel`, `crate`, `sack`, `wheelbarrow`, `lumber`, `weaponrack` (`.glb`) | Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | [KayKit Medieval Hexagon Pack 1.0](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0) (`Assets/gltf`, `LICENSE.txt`) | CC0 1.0 | 2026-11-22 |
| `modules/base/props/`: `grave_a`, `grave_b`, `gravestone`, `gravemarker_a`, `gravemarker_b`, `crypt`, `tree_dead_a`, `tree_dead_b` (`.glb`) | Kay Lousberg ([kaylousberg.com](https://www.kaylousberg.com)) | [KayKit Halloween Bits 1.0](https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0) (`Assets/gltf`, `LICENSE.txt`) | CC0 1.0 | 2026-11-22 |

## Инструменты

- [GUT](https://github.com/bitwes/Gut) — тесты, MIT (`addons/gut`, только для разработки, в сборку не входит).
