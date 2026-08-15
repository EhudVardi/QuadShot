#!/usr/bin/env bash
# Run the headless check board and print one PASS/FAIL line per check.
#
# IT EXISTS SO THE BOARD IS ONE LITERAL COMMAND, and that is a tooling fix rather
# than a convenience. A permission allowlist matches the command STRING, so an
# agent running the checks as a shell `for` loop can never match an entry - the
# loop body has a variable in it and is not statically knowable. Every board run
# therefore prompted, forever, however carefully the allowlist was written.
# One script is one command, and one command is matchable.
#
# Takes about 5 minutes; `lethality` is most of it.
#
#   ./tools/board.sh          all 24
#   ./tools/board.sh fast     skip lethality, about 2-3 minutes
set -u

GODOT="C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CHECKS="hover combat wave missile run repair motor_damage menu manifest
        sortie_compose falx screamer composition heat ammo sortie war_loop
        war_room aegis lance phalanx terrain crash separation"
if [ "${1:-}" != "fast" ]; then
    CHECKS="$CHECKS lethality"
fi

failed=0
for c in $CHECKS; do
    line=$("$GODOT" --headless -s "scripts/tests/${c}_check.gd" --path "$ROOT" 2>&1 \
        | grep -E 'PASS$|FAIL' | tail -1)
    if [ -z "$line" ]; then
        printf '[board] %-16s NO VERDICT\n' "$c"
        failed=$((failed + 1))
    else
        printf '[board] %-16s %s\n' "$c" "$line"
        case "$line" in *FAIL*) failed=$((failed + 1));; esac
    fi
done

echo
if [ "$failed" -eq 0 ]; then
    echo "[board] ALL GREEN"
    exit 0
fi
echo "[board] $failed check(s) NOT GREEN"
exit 1
