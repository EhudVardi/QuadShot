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
#   ./tools/board.sh          all 27
#   ./tools/board.sh fast     skip lethality, about 2-3 minutes
set -u

GODOT="C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CHECKS="hover combat wave missile run repair motor_damage menu manifest
        sortie_compose falx screamer composition heat ammo sortie war_loop
        war_room aegis lance phalanx terrain crash separation hud drill"
if [ "${1:-}" != "fast" ]; then
    CHECKS="$CHECKS lethality"
fi

failed=0
for c in $CHECKS; do
    # PASS/FAIL AS WHOLE WORDS, ANYWHERE ON THE LINE - never anchored to the end.
    #
    # This was 'PASS$|FAIL' until 2026-08-15 and it could not read `lethality`
    # AT ALL, because that check signs off with "PASS - calculator matches
    # Health.take on every cell" and the anchor demanded PASS be the last thing
    # on the line. Every full board run reported it as NO VERDICT, which was
    # blamed on two Godot processes overlapping before the grep was actually
    # tested against the check's real output.
    #
    # It failed SAFE - a verdict it cannot read counts as not-green - which is the
    # only reason it was noticed rather than quietly passing a broken check.
    # \b matters: it keeps "FAILURE" from reading as a failure.
    #
    # `tail -1` takes the LAST match, which is the verdict: checks that print
    # per-claim "FAIL: <reason>" lines put their one-word summary after them.
    line=$("$GODOT" --headless -s "scripts/tests/${c}_check.gd" --path "$ROOT" 2>&1 \
        | grep -E '\b(PASS|FAIL)\b' | tail -1)
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
