@echo off
REM The one-command balance report (GAMEPLAY-DESIGN v1.23, Phase 3.5 step 4).
REM
REM Runs the three layers IN ORDER, because each one feeds the next:
REM
REM   1. lethality_check  - Layer 1. Verifies the config-derived kill
REM                         arithmetic still matches the shipped Health code.
REM                         If this fails, nothing downstream means anything.
REM   2. delivery_bench   - Layer 2. Measures aim_quality and evasion in
REM                         isolation and writes balance/delivery_factors.json.
REM   3. matchup_harness  - Validation. Duels the integrated fight and prints
REM                         the mini-web as paper -> predicted -> validated.
REM
REM Read BALANCE.md before acting on the output. In particular: a
REM predicted-vs-validated gap is the instrument's OUTPUT, not its error --
REM it names an un-modeled factor (survival, a deadline, the economy) for a
REM human to go model or knowingly accept. Do not "fix" a number to close a
REM gap you have not explained.
REM
REM Every section prints the PILOT_VERSION it was measured under. Numbers
REM from different pilot versions never belong in the same table.

setlocal
set GODOT=C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe
cd /d "%~dp0.."

echo ============================================================
echo  LAYER 1 - lethality (config arithmetic vs shipped Health)
echo ============================================================
"%GODOT%" --headless -s scripts/tests/lethality_check.gd --path .
if errorlevel 1 (
	echo.
	echo [balance_report] Layer 1 FAILED - the calculator and the damage code
	echo [balance_report] disagree. Everything downstream is unreadable until
	echo [balance_report] that is resolved. Stopping.
	exit /b 1
)

echo.
echo ============================================================
echo  LAYER 2 - delivery (aim quality, evasion)
echo ============================================================
"%GODOT%" --headless -s scripts/tests/delivery_bench.gd --path .
if errorlevel 1 (
	echo.
	echo [balance_report] Layer 2 FAILED - a control cell missed, so the bench
	echo [balance_report] itself is broken. Fix the rig before reading any
	echo [balance_report] target's evasion. Stopping.
	exit /b 1
)

echo.
echo ============================================================
echo  VALIDATION - duels, and the paper/predicted/validated web
echo ============================================================
"%GODOT%" --headless -s scripts/tests/matchup_harness.gd --path .
set HARNESS_RESULT=%errorlevel%

echo.
echo [balance_report] done. Delivery factors: balance/delivery_factors.json
exit /b %HARNESS_RESULT%
