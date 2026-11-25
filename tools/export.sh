#!/usr/bin/env bash
# Сборка релизных билдов. Использование: tools/export.sh [macOS|Windows|Linux ...] (по умолчанию все).
# Нужны шаблоны экспорта той же версии Godot (ADR-0015).
# macOS-билд подписан ad-hoc: на другом Mac при первом запуске — правый клик → «Открыть».
# Дымовая проверка собранного билда: <бинарь> -- --smoke --seed=42 --screenshot=/путь/shot.png
# (как у godot из исходников, разделитель «--» обязателен — без него откроется меню).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
presets=("$@")
[[ ${#presets[@]} -eq 0 ]] && presets=(macOS Windows Linux)

"$GODOT" --headless --import >/dev/null 2>&1 || true

for preset in "${presets[@]}"; do
  path="$(awk -v name="$preset" '
    $0 ~ /^name=/ { gsub(/^name="|"$/, ""); current = $0 }
    $0 ~ /^export_path=/ && current == name { gsub(/^export_path="|"$/, ""); print; exit }
  ' export_presets.cfg)"
  if [[ -z "$path" ]]; then
    echo "Нет пресета экспорта: $preset" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$path")"
  echo "==> $preset → $path"
  "$GODOT" --headless --export-release "$preset" "$path"
done
