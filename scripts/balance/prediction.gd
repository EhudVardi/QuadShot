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
##   3. NOBODY SHOOTS BACK — in the BAND. A cell the player would predictably
##      die in still predicts a clean band, so a predicted-good / validated-bad
##      divergence is the instrument working: it has just named survival as the
##      missing factor.
##      PARTIALLY DISCHARGED (Iteration 9 / S3, v1.78): `survive()` below now
##      states, in seconds, how long a frame lasts under a named threat at a
##      named concurrency — Layer 3a's arithmetic times Layer 3b's measured
##      connect rate. What is deliberately NOT done is folding that number into
##      the predicted BAND: a ttk band and a survival band are two rulers, and
##      H.q1 forbids drifting one to make the other agree. So the survival term
##      is printed BESIDE the band, and assumption 3 still describes the band.
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
## The BESTIARY's half. THE WEAPON HALF WAS MISSING UNTIL v1.78, and Layer 3b
## is what made it a hole
## rather than a correct omission. While the benches only ever pointed the
## player's guns outward, an enemy's `damage`/`fire_rate` moved nothing measured
## — they are Layer 1 terms, recomputed live. The player-evasion bench changed
## that in three separate ways, and each one is a field below:
##   - `fire_rate` sets how many rounds the threat sends in the window, which is
##     the cell's SAMPLE SIZE and (through the jink's hit-gated memory) the duty
##     cycle of the evasion being measured.
##   - `damage` is the CONSERVATIVE entry, and the reasoning behind it changed
##     mid-build — recorded because the change is instructive. Under the first
##     Layer 3b design it was strictly load-bearing: the jink was hit-gated, so a
##     threat whose damage sat at or under the frame's armor produced a pilot
##     that never evaded, a completely different measurement from a config edit
##     the stamp could not see. Forcing the jink state (ReferencePilot.Jink)
##     broke that coupling along with the bistability it caused, so today damage
##     moves only the cell's diagnostic hull figure. It stays listed anyway: a
##     false positive costs one re-measure, a false negative costs a quoted stale
##     number, and the AUTO gate is one bench edit away from being load-bearing
##     again.
##   - `muzzle_speed` and `sight_range` are the perfect shooter's own ballistics:
##     the lead solution and the round's lifetime. A slower round is a longer
##     flight time, which is exactly what a jink is racing.
##   - `preferred_range` joined in v1.83 and was a PRE-EXISTING hole, not a new
##     input: an orbiting type's standoff radius has always decided the geometry
##     every evasion cell is measured at, and retuning it moved the factor while
##     the stamp reported a match. The Screamer only made it conspicuous — its
##     whole behaviour is a standoff radius.
##
## DELIBERATELY ABSENT: the EW pair (`jam_range`, `jam_full_range`). Every aim
## cell FORCES its jam state (`Jamming.bench_override`), exactly as every Layer 3b
## cell forces its jink state, so the radii cannot move a measured factor — they
## decide where in a FIGHT the states are met, which is the duel's business. This
## follows `aim_jitter_deg`'s stated precedent rather than the conservatism
## granted to `damage`/`hull`/`armor`, because the reason is structural (the bench
## states the condition) rather than merely currently-true.
const DELIVERY_FIELDS_ENEMY: Array[String] = [
	"speed", "accel", "turn_speed_deg", "pack_size", "swarm_spacing",
	"swarm_separation_gain", "swarm_cohesion_gain", "swarm_jitter",
	"swarm_sting_radius",
	"damage", "fire_rate", "muzzle_speed", "sight_range", "preferred_range",
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
## `aim_jitter_deg` is deliberately absent from the list above, and the reason is
## the whitelist discipline rather than an oversight: the player-evasion bench
## lays a PERFECT solution, exactly as the enemy-evasion bench does, so the
## threat's own marksmanship is by construction outside the factor. Nothing
## measured reads that field, so nothing measured goes stale when it moves. It is
## the un-measured mirror of `aim_quality` — see `survive`'s assumption 2.
const DELIVERY_FIELDS_FLIGHT: Array[String] = [
	"mass", "arm_length", "thrust_to_weight_ratio", "motor_lag_tau",
	"motor_idle", "yaw_authority", "max_rate_deg", "expo",
	"gyro_lpf_hz", "dterm_lpf_hz", "rc_smoothing_hz",
	"rate_p", "rate_i", "rate_d", "rate_ff", "ff_lpf_hz", "integral_limit",
	"drag_coefficient", "angular_damping", "fpv_uptilt_deg", "fpv_fov_deg",
]
## The FRAME's durability, read off FrameConfig itself rather than its flight
## model. Phase 4b left these out with a stated reason — "no bench that measures
## a delivery factor can be affected by them (the aim bench's target cannot
## shoot, the evasion bench's shooter is immortal)" — and that reason was true
## right up until a bench pointed a gun at the player.
##
## HOW STRONG THAT CLAIM IS CHANGED DURING THE BUILD, and the honest version is
## worth more than the tidy one. Layer 3b's first design gated the jink on having
## been hit, which made both fields strictly load-bearing: `armor` decided
## whether the pilot ever started evading (a hit that does not reduce hull never
## trips the gate) and `hull` decided whether it survived the window. That gate
## also made the cell a feedback loop and bistable, so it was replaced by a
## forced jink state — and forcing it removed the coupling that justified these
## two fields in the first place. Under the shipped bench they are once again
## inert: the player is immortal for the measurement and the flight mode is
## stated by the cell.
##
## They stay listed as a DELIBERATE CONSERVATISM, not a necessity, because the
## asymmetry is stark: a false positive costs one re-measure, a false negative
## costs a quoted stale number, and the AUTO gate is one bench edit away from
## making them load-bearing again. Drop them if the strict whitelist rule is
## preferred — but drop them knowingly.
##
## They are stamped GLOBALLY, like every other field here, so retuning the
## Atlas's armor invalidates the Kestrel's aim cells too. Same trade: one stamp
## with a false positive is honest, two stamps that each cover half the file are
## how a stale number gets quoted.
const DELIVERY_FIELDS_FRAME: Array[String] = ["hull", "armor"]


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
		for field: String in DELIVERY_FIELDS_FRAME:
			parts.append("%s.%s=%s"
					% [frame.frame_id, field, _stamp_value(frame.get(field))])
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
##
## THE JAM STATE IS THE THIRD PART OF THE KEY (v1.83, S.q9). The Screamer is the
## negative of the FCS gear ladder, and P4.3's rule — "FCS is not a column" —
## points the same way for both: equipment shifts a delivery factor, it never adds
## a matrix dimension. So EW re-keys aim rather than growing the matrix, on the
## exact precedent of `Lethality.STATES` (shielded/cracked), which is how the
## Aegis was absorbed without a column of its own. Cost, stated: the aim cells
## double, six to twelve.
##
## DISCRETE EVEN THOUGH THE FIELD IS GRADED, and that is the same choice the
## shield made. A shield is a continuous pool modeled as two states because the
## two ENDS are what a weapon's answer inverts between; a jam is a continuous
## field modeled as two states for the identical reason. What the gradient buys
## lives in the fight, and the duel harness reports the mean jam it actually flew
## through so a reader can see how fairly a row was keyed.
const AIM_STATES: Array[String] = ["clear", "jammed"]

static func aim_key(frame_id: String, weapon: String,
		state: String = "clear") -> String:
	return "%s:%s:%s" % [frame_id, weapon, state]


static func evasion_key(weapon: String, type_id: String) -> String:
	return "%s:%s" % [weapon, type_id]


## Splash yield — bodies covered per ARRIVING burst, per weapon x target. Keyed
## like evasion because it is equally a property of the pair: the same fragment
## cloud swallows three gnats and exactly one aegis.
static func splash_key(weapon: String, type_id: String) -> String:
	return "%s:%s" % [weapon, type_id]


## LAYER 3b (Iteration 9 / S3): the player as a target, keyed THREAT x FRAME.
##
## The mirror image of `evasion_key`, and the key order says which side owns
## which half: an enemy row is `<weapon>:<type>` because the shot is ours and the
## dodge is theirs; a player row is `<type>:<frame>` because the shot is theirs
## and the dodge is ours.
##
## FRAME-KEYED, unlike the enemy-side evasion it mirrors — and that asymmetry is
## structural rather than an inconsistency. The enemy-evasion bench freezes the
## shooter, so a frozen Atlas and a frozen Kestrel fire identical shots and the
## airframe is inert BY CONSTRUCTION. Nothing freezes the player here: the frame
## is what the pilot is dodging in. This is the axis that makes an Atlas legible.
static func player_evasion_key(type_id: String, frame_id: String) -> String:
	return "%s:%s" % [type_id, frame_id]


## Stings landed per second of exposure, per CONTACT threat x frame. A separate
## table from `player_evasion` because it is a different QUANTITY, not a
## different value of the same one: a contact type has no cadence to miss with
## (`gnat_swarm._resolve_stings` spends a body the instant it arrives), so its
## delivery term is an arrival RATE, not a connect fraction. Layer 3a refuses to
## invent that number from a config and points at a bench for it; this is the
## key that bench writes to.
static func contact_key(type_id: String, frame_id: String) -> String:
	return "%s:%s" % [type_id, frame_id]


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


## THE SYMMETRIC HALF (Iteration 9 / S1-S3, S5): how long this frame lives under
## `count` bodies of one threat type — Layer 3a's arithmetic (their damage vs
## your hull and armor) times Layer 3b's measured connect rate (how much of it
## you actually eat). The exact mirror of `predict` above, arrow reversed, and it
## reuses that function's own shot-counting convention deliberately: one
## arithmetic, read in both directions.
##
##   shots_at_you = ceil(hits_to_kill_you / connect_rate)
##   seconds      = (shots_at_you - 1) * interval / count
##
## Three assumptions, named like the outgoing four:
##   1. CONCURRENCY IS LINEAR. `count` divides the clock and nothing else. Focus
##      fire, overkill on the last hit and armor's per-hit nature all bend that,
##      which is precisely why S5 makes concurrency a BENCH AXIS: this line is a
##      claim the duels can falsify, not a convenience.
##   2. THE THREAT AIMS PERFECTLY. `connect_rate` is measured against a bench
##      shooter laying an exact solution, so the enemy's own marksmanship —
##      `aim_jitter_deg`, its tracking loop, its lead logic — is NOT in this
##      number. That term is the un-measured mirror of `aim_quality`, and until
##      something varies it (P4.q2's veterancy is the stated trigger) it has one
##      value and would measure nothing. So a survival time here is a FLOOR: the
##      real threat aims worse than the bench does, and you live longer.
##   3. EXPOSURE IS CONTINUOUS. This is seconds spent inside the envelope with
##      the threat firing, not wall clock. S4's whole finding is that the two are
##      different — the Kestrel takes 0% hull off a turret it kills in 1.3 s not
##      by dodging but by not being there.
##
## Returns: mode, seconds (INF when it cannot kill you), shots_at_you, per_hit,
## hull_fraction, why.
static func survive(enemy: EnemyConfig, frame: FrameConfig,
		connect_rate: float, count: int = 1) -> Dictionary:
	var incoming: Dictionary = Lethality.incoming(enemy, frame)
	var bodies: int = maxi(count, 1)
	var out: Dictionary = {
		"mode": incoming["mode"],
		"seconds": INF,
		"shots_at_you": 0.0,
		"per_hit": float(incoming["per_hit"]),
		"hull_fraction": float(incoming.get("hull_fraction", 0.0)),
		"count": bodies,
		"why": String(incoming["why"]),
	}
	if not bool(incoming["kills"]):
		return out
	if incoming["mode"] == &"contact":
		# `connect_rate` is a RATE here (stings/second), not a fraction — the
		# contact_key table, not the player_evasion one. Feeding one where the
		# other belongs is the single way to misread this function, so it is
		# guarded rather than trusted: a rate under this floor means no bench
		# measurement was supplied.
		if connect_rate <= 0.001:
			out["why"] = "no measured sting rate for this pair"
			return out
		out["shots_at_you"] = float(incoming["shots"])
		out["seconds"] = float(incoming["shots"]) \
				/ (connect_rate * float(bodies))
		return out
	if connect_rate <= 0.0:
		out["why"] = "nothing connects: this threat cannot reach this frame"
		return out
	var shots_at_you: float = ceilf(float(incoming["shots"]) / connect_rate)
	out["shots_at_you"] = shots_at_you
	out["seconds"] = (shots_at_you - 1.0) * float(incoming["interval"]) \
			/ float(bodies)
	return out


static func band_for(ttk: float) -> String:
	for entry: Array in TTK_BANDS:
		if ttk <= float(entry[0]):
			return entry[1]
	return "--"


static func _unresolved(why: String) -> Dictionary:
	return {"band": "?", "ttk": INF, "shots_fired": 0.0, "hit_rate": 0.0,
			"cadence": 0.0, "why": why}
