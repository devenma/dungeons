#!/usr/bin/env bash
# Atajos del proyecto / Project shortcuts
#   ./run.sh              juego / game
#   ./run.sh preview      escena de prueba de arte / art preview scene
#   ./run.sh test [texto] tests (todos o los que contienen el texto) / tests (all or matching)
#   ./run.sh import       reimportar recursos / reimport resources
set -u
cd "$(dirname "$0")"

# Binario de Godot; se puede pisar con la variable GODOT / Godot binary; override with GODOT
GODOT="${GODOT:-$HOME/tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
if [ ! -x "$GODOT" ]; then
	echo "No encuentro Godot en $GODOT (definí GODOT=/ruta/al/binario)" >&2
	exit 1
fi

case "${1:-game}" in
	game) "$GODOT" --path . ;;
	preview) "$GODOT" --path . res://scenes/preview/art_preview.tscn ;;
	import) "$GODOT" --headless --path . --import ;;
	test)
		filter="${2:-}"
		pass=0
		fail=0
		log="$(mktemp)"
		for t in scripts/test/*${filter}*.gd; do
			if "$GODOT" --headless --path . -s "$t" >"$log" 2>&1; then
				pass=$((pass + 1))
				echo "OK    $t"
			else
				fail=$((fail + 1))
				echo "FALLA $t"
				grep -i "fail\|error" "$log" | head -10 | sed 's/^/      /'
			fi
		done
		rm -f "$log"
		echo "$pass ok, $fail fallaron"
		[ "$fail" -eq 0 ]
		;;
	*)
		echo "Uso: ./run.sh [game|preview|test [texto]|import]" >&2
		exit 1
		;;
esac
