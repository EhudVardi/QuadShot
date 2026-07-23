extends Node3D

## Scene orchestration: camera switching (camera_toggle / X: FPV ↔ chase),
## combat config startup load, run/score/combo keeping (roadmap M3), and the
## player's damage → death → respawn loop (M2). Combat entities report in
## through their "destroyed" signals; waves flow through the WaveDirector.

@export var combat_config: CombatConfig
## Shared bindings resource (same instance the overlay edits) — main flips
## its context when pause engages.
@export var input_bindings: InputBindings

## Sample times (s) along the blaster's ballistic path for the HUD gun
## funnel — near rings aid close dogfights, far ones show the drop.
## Ranges (m) sampled for the FCS reticle: the fall-line arc, and the labelled
## range ticks. The pipper sits where the bolts pass at the target's range.

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _chase_camera: Camera3D = $ChaseCamera
@onready var _hud: GameHud = $Hud
@onready var _wave_director: WaveDirector = $WaveDirector
@onready var _missiles: MissileSystem = $Drone/FpvCamera/MissileSystem
@onready var _exit_gate: ExitGate = $ExitGate
@onready var _draft: DraftScreen = $DraftScreen
@onready var _weapon: Weapon = $Drone/FpvCamera/Weapon

var score: int = 0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _profile: PlayerProfile
var _combo: float = 1.0
var _last_kill_time: float = -1000.0
var _paused_mode: bool = false
var _pause_switch_was: bool = false
## Decaying FPV-breakup spike from the last hit (GAMEPLAY-DESIGN Iteration 7).
var _video_glitch_spike: float = 0.0


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	_profile = PlayerProfile.load_or_new()
	_hud.show_title(_bests_line())
	for scorer: Node in get_tree().get_nodes_in_group(&"targets") \
			+ get_tree().get_nodes_in_group(&"turrets"):
		scorer.connect(&"destroyed", _on_scorer_destroyed)
	_wave_director.enemy_destroyed.connect(_on_scorer_destroyed)
	_wave_director.wave_changed.connect(_hud.set_wave)
	_wave_director.sortie_cleared.connect(_on_sortie_cleared)
	_wave_director.run_ended.connect(_on_run_ended)
	_exit_gate.entered.connect(_on_gate_entered)
	_draft.picked.connect(_on_upgrade_picked)
	# Hull comes from the FRAME now (P3.9) and the drone applies it to itself in
	# _ready, so there is nothing to set here — only signals to wire.
	_drone_health.damaged.connect(_on_player_damaged)
	_drone_health.died.connect(_on_player_died)
	_drone.crashed.connect(_on_player_crashed)
	for gate: Node in get_tree().get_nodes_in_group(&"repair_gates"):
		(gate as RepairGate).repaired.connect(_on_engines_restored)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_refresh_motor_hud()


func _process(delta: float) -> void:
	if RunMods.current.regen_rate > 0.0 and _wave_director.running \
			and _drone_health.alive:
		_drone_health.heal(RunMods.current.regen_rate * delta)
		_hud.set_health(_drone_health.current, _drone_health.max_health)
	_handle_pause()
	if Input.is_action_just_pressed(&"camera_toggle"):
		if _fpv_camera.current:
			_chase_camera.make_current()
		else:
			_fpv_camera.make_current()
	# Arming starts (or restarts) a run — the summary stays readable until then.
	if not _wave_director.running and _drone.armed and _drone_health.alive:
		_start_run()
	_update_lock_indicator()
	_update_gate_marker()
	_update_reticle()
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])
	_update_damage_feedback(delta)


## BeamNG-style pause: time crawls (pause_time_scale) instead of stopping,
## the paused binding context activates (gameplay keys go quiet for safe
## typing), and the autopilot parks the drone.
func _handle_pause() -> void:
	# Typing in an overlay field must not toggle pause (P is a default key).
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if Input.is_action_just_pressed(&"pause_toggle"):
		_set_paused(not _paused_mode)
	if InputMap.has_action(&"pause_switch") \
			and not InputMap.action_get_events(&"pause_switch").is_empty():
		var switch_on: bool = Input.is_action_pressed(&"pause_switch")
		if switch_on != _pause_switch_was:
			_pause_switch_was = switch_on
			_set_paused(switch_on)


func _set_paused(paused: bool) -> void:
	_paused_mode = paused
	Engine.time_scale = _drone.config.pause_time_scale if paused else 1.0
	_drone.autopilot = paused
	if input_bindings != null:
		input_bindings.apply_context(paused)
	SoundBank.set_muffled(paused)
	_hud.show_pause(paused)
	print("[pause] %s" % ("slow-mo engaged, autopilot holding" if paused else "resumed"))


## Draw the FCS reticle: the true bolt fall (impact pipper + fall-line arc +
## range ticks) and the missile lock cone. The geometry lives in
## ReticleSolver, shared with the matchup harness's watch mode so the game and
## the rig can never draw different truths.
func _update_reticle() -> void:
	var solution: Dictionary = ReticleSolver.solve(
			get_viewport().get_camera_3d(), _weapon, _drone, combat_config,
			_missiles, get_tree(), RunMods.current.lock_cone_mult)
	if solution.is_empty():
		_hud.clear_reticle()
		return
	_hud.update_reticle(solution["center"], solution["pipper"], solution["arc"],
			solution["ticks"], solution["lock_radius"], solution["hold_radius"],
			solution["lockable"])


func _update_gate_marker() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not _exit_gate.active or camera == null \
			or camera.is_position_behind(_exit_gate.global_position):
		_hud.update_gate_marker(false)
		return
	_hud.update_gate_marker(true,
			camera.unproject_position(_exit_gate.global_position))


func _update_lock_indicator() -> void:
	var target: Node3D = _missiles.target
	var camera: Camera3D = get_viewport().get_camera_3d()
	if target == null or not is_instance_valid(target) or camera == null \
			or camera.is_position_behind(target.global_position):
		_hud.update_lock(false)
		return
	_hud.update_lock(true, camera.unproject_position(target.global_position),
			_missiles.lock_progress, _missiles.is_locked(),
			_missiles.auto_hold_progress())


func _start_run() -> void:
	score = 0
	_combo = 1.0
	_last_kill_time = -1000.0
	_hud.set_score(0)
	_hud.set_combo(1)
	_hud.hide_run_summary()
	_hud.hide_title()
	_exit_gate.deactivate()
	RunMods.reset()
	_drone_health.max_health = _drone.frame.hull
	_drone_health.revive()
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_repair_airframe()
	_wave_director.start_run()


func _on_sortie_cleared(sortie: int) -> void:
	_exit_gate.activate()
	_hud.announce_gate(sortie)


func _on_gate_entered() -> void:
	# Gate transit heals to full — sorties are self-contained challenges.
	_drone_health.heal(_drone_health.max_health)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_repair_airframe()
	# The gate fires from a physics callback; pausing for the draft waits
	# until the physics flush is done.
	_draft.call_deferred(&"open", Upgrades.draft())


func _on_upgrade_picked(id: StringName) -> void:
	Upgrades.apply(id, RunMods.current)
	_drone_health.max_health = _drone.frame.hull \
			+ RunMods.current.max_health_bonus
	_drone_health.heal(_drone_health.max_health)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_hud.add_kill_feed("+ %s" % Upgrades.title_of(id))
	_wave_director.advance_sortie()


func _on_scorer_destroyed(points: float) -> void:
	Blackbox.log_event(&"kill", "", points)
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_kill_time <= combat_config.combo_window:
		_combo = minf(_combo + 1.0, combat_config.combo_max)
	else:
		_combo = 1.0
	_last_kill_time = now
	var awarded: int = int(points * _combo * RunMods.current.score_mult)
	score += awarded
	_hud.set_score(score)
	_hud.set_combo(int(_combo))
	var feed: String = "+%d" % awarded
	if _combo > 1.0:
		feed += "  x%d" % int(_combo)
	_hud.add_kill_feed(feed)


func _on_run_ended(sorties_cleared: int, waves_cleared: int, kills: int) -> void:
	_profile.record_run(sorties_cleared, kills, score)
	_profile.save()
	_hud.show_run_summary(sorties_cleared, waves_cleared, kills, score,
			_bests_line())


func _bests_line() -> String:
	if _profile.runs == 0:
		return "first flight — good luck"
	return "runs %d  ·  kills %d  ·  best score %d  ·  best sorties %d" \
			% [_profile.runs, _profile.kills_total, _profile.best_score,
			_profile.best_sorties]


func _on_player_crashed(impact_speed: float) -> void:
	var excess: float = impact_speed - combat_config.crash_damage_speed
	if excess > 0.0:
		_drone_health.take(excess * combat_config.crash_damage_scale)


func _on_player_damaged(amount: float, remaining: float) -> void:
	Blackbox.log_event(&"player_hit", "", amount)
	# Damage is a flight-model event (D1): degrade the motor on the struck side
	# BEFORE the direction is consumed below, and spike the video feed (D4).
	_drone.apply_hit_to_motors(amount)
	var dc: DamageConfig = _drone.damage_config
	if dc != null and dc.severity > 0.0:
		# Every hit snaps the feed to at least the punch threshold (a sudden
		# break), bigger hits drive it harder — abrupt, not a gentle ramp.
		var bite: float = clampf(amount / maxf(_drone_health.max_health, 1.0) * 4.0,
				0.0, 1.0)
		var spike: float = dc.video_glitch_on_hit * dc.severity * (0.7 + 0.6 * bite)
		_video_glitch_spike = clampf(maxf(_video_glitch_spike, spike), 0.0, 1.0)
	_refresh_motor_hud()
	_hud.set_health(remaining, _drone_health.max_health)
	_hud.flash_damage(_incoming_fire_side())


func _refresh_motor_hud() -> void:
	var healths := PackedFloat32Array()
	for i: int in MotorModel.MOTOR_COUNT:
		healths.append(_drone.motor_health(i))
	_hud.set_motor_health(healths)


## Flew through a repair gate (D5): engines back, hull topped up — refresh the
## HUD and flash the confirmation.
func _on_engines_restored() -> void:
	_refresh_motor_hud()
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_hud.flash_engines_restored()


## Drive the FPV-breakup overlay: the last hit's decaying spike, floored by a
## sustained wash that grows as integrity falls (D4). Off entirely when dead —
## the death banner owns the screen then.
func _update_damage_feedback(delta: float) -> void:
	var dc: DamageConfig = _drone.damage_config
	if dc == null:
		return
	_video_glitch_spike = maxf(_video_glitch_spike - dc.video_glitch_decay * delta, 0.0)
	var sustained: float = 0.0
	if _drone_health.alive and _drone_health.max_health > 0.0:
		var integrity_frac: float = _drone_health.current / _drone_health.max_health
		sustained = dc.video_glitch_sustained * (1.0 - integrity_frac) * dc.severity
	_hud.set_video_glitch(maxf(_video_glitch_spike, sustained))


## Field patch (D5): pads/gate/respawn restore the airframe's flight and clear
## the feed — the wound is sortie-scoped, healed at the reset, not carried.
func _repair_airframe() -> void:
	_drone.repair_motors()
	_video_glitch_spike = 0.0
	_refresh_motor_hud()
	_hud.set_video_glitch(0.0)


## Maps the last projectile's incoming direction to a screen edge for the
## HUD. Crash damage has no direction and flashes the whole screen.
func _incoming_fire_side() -> StringName:
	var from_direction: Vector3 = _drone.last_hit_direction
	_drone.last_hit_direction = Vector3.ZERO
	if from_direction == Vector3.ZERO:
		return &"all"
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return &"all"
	var local: Vector3 = camera.global_basis.inverse() * from_direction
	if absf(local.x) > absf(local.z):
		return &"right" if local.x > 0.0 else &"left"
	return &"front" if local.z < 0.0 else &"back"


func _on_player_died() -> void:
	_wave_director.end_run()
	Effects.explosion(get_tree().root, _drone.global_position, 1.6)
	_drone.disarm()
	_drone.visible = false
	# Death arrives mid-physics (projectile hit or crash contact) — body
	# state changes must defer.
	_drone.set_deferred(&"freeze", true)
	_hud.show_death(true)
	get_tree().create_timer(combat_config.respawn_delay).timeout.connect(_respawn_player)


func _respawn_player() -> void:
	_drone.freeze = false
	_drone.reset_to_spawn()
	# Re-read max health so live tuning applies from the next life on.
	_drone_health.max_health = _drone.frame.hull
	_drone_health.revive()
	_drone.visible = true
	_hud.show_death(false)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_repair_airframe()
