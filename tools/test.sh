#!/usr/bin/env bash
# Запуск тестов GUT headless. Использование: tools/test.sh [res-относительная папка, по умолчанию tests]
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
DIR="${1:-tests}"

if [[ ! -f project.godot ]]; then
  echo "project.godot не найден — проект ещё не создан (этап 0)." >&2
  exit 1
fi
if [[ ! -f addons/gut/gut_cmdln.gd ]]; then
  echo "GUT не установлен в addons/gut." >&2
  exit 1
fi

# Импорт ресурсов, чтобы class_name и ассеты были доступны в headless-режиме.
"$GODOT" --headless --import >/dev/null 2>&1 || true

"$GODOT" --headless -s addons/gut/gut_cmdln.gd \
  -gdir="res://${DIR#res://}" -ginclude_subdirs -gprefix=test_ -gexit
