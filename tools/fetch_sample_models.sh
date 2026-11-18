#!/usr/bin/env bash
# Скачивает образцы моделей для просмотрщика (KayKit, CC0) и создаёт синтетическую
# модель с ригом Mixamo. Модели кладутся в пользовательскую папку игры, не в репозиторий.
# Использование: tools/fetch_sample_models.sh [папка]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

case "$(uname -s)" in
  Darwin) default_dir="$HOME/Library/Application Support/Godot/app_userdata/Vseslav/models" ;;
  Linux) default_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Vseslav/models" ;;
  *) default_dir="$APPDATA/Godot/app_userdata/Vseslav/models" ;;
esac
dir="${1:-$default_dir}"
mkdir -p "$dir"

base=https://raw.githubusercontent.com/KayKit-Game-Assets
# KayKit: Adventurers и Skeletons, CC0 (Kay Lousberg, kaylousberg.com).
curl -sfL -o "$dir/Knight.glb" \
  "$base/KayKit-Character-Pack-Adventures-1.0/main/addons/kaykit_character_pack_adventures/Characters/gltf/Knight.glb"
curl -sfL -o "$dir/Skeleton_Warrior.glb" \
  "$base/KayKit-Character-Pack-Skeletons-1.0/main/addons/kaykit_character_pack_skeletons/Characters/gltf/Skeleton_Warrior.glb"

"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s res://tools/make_sample_models.gd -- "$dir"

echo "Модели в: $dir"
ls -1 "$dir"
