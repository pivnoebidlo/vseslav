#!/usr/bin/env bash
# Запуск тестов GUT headless. Использование: tools/test.sh [папка, по умолчанию tests]
# Провал, если: упал тест, или в выводе есть ошибка скрипта / пропущенный тестовый файл
# (GUT по умолчанию пропускает файл с ошибкой разбора и всё равно пишет «All tests passed»).
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
DIR="${1:-tests}"

if [[ ! -f project.godot ]]; then
  echo "project.godot не найден." >&2
  exit 1
fi
if [[ ! -f addons/gut/gut_cmdln.gd ]]; then
  echo "GUT не установлен в addons/gut." >&2
  exit 1
fi

# Импорт: обновляет кэш class_name и ресурсы для headless-режима.
"$GODOT" --headless --import >/dev/null 2>&1 || true

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

"$GODOT" --headless -s addons/gut/gut_cmdln.gd \
  -gdir="res://${DIR#res://}" -ginclude_subdirs -gprefix=test_ -gexit 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

if grep -q -e "SCRIPT ERROR" -e "Parse Error" -e "Ignoring script" "$LOG"; then
  echo "" >&2
  echo "ОШИБКА: в тестах или коде есть ошибки скриптов (см. SCRIPT ERROR / Ignoring script выше)." >&2
  exit 1
fi
exit "$status"
