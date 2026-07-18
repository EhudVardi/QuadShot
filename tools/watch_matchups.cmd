@echo off
REM Watch the matchup harness fly its duels (GAMEPLAY-DESIGN H2/H5).
REM
REM Same rig as the headless balance run, minus --headless: each duel renders
REM from the reference pilot's own FPV camera, with the matchup and rep printed
REM as it starts and the outcome as it ends. Audio is muted (the rig restarts a
REM duel every few seconds, which makes motor tone unpleasant) and the arena
REM gains a sun/sky/grid floor purely so there is something to see — the floor
REM has no collider, so a watched duel is physically identical to a measured one.
REM
REM Close the window at any time; the run is a measurement, not a save.

setlocal
set GODOT=C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe
cd /d "%~dp0.."
"%GODOT%" -s scripts/tests/matchup_harness.gd --path .
echo.
echo [watch] finished - press any key to close.
pause >nul
