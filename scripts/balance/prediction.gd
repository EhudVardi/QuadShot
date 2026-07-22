class_name BalancePrediction
extends RefCounted

## Where the two layers meet (GAMEPLAY-DESIGN v1.23 Phase 3.5 step 4,
## BALANCE.md): Layer 1 lethality x Layer 2 delivery -> a PREDICTED band for
## each weapon x enemy cell, which the duel harness then VALIDATES.
##
## The model, stated plainly so it can be argued with:
##
##   shots_fired = ceil(shots_to_kill * bodies / (aim * evasion * splash))
##   engagement_ttk = (shots_fired - 1) * cadence
##
## Four assumptions live in that arithmetic, and naming them is the point:
##   1. SEPARABILITY — aim and evasion multiply. Measured apart, used
##      together. If a target's evasion degrades the agent's aim by MORE than
##      the product (a jinking raider is harder to track than a static one by
##      a factor the static bench never saw), the prediction is optimistic and
##      the validation column will say so.
##   2. CADENCE IS THE ECONOMY — misses cost time at the weapon's own rate.
##      This is the whole reason a 3 s missile bankrupts against nine gnats it
##      hits every single time: delivery 1.00, durability 1 hit, and still a
##      24 s engagement.
##   3. NOBODY SHOOTS BACK. There is no survival term here at all. A cell the
##      player would predictably die in still predicts a clean band, so a
##      predicted-good / validated-bad divergence is the instrument working:
##      it has just named survival as the missing factor.
##   3b. SPLASH IS A DIVISOR ON THE PACK BILL, not a multiplier on damage. An
##      area weapon is paid per BURST while the target is priced per BODY, and
##      `splash` (bodies covered by one arriving burst, MEASURED against a real
##      pack) is the exchange rate between the two. It is 1.0 for every
##      single-target weapon and for every single-body target, so it changes
##      nothing that existed before flak — but it is the only reason the flak
##      column can read differently from the chip gun's, since Layer 1 prices
##      both per body. Un-modeled inside it: a burst's coverage depends on how
##      tight the cloud happens to be at that instant, so splash is an average
##      over a measurement window, not a guarantee about any one shell.
##   4. THE CLOCK STARTS AT THE FIRST SHOT. Acquisition (a 0.9 s missile lock)
##      and time of flight (0.8 s over 40 m) are outside this number, so a
##      predicted ttk is systematically OPTIMISTIC by roughly one lock plus
##      one flight time — a one-missile kill predicts 0.0 s and duels at
##      1.7 s. Fine for ranking cells against each other, wrong if read as a
##      wall clock. Do not tighten a band to close that gap; it is the
##      metric's definition, not a balance problem.
##
## Divergence is the OUTPUT, not the error. Per BALANCE.md, this file is never
## the source of truth for "what will happen" — it is the source of truth for
## "what the numbers alone imply", and the gap is a finding.

## Where the delivery bench leaves its measured factors.
const FACTORS_PATH: String = "res://balance/delivery_factors.json"

## Predicted-TTK bands, seconds, ascending; stated constants that do not drift
## (H.q1). Anchored on the duel harness's own 10 s cap: a cell predicted
## slower than the cap is a cell the rig cannot finish, which is what `-` and
## `--` mean operationally.
const TTK_BANDS: Array = [[2.0, "++"], [5.0, "+"], [10.0, "0"], [20.0, "-"]]

## Guard against a divide-by-almost-zero delivery factor turning into an
## absurd shot count. Past this many shots per body the answer is "no".
const MAX_SHOTS_PER_BODY: float = 10000.0


## Load the delivery bench's artifact. Returns {} when it is missing — the
## caller must degrade honestly (print no predicted column) rather than
## substitute a default, because an invented delivery factor is exactly the
## kind of quiet fiction this whole phase exists to remove.
static func load_factors() -> Dictionary:
	if not FileAccess.file_exists(FACTORS_PATH):
		return {}
	var file: FileAccess = FileAccess.open(FACTORS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


## Fields that actually move a measured delivery factor. A change to any of
## them invalidates balance/delivery_factors.json just as surely as a pilot
## change does — but the staleness guard used to watch PILOT_VERSION alone, so
## retuning muzzle_speed or an enemy's speed silently left the predicted column
## quoting factors measured against different physics. Phase 4 makes that
## urgent rather than theoretical: adding a weapon column edits CombatConfig.
##
## Deliberately a WHITELIST, not every field: hull and damage belong to Layer 1
## (they change lethality, which is recomputed live from config every run and
## so is never stale), while these govern whether a shot ARRIVES. Listing them
## explicitly also documents what delivery actually depends on.
const DELIVERY_FIELDS_COMBAT: Array[String] = [
	"muzzle_speed", "projectile_gravity_scale", "projectile_lifetime",
	"inherit_velocity", "fire_rate", "fire_assist_range",
	"missile_speed", "missile_turn_rate_deg", "missile_lock_range",
	"missile_lock_cone_deg", "missile_lock_time", "missile_cooldown",
	"missile_prox_radius", "missile_lifetime",
	# Flak's ballistics AND its two radii: the fuse and the burst decide whether
	# a shell arrives and how much of a pack it covers, so both are delivery
	# inputs. flak_damage is deliberately absent — it is Layer 1, recomputed
	# live, and so can never go stale.
	"flak_muzzle_speed", "flak_shell_gravity_scale", "flak_shell_lifetime",
	"flak_fire_rate", "flak_arm_distance", "flak_fuse_radius",
	"flak_burst_radius",
]
const DELIVERY_FIELDS_ENEMY: Array[String] = [
	"speed", "accel", "turn_speed_deg", "pack_size", "swarm_spacing",
	"swarm_separation_gain", "swarm_cohesion_gain", "swarm_jitter",
	"swarm_sting_radius",
]
## The AIRFRAME's half of aim (Phase 4b): what the pilot is flying decides how
## well it can hold a line, so a frame's flight model is a delivery input in the
## same way a muzzle speed is. Read off each frame's FlightConfig.
##
## This list closes the hole the frame axis exposed rather than created — the
## Kestrel's mass and rate gains were ALWAYS delivery inputs and were never
## stamped, so retuning the drone's PID silently invalidated every factor while
## the stamp reported a match. Vector fields are stamped componentwise.
##
## FrameConfig.hull and .armor are deliberately absent: no bench that measures a
## delivery factor can be affected by them (the aim bench's target cannot shoot,
## the evasion bench's shooter is immortal). They move VALIDATED results, which
## are re-measured every run and so cannot go stale.
const DELIVERY_FIELDS_FLIGHT: Array[String] = [
	"mass", "arm_length", "thrust_to_weight_ratio", "motor_lag_tau",
	"motor_idle", "yaw_authority", "max_rate_deg", "expo",
	"gyro_lpf_hz", "dterm_lpf_hz", "rc_smoothing_hz",
	"rate_p", "rate_i", "rate_d", "rate_ff", "ff_lpf_hz", "integral_limit",
	"drag_coefficient", "angular_damping", "fpv_uptilt_deg", "fpv_fov_deg",
]


## A stamp over every config value the delivery benches are sensitive to.
## Stored in the artifact and compared on read; a mismatch means the factors
## were measured against different numbers and must not be quoted.
static func config_stamp(combat: CombatConfig, enemies: Array[EnemyConfig],
		frames: Array[FrameConfig]) -> String:
	var parts: PackedStringArray = []
	for field: String in DELIVERY_FIELDS_COMBAT:
		parts.append("%s=%.4f" % [field, float(combat.get(field))])
	# Sorted by type_id so the stamp does not depend on load order.
	var sorted: Array[EnemyConfig] = enemies.duplicate()
	sorted.sort_custom(func(a: EnemyConfig, b: EnemyConfig) -> bool:
			return String(a.type_id) < String(b.type_id))
	for enemy: EnemyConfig in sorted:
		for field: String in DELIVERY_FIELDS_ENEMY:
			parts.append("%s.%s=%.4f"
					% [enemy.type_id, field, float(enemy.get(field))])
	var frames_sorted: Array[FrameConfig] = frames.duplicate()
	frames_sorted.sort_custom(func(a: FrameConfig, b: FrameConfig) -> bool:
			return String(a.frame_id) < String(b.frame_id))
	for frame: FrameConfig in frames_sorted:
		for field: String in DELIVERY_FIELDS_FLIGHT:
			parts.append("%s.%s=%s"
					% [frame.frame_id, field, _stamp_value(
					frame.flight_config.get(field))])
	return String(", ".join(parts)).sha256_text()


## Vector fields are stamped componentwise; everything else to four decimals, so
## the stamp reads the same on any machine and a Vector3 cannot collapse to one
## number that hides two gains swapping.
static func _stamp_value(value: Variant) -> String:
	if value is Vector3:
		var v: Vector3 = value as Vector3
		return "(%.5f,%.5f,%.5f)" % [v.x, v.y, v.z]
	return "%.4f" % float(value)


## Delivery factor keys. Aim is per agent+weapon; evasion is per weapon+target
## (the same bolt is easy to dodge and the same missile is not, so evasion is
## not a property of the target alone — it is measured against the weapon that
## has to arrive).
##
## THE FRAME AXIS COST THE MODEL NOTHING NEW (Phase 4b). Adding the flak column
## forced a third factor into existence (`splash`), so the obvious worry about a
## second frame was which factor it would force next. The answer is none: the
## agent was always "pilot flying an airframe", there was simply only ever one
## airframe, so a frame is a RE-KEYING of aim rather than a new dimension. The
## Atlas's soft rates and 1.9x mass move how well the same brain holds a gun
## line, which is exactly what aim_quality already meant.
##
## Evasion is deliberately NOT frame-keyed, and that is structural rather than
## an economy: the evasion bench freezes the shooter and lays its gun on the
## exact ballistic solution every tick, so the airframe is inert BY CONSTRUCTION
## — a frozen Atlas and a frozen Kestrel fire identical shots. Splash likewise
## belongs to the weapon meeting the target. So the frame axis doubles the aim
## cells and nothing else.
static func aim_key(frame_id: String, weapon: String) -> String:
	return "%s:%s" % [frame_id, weapon]


static func evasion_key(weapon: String, type_id: String) -> String:
	return "%s:%s" % [weapon, type_id]


## Splash yield — bodies covered per ARRIVING burst, per weapon x target. Keyed
## like evasion because it is equally a property of the pair: the same fragment
## cloud swallows three gnats and exactly one aegis.
static func splash_key(weapon: String, type_id: String) -> String:
	return "%s:%s" % [weapon, type_id]


## A missing splash entry means 1.0, not "unknown". Every weapon before the flak
## pod damaged exactly one body per connect, so the absence of a measurement IS
## the measurement for them — unlike aim or evasion, where a missing factor must
## blank the column rather than be guessed.
static func splash_for(factors: Dictionary, weapon: String,
		type_id: String) -> float:
	var table: Dictionary = factors.get("splash", {})
	return maxf(float(table.get(splash_key(weapon, type_id), 1.0)), 0.01)


## One predicted cell. `bodies` is the pack size (1 for single-body types) —
## the unit is the CLOUD for distributed types (P4.q5), so killing the unit
## means killing every body. `splash` is the area-weapon divisor (assumption 3b);
## 1.0 for everything that damages one body per connect.
##
## Returns: band, ttk, shots_fired, hit_rate, why (when it cannot resolve).
static func predict(weapon: String, combat: CombatConfig, enemy: EnemyConfig,
		aim: float, evasion: float, bodies: float,
		splash: float = 1.0) -> Dictionary:
	var lethality: Dictionary = Lethality.versus(weapon, combat, enemy)
	if lethality.is_empty():
		return _unresolved("unknown weapon")
	var cadence: float = float(lethality["interval"])
	if not bool(lethality["kills"]):
		# Layer 1 vetoes: no amount of delivery rescues a weapon that cannot
		# kill this target even on a clean hit.
		return {"band": "--", "ttk": INF, "shots_fired": 0.0,
				"hit_rate": 0.0, "cadence": cadence,
				"why": "lethality: %s" % lethality["why"]}
	var hit_rate: float = aim * evasion
	if hit_rate <= 0.0:
		return {"band": "--", "ttk": INF, "shots_fired": 0.0,
				"hit_rate": 0.0, "cadence": cadence,
				"why": "delivery: nothing connects"}
	var per_body: float = float(lethality["shots"]) / hit_rate
	if per_body > MAX_SHOTS_PER_BODY:
		return {"band": "--", "ttk": INF, "shots_fired": ceilf(per_body),
				"hit_rate": hit_rate, "cadence": cadence,
				"why": "delivery: %.0f shots per body" % per_body}
	# ONE rounding, on the TOTAL — not one per body. The per-body ceiling this
	# replaced was pessimistic for packs by up to a shot each: a bolt that misses
	# gnat 4 is not a shot "wasted on gnat 4" that has to be re-spent, it is one
	# shot of an aggregate bill. Flak forced the question (its whole economy is
	# the pack bill) and the aggregate is simply the correct arithmetic. Only one
	# shipped cell moves: Blaster x Gnats, 450 shots -> 442, band unchanged.
	var shots_fired: float = ceilf(
			per_body * maxf(bodies, 1.0) / maxf(splash, 0.01))
	# First shot at t=0, so the clock spans the gaps between shots, not the
	# shots themselves.
	var ttk: float = (shots_fired - 1.0) * cadence
	return {"band": band_for(ttk), "ttk": ttk, "shots_fired": shots_fired,
			"hit_rate": hit_rate, "cadence": cadence, "splash": splash,
			"why": ""}


static func band_for(ttk: float) -> String:
	for entry: Array in TTK_BANDS:
		if ttk <= float(entry[0]):
			return entry[1]
	return "--"


static func _unresolved(why: String) -> Dictionary:
	return {"band": "?", "ttk": INF, "shots_fired": 0.0, "hit_rate": 0.0,
			"cadence": 0.0, "why": why}
