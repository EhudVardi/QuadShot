@echo off
REM Watch the Layer 2 delivery benches measure themselves (BALANCE.md).
REM
REM Same rig as the headless run, minus --headless: each cell renders from the
REM drone's own FPV camera, announced as it starts, with the measured factor
REM printed as it ends. Audio is muted and the arena gains a sun/sky/grid floor
REM purely so there is something to see -- the floor has no collider, so a
REM watched cell is physically identical to a measured one.
REM
REM What to look for:
REM   aim cells      - the pilot flies and shoots a target that cannot move.
REM                    0.14 for the blaster is the number to interrogate: is it
REM                    missing its shots, or fighting the aircraft?
REM   evasion cells  - the drone is FROZEN and its gun is re-laid every tick
REM                    onto the exact firing solution. Anything it misses, the
REM                    TARGET dodged. The static control cells should look
REM                    boring: bolt after bolt straight into a hovering raider.
REM
REM Close the window at any time; the run is a measurement, not a save.

setlocal
set GODOT=C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe
cd /d "%~dp0.."
"%GODOT%" -s scripts/tests/delivery_bench.gd --path .
echo.
echo [watch] finished - press any key to close.
pause >nul
