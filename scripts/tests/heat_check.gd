extends SceneTree

## Headless blaster-DUTY-CYCLE check (Iteration 10 R.q1). The blaster is the
## weapon you always have, so the failure this exists to catch is the worst one
## in the game: a gun that locks out and never comes back leaves a pilot alive,
## armed, and unable to clear a wave — and nothing else in the suite would
## notice, because every other check either kills its enemies with `take_hit`
## or never holds the trigger long enough to overheat.
##
## Four phases, in the order the mechanic can fail:
##   1. a held trigger actually overheats, and does so at the bolt count the
##      config says (not "eventually");
##   2. the lockout is REAL — no bolt leaves while it holds;
##   3. it recovers, and only after falling to the reset fraction rather than
##      the instant it dips below the ceiling (the stutter-at-the-ceiling bug
##      the reset fraction exists to prevent);
##   4. it fires again afterwards, which is the "never comes back" case.
##
## Then one assertion that is arithmetic rather than flight: Layer 1's
## duty-cycle model must agree with the weapon it claims to describe, or
## BALANCE.md's Layer 1 goes back to quietly assuming infinite ammunition
## (Iteration 10 R7). It is checked HERE, against a live weapon in a live
## scene, precisely because `lethality_check` cannot — that bench plants shots
## from the model itself, so a model that drifted from the gun would agree with
## itself all the way to the wrong answer.
##
## Run: <godot> --headless -s scripts/tests/heat_check.gd --path .

const MAX_SECONDS: float = 20.0

var _main: Node3D
var _drone: FlightController
var _weapon: Weapon
var _combat: CombatConfig
var _phase: int = 0
var _ticks: int = 0
var _ticks_max: int
var _failures: Array[String] = []
var _shots_at_lockout: int = 0
var _locked_ticks: int = 0


func _initialize() -> void:
	# An instrument measures the REPO's numbers, never one machine's tuning.
	TunableConfig.user_overrides_enabled = false
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_main)
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks >= _ticks_max:
		_fail("timed out in phase %d (heat %.1f, overheated %s, shots %d)"
				% [_phase, _weapon.heat if _weapon != null else -1.0,
				str(_weapon.overheated if _weapon != null else false),
				_weapon.shots_fired if _weapon != null else -1])
		_report()
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_setup()
			_phase = 1
		1:
			# Trigger held (fire_override). Sustained fire must never cool, so
			# the burst is an exact bolt count.
			if not _weapon.overheated:
				return
			_shots_at_lockout = _weapon.shots_fired
			var expected: int = Lethality.burst_shots(_combat)
			# One bolt of slack: the tick the sink fills and the tick the
			# lockout latches are the same frame's two halves.
			if absi(_shots_at_lockout - expected) > 1:
				_fail("overheated after %d bolts, config says %d"
						% [_shots_at_lockout, expected])
			print("[heat_check] locked out after %d bolts (config %d)"
					% [_shots_at_lockout, expected])
			_phase = 2
		2:
			# The lockout has to be real: not one bolt while it holds. Tested
			# INSIDE the overheated branch, and that ordering is load-bearing —
			# the tick the lockout clears is a tick the gun legitimately fires
			# on, and checking bolts first reported the first bolt of the next
			# burst as a bolt fired during the vent.
			if _weapon.overheated:
				_locked_ticks += 1
				if _weapon.shots_fired > _shots_at_lockout:
					_fail("fired %d bolts DURING the lockout (tick %d of it, heat %.2f)"
							% [_weapon.shots_fired - _shots_at_lockout,
							_locked_ticks, _weapon.heat])
					_report()
					return
				return
			# Released. The assertion is the vent DURATION, not the heat left in
			# the sink: duration is what the reset fraction actually produces,
			# and unlike an instantaneous reading it cannot be contaminated by
			# the next burst's first bolt landing on the same tick.
			var held_s: float = float(_locked_ticks) / float(Engine.physics_ticks_per_second)
			var predicted: float = Lethality.vent_seconds(_combat)
			# Generous: the trigger is still down, so the frame it releases it
			# also fires. This is a sanity band, not a timing assertion.
			if absf(held_s - predicted) > 0.5:
				_fail("vent took %.2fs, Layer 1 predicts %.2fs" % [held_s, predicted])
			print("[heat_check] vented in %.2fs (Layer 1 says %.2fs)"
					% [held_s, predicted])
			_phase = 3
		3:
			# The one that matters: does the gun come back at all?
			if _weapon.shots_fired > _shots_at_lockout:
				print("[heat_check] firing again after the vent (%d bolts total)"
						% _weapon.shots_fired)
				_check_layer_one()
				_report()


func _check_layer_one() -> void:
	# A kill inside one burst must not pay for a vent it never reached.
	var raider: EnemyConfig = load("res://resources/default_enemy_raider.tres") as EnemyConfig
	var solo: Dictionary = Lethality.versus("blaster", _combat, raider)
	if not bool(solo["kills"]):
		_fail("blaster cannot kill a raider at all — heat broke Layer 1")
		return
	var interval: float = 1.0 / maxf(_combat.fire_rate, 0.001)
	if int(solo["shots"]) <= Lethality.burst_shots(_combat) \
			and absf(float(solo["ttk"]) - float(int(solo["shots"]) - 1) * interval) > 0.001:
		_fail("a %d-bolt kill inside a %d-bolt burst was charged for a vent (ttk %.3f)"
				% [solo["shots"], Lethality.burst_shots(_combat), solo["ttk"]])
	# And a target that CANNOT die inside one burst must pay for exactly the
	# vents it crosses — the arithmetic R7 promised would land with the feature.
	var wall := EnemyConfig.new()
	wall.hull = _combat.projectile_damage * float(Lethality.burst_shots(_combat)) * 2.5
	var long_kill: Dictionary = Lethality.versus("blaster", _combat, wall)
	var shots: int = int(long_kill["shots"])
	var vents: int = (shots - 1) / Lethality.burst_shots(_combat)
	var expected: float = float(shots - 1) * interval \
			+ float(vents) * Lethality.vent_seconds(_combat)
	if vents < 1:
		_fail("the long-kill probe never crossed a vent — it proves nothing")
	elif absf(float(long_kill["ttk"]) - expected) > 0.001:
		_fail("%d-bolt kill: ttk %.2fs, %d vents says %.2fs"
				% [shots, long_kill["ttk"], vents, expected])
	else:
		print("[heat_check] Layer 1: %d bolts across %d vent(s) = %.2fs"
				% [shots, vents, long_kill["ttk"]])


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_combat = _weapon.combat_config
	# Every field the assertions depend on is pinned explicitly — main
	# auto-loads the pilot's saved combat config, which can carry any tuning.
	_combat.fire_rate = 10.0
	_combat.heat_per_shot = 1.0
	_combat.heat_capacity = 30.0
	_combat.heat_cool_rate = 12.0
	_combat.heat_vent_delay = 0.35
	_combat.heat_reset_fraction = 0.3
	# The director must not fire for us: this check is about the trigger.
	_combat.fire_assist_miss_m = 0.0
	# Arming starts a real run, and a real run shoots back. The first version
	# of this check held the trigger for seven seconds and then reported "the
	# gun never came back" — the gun was fine, the drone was dead. Defang the
	# whole roster: this check is about a weapon, not a fight.
	for type_id: StringName in WaveDirector.ROSTER:
		var enemy: EnemyConfig = load(
				"res://resources/default_enemy_%s.tres" % type_id) as EnemyConfig
		enemy.damage = 0.0
		enemy.sight_range = 0.0
	RunMods.reset()
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	# Held from here to the end of the check. The gun coming back is only
	# meaningful if nobody let go.
	_weapon.fire_override = true


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	for message: String in _failures:
		print("[heat_check] FAIL: %s" % message)
	print("[heat_check] %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
