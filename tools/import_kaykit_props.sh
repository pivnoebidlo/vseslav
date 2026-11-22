#!/usr/bin/env bash
# Импорт моделей окружения KayKit (CC0) в modules/base/props: клонирует наборы во
# временную папку и переводит выбранные .gltf в .glb (tools/convert_gltf.gd).
# Список и лицензии — CREDITS.md. Использование: tools/import_kaykit_props.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
out=modules/base/props
mkdir -p "$out"

git clone -q --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0.git "$tmp/medieval"
git clone -q --depth 1 https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0.git "$tmp/halloween"
m="$tmp/medieval/addons/kaykit_medieval_hexagon_pack/Assets/gltf"
h="$tmp/halloween/addons/kaykit_halloween_bits/Assets/gltf"

args=()
add() { args+=("$1" "$out/$2.glb"); }
add "$m/buildings/yellow/building_home_A_yellow.gltf" house_a
add "$m/buildings/yellow/building_home_B_yellow.gltf" house_b
add "$m/buildings/red/building_home_A_red.gltf" house_c
add "$m/buildings/yellow/building_tavern_yellow.gltf" house_large
add "$m/buildings/yellow/building_blacksmith_yellow.gltf" smithy
add "$m/buildings/yellow/building_well_yellow.gltf" well
add "$m/buildings/neutral/fence_wood_straight.gltf" fence_wood
add "$m/decoration/nature/tree_single_A.gltf" tree_a
add "$m/decoration/nature/tree_single_B.gltf" tree_b
add "$m/decoration/nature/rock_single_A.gltf" rock_a
add "$m/decoration/nature/rock_single_B.gltf" rock_b
add "$m/decoration/props/tent.gltf" tent
add "$m/decoration/props/barrel.gltf" barrel
add "$m/decoration/props/crate_A_small.gltf" crate
add "$m/decoration/props/sack.gltf" sack
add "$m/decoration/props/wheelbarrow.gltf" wheelbarrow
add "$m/decoration/props/resource_lumber.gltf" lumber
add "$m/decoration/props/weaponrack.gltf" weaponrack
add "$h/grave_A.gltf" grave_a
add "$h/grave_B.gltf" grave_b
add "$h/gravestone.gltf" gravestone
add "$h/gravemarker_A.gltf" gravemarker_a
add "$h/gravemarker_B.gltf" gravemarker_b
add "$h/crypt.gltf" crypt
add "$h/tree_dead_medium.gltf" tree_dead_a
add "$h/tree_dead_large.gltf" tree_dead_b

"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s res://tools/convert_gltf.gd -- "${args[@]}"
