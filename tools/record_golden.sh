#!/usr/bin/env bash
# Перезаписывает golden-реплей. Только при намеренном изменении правил — и с объяснением в коммите.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s res://tools/record_golden.gd
