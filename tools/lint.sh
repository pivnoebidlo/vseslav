#!/usr/bin/env bash
# Линт и проверка форматирования GDScript (gdtoolkit 4.x: pip install "gdtoolkit==4.*").
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=()
for d in core game editor addons/vseslav_editor tests tools; do
  [[ -d "$d" ]] && dirs+=("$d")
done

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "Нет папок с кодом — нечего проверять."
  exit 0
fi

gdlint "${dirs[@]}"
gdformat --check "${dirs[@]}"
