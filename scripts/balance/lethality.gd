class_name Lethality
extends RefCounted

## Layer 1 of the balance model (GAMEPLAY-DESIGN v1.23, BALANCE.md): pure
## config arithmetic answering "if this weapon CONNECTS, what happens" —
## kill-or-never, shots to kill, cadence-limited TTK. No pilot, no physics,
## no scene anywhere in it: every number here is derived from CombatConfig x
## EnemyConfig by replaying the exact `Health.take` rules (threshold-gated
## shield, excess carry-through, regen after a quiet spell) against the
## weapon's own cadence.
##
## The one modeled loop is the shield exchange — a hit-by-hit replay, because
## regen between shots makes the shielded case genuinely stateful (EVERY arriving
## hit rewinds the regen clock, on the screen or on the exposed hull, exactly as
## health.gd does it). That is still config arithmetic in the
## BALANCE.md sense: deterministic, instant, and verified against the shipped
## Health node by the planted-shot bench (scripts/tests/lethality_check.gd).
##
## Deliberately NOT modeled: anything about hitting (that is Layer 2, delivery).
##
## LAYER 3a — INCOMING (Iteration 9 / S2, 2026-07-27). Being shot at used to be
## outside this file too, and that omission is what made the frame axis
## illegible: a frame cell bands "destroyed minus hull spent", the Atlas's whole
## virtue lives in the hull term, and nothing was ever measuring the hull term.
## The fix costs almost nothing, because the exchange loop below never cared
## WHOSE durability it was replaying — it reads six fields. So a "target" is now
## a plain durability block (`target_from_enemy` / `target_from_frame`) and
## `incoming()` points the same arithmetic the other way: THEIR weapon against
## YOUR frame. Same rules, same verification discipline, arrow reversed.
##
## Still not modeled here: whether their shot connects. That is Layer 3b (player
## evasion), measured by a bench, exactly as aim_quality is on the outgoing side.
##
## EnemyConfig.armor IS modeled as of Phase 4b: it stopped being a schema-only
## field the day the Atlas needed flat reduction to exist (P3.3), and this file
## mirrors the CODE, so it appears here the same day. Every roster value is
## still 0.0, which is why no shipped cell moved when it landed.

## Sentinel shot count for "this weapon cannot kill this target, ever".
const NEVER: int = -1
## Hit-loop cap: a shielded exchange that has not resolved after this many
## hits is a stalemate (regen outpaces the weapon) and reports NEVER.
const MAX_HITS: int = 1000


## The measured player weapons, in matrix-column order.
const WEAPONS: Array[String] = ["blaster", "missile", "flak"]


## One cell of the Layer 1 table. Returns:
##   kills: bool     — can this weapon kill this enemy at all
##   shots: int      — hits to kill (NEVER when kills is false)
##   ttk: float      — seconds from first hit to kill at the weapon's own
##                     cadence, first shot at t=0 (0.0 when kills is false)
##   interval: float — the weapon's own cadence, seconds between shots. The
##                     economy term: what makes nine gnats expensive for a
##                     3 s missile is this, not durability and not delivery.
##   why: String     — human-readable note when kills is false
## `damage_mult` is the RunMods layer; the baseline table uses 1.0, and every
## bench in the project passes 1.0, so the split below moved nothing here.
## It applies to the two GUN-family weapons only — missile.gd reads
## missile_damage raw, and this mirrors that, faithfully including the
## asymmetry. **The two guns have separate mods** (`damage_mult` for the
## blaster, `flak_damage_mult` for the pod, v1.86): a caller that ever passes a
## live RunMods must pass the one belonging to the weapon it named, or it will
## quietly model a blaster upgrade landing on flak — which is the exact bug the
## split fixed in the game.
static func versus(weapon: String, combat: CombatConfig, enemy: EnemyConfig,
		damage_mult: float = 1.0) -> Dictionary:
	return _fire(weapon, combat, enemy, damage_mult, false)


## THE STATE SPLIT (v1.25, from the user's reading: "the shield IS a target by
## itself, just like a hull of a ship"). A shielded type is not one target —
## it is two in sequence, and a weapon's answer can INVERT between them: the
## blaster is `--` against a shielded aegis and `++` against a cracked one.
## Averaging those into one cell destroys both facts.
##
## This is the genre's standard model, not an invention here: Halo's plasma-
## strips-shield / bullets-kill-flesh sandbox, Mass Effect's per-layer weapon
## multipliers, Destiny's match-game shields. Each defensive layer is its own
## target with its own effectiveness row.
##
## The payoff is that COMBOS BECOME DERIVABLE instead of exceptional (see
## `combo` below), which is what keeps them out of the per-weapon table where
## they would poison any arithmetic drawn from it.
##
##   shielded — the type as it arrives, shield up
##   cracked  — shield down, hull exposed (the window a burst opens)
##
## Unshielded types report identically for both states.
const STATES: Array[String] = ["shielded", "cracked"]


static func versus_state(weapon: String, combat: CombatConfig,
		enemy: EnemyConfig, state: String,
		damage_mult: float = 1.0) -> Dictionary:
	if state == "cracked":
		return versus(weapon, combat, cracked_config(enemy), damage_mult)
	return versus(weapon, combat, enemy, damage_mult)


## The same stat block with its shield spent. Used for the cracked-state row
## and as the finisher's target in a combo.
static func cracked_config(enemy: EnemyConfig) -> EnemyConfig:
	var cracked: EnemyConfig = enemy.duplicate() as EnemyConfig
	cracked.shield_max = 0.0
	cracked.shield_break_threshold = 0.0
	cracked.shield_regen = 0.0
	return cracked


## Hits to bring the shield down (NOT to kill) — the first leg of a combo.
## An unshielded target reports 0 shots: there is nothing to strip.
static func strip_shield(weapon: String, combat: CombatConfig,
		enemy: EnemyConfig, damage_mult: float = 1.0) -> Dictionary:
	return _fire(weapon, combat, enemy, damage_mult, true)


## The two-weapon answer: `strip` brings the shield down, `finish` kills the
## exposed hull. This is what P4.3 means in prose by "cracking opens a timed
## window where the gun finally matters — the combo, not the gun alone",
## expressed as arithmetic so it can be predicted rather than discovered.
##
## Assumes the finisher opens IMMEDIATELY once the shield drops. That is the
## honest reading for a pilot holding both triggers, and it is safe against
## regen for any shield whose `shield_regen_delay` exceeds the switch gap —
## but a hesitant follow-up loses the window, which this number does not model.
static func combo(strip: String, finish: String, combat: CombatConfig,
		enemy: EnemyConfig, damage_mult: float = 1.0) -> Dictionary:
	var leg_one: Dictionary = strip_shield(strip, combat, enemy, damage_mult)
	if not bool(leg_one["kills"]):
		return _never("cannot strip the shield: %s" % leg_one["why"])
	var leg_two: Dictionary = versus(finish, combat, cracked_config(enemy),
			damage_mult)
	if not bool(leg_two["kills"]):
		return _never("cannot kill the exposed hull: %s" % leg_two["why"])
	# The gap between the legs. Switching to a DIFFERENT weapon costs nothing
	# — separate cooldowns, both triggers already under the pilot's fingers —
	# but continuing with the SAME weapon must wait out its cadence, exactly
	# as it would have mid-burst. Without this a same-weapon "combo" reports
	# a faster kill than the identical solo row, which is how the omission
	# was caught: missile->missile said 3.0 s where solo says 6.0 s.
	var gap: float = float(leg_two["interval"]) if strip == finish else 0.0
	return {
		"kills": true,
		"shots": int(leg_one["shots"]) + int(leg_two["shots"]),
		"ttk": float(leg_one["ttk"]) + gap + float(leg_two["ttk"]),
		"interval": float(leg_two["interval"]),
		"strip_shots": int(leg_one["shots"]),
		"strip_ttk": float(leg_one["ttk"]),
		"finish_shots": int(leg_two["shots"]),
		"finish_ttk": float(leg_two["ttk"]),
		"why": "",
	}


## ---------- targets (the durability block, whoever owns it) ----------

## A target is these six numbers and nothing else. Making that explicit is what
## lets one verified exchange loop serve both directions of the model.
##
## MOUNTS COUNT AS HULL, and the reason is that they are not optional armour: a
## Phalanx routes every round to the nearest LIVING mount before the hull, and
## `_mount_facing` picks the nearest living one regardless of angle, so a pilot
## firing from any one bearing must strip the whole battery first. Six mounts of
## 100 in front of a 700 hull is one 1300-point sequence, and the model used to
## price 700 of it — the same family of blindness as v2.35's "a battery is not a
## gun", found from the other end. `mount_count` is 0 for every other type in the
## roster, so this term vanishes for all of them.
static func target_from_enemy(enemy: EnemyConfig) -> Dictionary:
	return {
		"hull": enemy.hull + float(maxi(enemy.mount_count, 0)) * enemy.mount_hull,
		"armor": enemy.armor,
		"shield_max": enemy.shield_max,
		"shield_break_threshold": enemy.shield_break_threshold,
		"shield_regen": enemy.shield_regen,
		"shield_regen_delay": enemy.shield_regen_delay,
	}


## The player, as a target. `FrameConfig.hull`/`armor` are live on the drone —
## `FlightController._ready` pushes both into its `Health` — so this mirrors
## shipped wiring, not a schema. No shield: no frame has one, and inventing
## fields for a defence nothing implements is how dead tunables start.
static func target_from_frame(frame: FrameConfig) -> Dictionary:
	return {
		"hull": frame.hull, "armor": frame.armor,
		"shield_max": 0.0, "shield_break_threshold": 0.0,
		"shield_regen": 0.0, "shield_regen_delay": 0.0,
	}


## ---------- Layer 3a: incoming ----------

## What ONE enemy type's weapon does to ONE player frame, if it connects:
## hits-to-kill-you, seconds-to-kill-you at that type's own cadence. The exact
## mirror of `versus`, and the term the frame axis was missing.
##
## THREE DELIVERY MODES, because the roster already has three and collapsing
## them would have made this layer lie on its first day:
##
##   &"ranged"  — a cadence weapon (`fire_rate > 0`): raider, turret. Sustained
##                fire, so ttk and dps are meaningful.
##   &"contact" — a CONSUMABLE sting (`fire_rate == 0`, `pack_size > 0`): the
##                gnat. `gnat_swarm._resolve_stings` calls `take_hit(damage)`
##                and then `body.die(false)` — each body spends ITSELF for one
##                bite. So a pack is a FINITE damage budget, not a rate, and
##                the arrival timing belongs to delivery, not to this file.
##                Reporting a ttk here would invent a cadence that does not
##                exist in any config.
##   &"none"    — no weapon at all (`damage == 0`): the aegis. The v1.72
##                finding as arithmetic — an enemy that cannot hurt you cannot
##                price your durability, so no frame can distinguish itself.
##
## The gnat is why `fire_rate == 0` must never be read as "harmless": it is the
## type the Atlas's armor exists for (P4.4, "heavy is ++ against gnat stings"),
## and a naive weaponless test would have deleted exactly the cell that proves
## flat reduction works.
static func incoming(enemy: EnemyConfig, frame: FrameConfig) -> Dictionary:
	var target: Dictionary = target_from_frame(frame)
	var per_hit: float = maxf(enemy.damage - frame.armor, 0.0)

	# A TYPE THAT *IS* THE ORDNANCE (the Lance, A5). It carries no gun — `damage`
	# and `fire_rate` are both 0 — and kills with a contact blast, so reading
	# `damage == 0` as harmless prices it at nothing against every frame.
	#
	# **Never read `damage == 0` as harmless.** That is the same lesson the gnat
	# taught one level down, where `fire_rate == 0` had to stop meaning harmless,
	# and it repeated here for exactly the same reason: the roster keeps growing
	# ways to arrive that are not a cadence.
	#
	# `payload` is what separates BEING ordnance from CARRYING it. A Lance spends
	# itself on you (payload 0, one body, one blast); an aegis spends bombs on
	# your GROUND (payload 3), which is priced against the war rather than against
	# your hull, and stays `none` here exactly as v1.72 decided.
	if enemy.damage <= 0.0 and enemy.bomb_damage > 0.0 and enemy.payload <= 0:
		var blast: float = maxf(enemy.bomb_damage - frame.armor, 0.0)
		var hits: int = NEVER
		if blast > 0.0:
			hits = int(ceil(frame.hull / blast))
		return {
			"mode": &"contact",
			"kills": blast >= frame.hull,
			"shots": hits,
			# No ttk, for the gnat's reason: how long it takes to ARRIVE is a
			# delivery property, measured by a bench, never read from a config.
			"ttk": 0.0,
			"interval": 0.0,
			"per_hit": blast,
			# The pre-armor figure, so `lethality_check` can PLANT the same hit
			# without knowing which config field this type keeps its damage in.
			# Planting `per_hit` would apply armor twice, since Health.take does it.
			"raw_per_hit": enemy.bomb_damage,
			"bodies": 1,
			"pack_damage": blast,
			"hull_fraction": minf(blast / maxf(frame.hull, 0.001), 1.0),
			"why": "" if blast >= frame.hull
					else ("%.0f blast at or under the %.0f armor"
					% [enemy.bomb_damage, frame.armor] if blast <= 0.0
					else "one blast spends %.0f against %.0f hull"
					% [blast, frame.hull]),
		}

	if enemy.damage <= 0.0:
		var idle: Dictionary = _never(
				"%s carries no weapon against the player" % enemy.type_id)
		idle["mode"] = &"none"
		idle["per_hit"] = 0.0
		idle["hull_fraction"] = 0.0
		return idle

	if enemy.fire_rate <= 0.0:
		# Contact: the whole pack, spent.
		var bodies: int = maxi(int(enemy.pack_size), 1)
		var budget: float = per_hit * float(bodies)
		var needed: int = NEVER
		if per_hit > 0.0:
			needed = int(ceil(frame.hull / per_hit))
		return {
			"mode": &"contact",
			"kills": budget >= frame.hull and per_hit > 0.0,
			"shots": needed,
			# No ttk: the arrival rate is a DELIVERY property (how fast the
			# cloud reaches you), measured by a bench, never read from a config.
			"ttk": 0.0,
			"interval": 0.0,
			"per_hit": per_hit,
			"raw_per_hit": enemy.damage,
			"bodies": bodies,
			"pack_damage": budget,
			"hull_fraction": minf(budget / maxf(frame.hull, 0.001), 1.0),
			"why": "" if budget >= frame.hull and per_hit > 0.0
					else ("%.0f dmg at or under the %.0f armor"
					% [enemy.damage, frame.armor] if per_hit <= 0.0
					else "a full pack of %d spends %.0f against %.0f hull"
					% [bodies, budget, frame.hull]),
		}

	# A TYPE WITH A BATTERY FIRES FROM ALL OF IT (A7's Phalanx). `fire_rate` is
	# ONE mount's cadence, so reading it as the body's prices a six-gun fortress
	# as a single turret — measured before this line existed, Layer 3a claimed
	# **20 hits over 23.8 s** to kill a Kestrel while the real body puts six
	# barrels on the same target.
	#
	# `mount_count` is 0 for every other type in the roster, so the max() leaves
	# them all untouched.
	#
	# It prices the FULL battery, which is the worst case for the player and goes
	# stale in their favour as mounts are stripped. That is the same convention
	# the directional shield gets — Layer 1 assumes you are in the arc — and for
	# the same reason: a durability model that flatters the target is the one that
	# gets somebody killed.
	var guns: float = float(maxi(enemy.mount_count, 1))
	var interval: float = 1.0 / (enemy.fire_rate * guns)
	var result: Dictionary = _exchange(enemy.damage, interval, target, false)
	result["mode"] = &"ranged"
	result["per_hit"] = per_hit
	result["dps"] = per_hit * enemy.fire_rate * guns
	# Fraction of hull spent per second under sustained fire — the term a frame
	# cell actually bands, in the unit it bands it in.
	result["hull_fraction"] = minf(
			result["dps"] / maxf(frame.hull, 0.001), 1.0)
	return result


## Seconds this frame survives under sustained fire from `count` RANGED bodies,
## all connecting. The durability readout in the unit the fight uses — how long
## can I stay in the envelope — and what being outnumbered (S5) erodes.
##
## Linear in `count` by construction, and that linearity is a CLAIM the
## concurrency bench can falsify, not a convenience: focus fire, overkill on
## the killing blow and armor's per-hit nature all bend it.
##
## INF for contact and weaponless types — a pack that cannot spend more than
## your hull never kills you however long you loiter, and saying "3.2 seconds"
## about a gnat cloud would be inventing a cadence.
static func survival_seconds(enemy: EnemyConfig, frame: FrameConfig,
		count: int = 1) -> float:
	if count <= 0:
		return INF
	var solo: Dictionary = incoming(enemy, frame)
	if solo["mode"] != &"ranged" or not bool(solo["kills"]):
		return INF
	return float(solo["ttk"]) / float(count)


## Bolts a held trigger gets before the sink locks out. 0 = no heat model.
static func burst_shots(combat: CombatConfig) -> int:
	if combat.heat_per_shot <= 0.0 or combat.heat_capacity <= 0.0:
		return 0
	return maxi(int(floor(combat.heat_capacity / combat.heat_per_shot)), 1)


## Seconds the gun is dead after a full sink: the quiet time before venting
## starts, plus the time to shed down to the reset fraction.
static func vent_seconds(combat: CombatConfig) -> float:
	if burst_shots(combat) <= 0 or combat.heat_cool_rate <= 0.0:
		return 0.0
	var shed: float = combat.heat_capacity * (1.0 - combat.heat_reset_fraction)
	return combat.heat_vent_delay + shed / combat.heat_cool_rate


## ---------- Layer 1 LOCATED: the component model arrives (E8) ----------

## E8 states the bill against this file directly: *"a component model breaks the
## assumption underneath [Layer 1] — 'hits to kill' stops being one number and
## becomes a distribution over where the hits land."*
##
## WHAT IS MIRRORED, and it is mirrored rather than shared on purpose.
## `FlightController._apply_located` takes the round's bearing out to the hull's
## edge and splits it across every ROUTED component inside
## `DamageConfig.hit_footprint_m`, weighted by closeness and normalised so damage
## is conserved. That footprint is in METRES and does not scale with the airframe,
## which is the whole of E4.3: a 0.28 m Kestrel has one round straddle three
## rotors while a 3.0 m Roc has the same round take exactly one. The functions
## below re-derive that split from the two resources alone — no drone, no tree, no
## physics, exactly like the rest of Layer 1 — and `lethality_check` plants real
## shots at named bearings to prove the two agree. The calculator is allowed to be
## a copy precisely because a bench compares it against the shipped code; that is
## the same discipline the shield exchange has run under since v1.23.
##
## **THE INPUT IS POST-ARMOUR HULL DAMAGE, AND GETTING THAT WRONG WOULD BE
## INVISIBLE.** `main._on_player_damaged` is wired to `Health.damaged`, which emits
## what actually reached the hull *after* `FrameConfig.armor` — so the Atlas's
## 3.0 of plating shields its rotors as well as its structure, and a model fed the
## enemy's raw `damage` would price its motors 60% too fragile. Every entry point
## here names the parameter `hull_damage` for that reason, and `located_incoming`
## takes it from `incoming()`'s own `per_hit` rather than from a config.

## Bearings walked for every figure below that is an EXPECTATION rather than an
## answer at one aspect. 72 is every 5 degrees, which resolves a quad's 90-degree
## symmetry and a hexa's 60-degree one while landing on neither's rotors alone —
## a coarser sweep that sampled only the arms would report a frame as uniform when
## it is not, which is the one sampling artefact that would flatter this model.
##
## Bearing 0 is the NOSE and it runs clockwise, matching `MotorModel._ring`'s own
## convention (`x = sin`, `z = -cos`, front is body -Z) so that a bearing quoted by
## this file and one quoted by the airframe mean the same thing.
const BEARING_SAMPLES: int = 72


## Body-space direction a round arriving on `bearing_deg` came FROM.
static func bearing_vector(bearing_deg: float) -> Vector3:
	var radians: float = deg_to_rad(bearing_deg)
	return Vector3(sin(radians), 0.0, -cos(radians))


## WHERE ONE ROUND LANDS: each routed component's share of a single hit, in
## `parts` order, summing to 1. The mirror of `_apply_located`'s weighting.
##
## Returns empty for a DIRECTIONLESS hit, which is not an oversight but E5's
## distinction: a crash has no bearing, loads the whole airframe through
## `_apply_crash`, and is not a located event at all.
static func hit_shares(parts: Array[AirframeComponents.Part], body_m: float,
		footprint: float, from_body: Vector3) -> PackedFloat32Array:
	var shares := PackedFloat32Array()
	if parts.is_empty():
		return shares
	var bearing := Vector3(from_body.x, 0.0, from_body.z)
	if bearing.length_squared() < 0.000001:
		return shares
	# The impact point is that bearing taken out to the hull's own edge, exactly
	# as the live path computes it. Half of `body_m`, never of `arm_length`: the
	# round meets the airframe, not the motor ring.
	var impact: Vector3 = bearing.normalized() * (body_m * 0.5)
	var weights: Array[float] = []
	var total: float = 0.0
	var nearest: int = 0
	var nearest_distance: float = INF
	for i: int in parts.size():
		var pos := Vector3(parts[i].position.x, 0.0, parts[i].position.z)
		var distance: float = pos.distance_to(impact)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = i
		var weight: float = 0.0
		if footprint > 0.0:
			weight = maxf(1.0 - distance / footprint, 0.0)
		weights.append(weight)
		total += weight
	shares.resize(parts.size())
	if total <= 0.0:
		# The large airframe's ordinary case: nothing falls inside the footprint,
		# so the nearest component takes the whole round. A separate branch in the
		# live code too, and the one that makes a Roc's hits singular.
		shares[nearest] = 1.0
		return shares
	for i: int in parts.size():
		shares[i] = weights[i] / total
	return shares


## Motor capability one hit strips BEFORE it is divided among components —
## `apply_hit_to_motors`' own three lines, severity dial included. 0 when the
## dial is off, which is what makes severity 0 a genuine arcade floor rather than
## a scaling of one.
static func located_amount(hull_damage: float, damage: DamageConfig) -> float:
	if damage == null or damage.severity <= 0.0 or hull_damage <= 0.0:
		return 0.0
	return minf(hull_damage * damage.motor_damage_scale,
			damage.motor_damage_max) * damage.severity


## E8'S SECOND OUTPUT, AT ONE ASPECT: which component fails first under repeated
## hits arriving on `from_body`, and after how many.
##
## A component's health is a 0-to-1 capability and plating is flat against it
## (`_damage_component`), so a hit costs a component
## `max(share x amount - armor, 0)` and the count is that divided into 1. Flat
## plating is why this cannot be read off the share alone: a round split three
## ways can have every one of its small shares eaten whole, which is exactly the
## interaction task 4 measured.
##
## The HELD aspect is the honest case for E7's *"if in two different runs i get
## the same engine hit — thats a lession to be learned"*: a pursuer sits in one
## part of your sky and keeps putting rounds into the same corner.
static func first_failure_at(frame: FrameConfig, damage: DamageConfig,
		hull_damage: float, from_body: Vector3) -> Dictionary:
	var config: FlightConfig = frame.flight_config if frame != null else null
	var parts: Array[AirframeComponents.Part] = \
			AirframeComponents.routed_layout(frame, config)
	var amount: float = located_amount(hull_damage, damage)
	if parts.is_empty():
		return _no_failure("this airframe routes no located damage to anything")
	if amount <= 0.0:
		return _no_failure("no located damage: %.1f hull damage at severity %.2f"
				% [hull_damage, damage.severity if damage != null else 0.0])
	var shares: PackedFloat32Array = hit_shares(parts, config.body_m,
			damage.hit_footprint_m, from_body)
	if shares.is_empty():
		return _no_failure("a directionless hit is a crash, not a located round (E5)")
	return _failure_from_shares(parts, shares, amount, hull_damage)


## The per-component arithmetic, over shares that have already been computed.
## Shared by the single-aspect entry point and the sweep so the two can never
## drift — the same reason `_exchange` is one loop serving both directions of the
## model.
static func _failure_from_shares(parts: Array[AirframeComponents.Part],
		shares: PackedFloat32Array, amount: float,
		hull_damage: float) -> Dictionary:
	var soonest: int = -1
	var soonest_hits: int = MAX_HITS + 1
	var soonest_through: float = 0.0
	for i: int in parts.size():
		var through: float = maxf(shares[i] * amount - parts[i].armor, 0.0)
		if through <= 0.0:
			continue
		var hits: int = int(ceil(1.0 / through))
		# Ties keep the LOWEST index rather than the last one seen. A quad-X is
		# symmetric about its own diagonals, so exact ties are ordinary here and a
		# picker that drifted with iteration order would make this file's answers
		# depend on `TABLE`'s row order.
		if hits < soonest_hits:
			soonest_hits = hits
			soonest = i
			soonest_through = through
	if soonest < 0 or soonest_hits > MAX_HITS:
		return _no_failure(
				"plating turns away every share of a %.1f-point hit on this bearing"
				% hull_damage)
	var part: AirframeComponents.Part = parts[soonest]
	return {
		"component": part.id,
		"kind": part.kind,
		"index": part.index,
		"hits": soonest_hits,
		"per_hit": soonest_through,
		"share": shares[soonest],
		"why": "",
	}


## E8'S SECOND OUTPUT AS AN EXPECTATION: the same question, taken over the
## hit-location distribution instead of at one stated aspect.
##
## **THE DISTRIBUTION IS OVER WHICH ASPECT THE FIRE HOLDS, NOT OVER EACH ROUND'S
## BEARING, AND THAT CHOICE IS THE WHOLE MEANING OF THE NUMBER.** Averaging
## per-ROUND would be the wrong model and quietly the degenerate one: separation
## conserves damage, so under bearings drawn fresh for every round each rotor
## accrues exactly `amount / rotor_count` per hit on every airframe in the roster,
## and the frame ladder collapses to a single number. Concentration lives in the
## VARIANCE, and a mean over rounds is precisely what destroys it. So each sample
## here is a whole engagement fought from one bearing, and the expectation is over
## where the shooter was.
##
## Both ends are reported beside the mean, because BALANCE.md's own grammar for a
## graded thing is to state the two ends and let the fight live between them:
##   `soonest_hits` — the aspect that costs a component fastest (the pilot's worst)
##   `latest_hits`  — the aspect that costs one slowest
##   `spread_hits`  — the diffuse floor: fire from everywhere at once, where no
##                    component concentrates anything. This is the degenerate case
##                    described above, reported ON PURPOSE as the datum the held
##                    aspects are worth against — on an unplated frame it is the
##                    same number for every airframe in the roster, and that
##                    identity is the clearest possible statement that E4.3's
##                    content is concentration and nothing else.
##
## `hits` is a FLOAT here and an int in `first_failure_at` — an expectation over
## aspects is not a hit count and rounding it would hide exactly the differences
## between frames this exists to report. Read `soonest_hits` when an integer is
## wanted; it is the aspect that actually happens to somebody.
static func expected_first_failure(frame: FrameConfig, damage: DamageConfig,
		hull_damage: float) -> Dictionary:
	var config: FlightConfig = frame.flight_config if frame != null else null
	var parts: Array[AirframeComponents.Part] = \
			AirframeComponents.routed_layout(frame, config)
	var amount: float = located_amount(hull_damage, damage)
	if parts.is_empty() or amount <= 0.0:
		var blank: Dictionary = first_failure_at(frame, damage, hull_damage,
				bearing_vector(0.0))
		blank["soonest_hits"] = NEVER
		blank["soonest_bearing_deg"] = 0.0
		blank["latest_hits"] = NEVER
		blank["spread_hits"] = NEVER
		blank["bearings"] = 0
		return blank
	var total_hits: float = 0.0
	var total_share: float = 0.0
	var counted: int = 0
	var soonest: Dictionary = {}
	var soonest_bearing: float = 0.0
	var latest_hits: int = NEVER
	# Per-component accrual summed across the sweep — the diffuse end.
	var accrued: PackedFloat32Array = PackedFloat32Array()
	accrued.resize(parts.size())
	for sample: int in BEARING_SAMPLES:
		# HALF-OFFSET, and it is a correctness fix rather than a nicety. A sweep
		# starting at 0 lands exactly on a quad's four arms AND exactly on the four
		# bearings where two rotors are equidistant, so the tie-break — which
		# exists for determinism — decides a twentieth of the samples and skews
		# `spread_hits` by 6%. Measured: the Roc read 79 hits where conservation
		# says 84, while the Kestrel read the correct 84, which looked like a real
		# difference between two frames and was an artefact of where the ruler's
		# marks fell. Sampling a symmetric object on its own symmetry axes is the
		# oldest way to measure the instrument instead of the thing.
		var bearing_deg: float = 360.0 * (float(sample) + 0.5) \
				/ float(BEARING_SAMPLES)
		var from_body: Vector3 = bearing_vector(bearing_deg)
		# The layout is built ONCE for the whole sweep and the shares once per
		# bearing. Going back through `first_failure_at` per sample would rebuild
		# both 72 times over, and Layer 1's contract is that it is instant.
		var shares: PackedFloat32Array = hit_shares(parts, config.body_m,
				damage.hit_footprint_m, from_body)
		var cell: Dictionary = _failure_from_shares(parts, shares, amount,
				hull_damage)
		for i: int in parts.size():
			accrued[i] += maxf(shares[i] * amount - parts[i].armor, 0.0)
		if int(cell["hits"]) == NEVER:
			continue
		var hits: int = int(cell["hits"])
		total_hits += float(hits)
		total_share += float(cell["share"])
		counted += 1
		if soonest.is_empty() or hits < int(soonest["hits"]):
			soonest = cell
			soonest_bearing = bearing_deg
		if latest_hits == NEVER or hits > latest_hits:
			latest_hits = hits
	if counted <= 0:
		var none: Dictionary = _no_failure(
				"no bearing on this airframe can fail a component with %.1f-point hits"
				% hull_damage)
		none["soonest_hits"] = NEVER
		none["soonest_bearing_deg"] = 0.0
		none["latest_hits"] = NEVER
		none["spread_hits"] = NEVER
		none["bearings"] = BEARING_SAMPLES
		return none
	var best_accrual: float = 0.0
	for i: int in parts.size():
		best_accrual = maxf(best_accrual, accrued[i] / float(BEARING_SAMPLES))
	var spread: int = NEVER
	if best_accrual > 0.0 and 1.0 / best_accrual <= float(MAX_HITS):
		spread = int(ceil(1.0 / best_accrual))
	var result: Dictionary = soonest.duplicate()
	# The scalar E8 asks for: hits to the first failure, expected over aspect.
	result["hits"] = total_hits / float(counted)
	result["share"] = total_share / float(counted)
	result["soonest_hits"] = int(soonest["hits"])
	result["soonest_bearing_deg"] = soonest_bearing
	result["latest_hits"] = latest_hits
	result["spread_hits"] = spread
	result["bearings"] = counted
	return result


## E8'S FIRST OUTPUT, AND THE HONEST ANSWER IS NOT THE ONE E8 EXPECTED.
##
## E8 asks Layer 1 to keep *"a scalar expected hits-to-kill, computed under the
## hit-location distribution"*, on the reasoning that a component model turns one
## number into a distribution. **In the model that actually shipped it does not,
## and this file mirrors what shipped.** Two facts decide it, and both are E5's
## and E.q3's rather than this file's:
##
##  - **Nothing routed is lethal.** The only components a located hit can reach
##    are the rotors, and a rotor at zero still makes `motor_min_thrust` of its
##    share — every frame on the roster hovers with all four dead. Losing them all
##    is a flight problem, never a death.
##  - **What kills you is the structure pool**, which E5 keeps *undifferentiated
##    on purpose* — it is the whole airframe, so it has no location for a
##    distribution to be over.
##
## So `expected_shots` equals the structural number, and the instrument says so
## out loud instead of dressing an unchanged figure in a new word. **The condition
## that would change it is written down rather than built**: E.q6's detonating
## magazine is the one proposed component whose loss is instantly fatal, and it is
## PINNED, not shipped. Building the machinery for it now would be a failure mode
## E9 and E10 step 2 both forbid.
##
## `fails_before_death` is where the pair earns its keep, and it is the number a
## pilot actually experiences: does any aspect cost you a rotor while you are
## still alive to fly it?
static func located_incoming(enemy: EnemyConfig, frame: FrameConfig,
		damage: DamageConfig) -> Dictionary:
	var structural: Dictionary = incoming(enemy, frame)
	# Post-armour, taken from the structural cell rather than from `enemy.damage`,
	# so the three arrival modes (ranged / contact / none) each hand over the hit
	# THEY define and this function never has to know which one it got.
	var hull_damage: float = float(structural.get("per_hit", 0.0))
	var failure: Dictionary = expected_first_failure(frame, damage, hull_damage)
	var shots: int = int(structural["shots"])
	var soonest: int = int(failure["soonest_hits"])
	return {
		"mode": structural["mode"],
		"hull_damage": hull_damage,
		"expected_shots": shots,
		"located_lethal": false,
		"why_expected": "no routed component's loss is fatal, so hits-to-kill is the structure pool's (E5); E.q6's magazine is the pinned exception",
		"first_failure": failure,
		"fails_before_death": soonest != NEVER and shots != NEVER and soonest < shots,
	}


static func _no_failure(why: String) -> Dictionary:
	return {"component": &"", "kind": &"", "index": -1, "hits": NEVER,
			"per_hit": 0.0, "share": 0.0, "why": why}


static func _fire(weapon: String, combat: CombatConfig, enemy: EnemyConfig,
		damage_mult: float, stop_at_shield_down: bool) -> Dictionary:
	match weapon:
		"blaster":
			# THE DUTY CYCLE, and R7's promise kept: this file used to assume
			# infinite sustained fire, which stopped being true the moment the
			# blaster grew a heat sink. A kill that needs more bolts than one
			# burst holds now pays for the vent, and — the interaction worth
			# having — a shield REGENERATES during that vent, through the same
			# loop that already credits regen between shots.
			#
			# Sustained fire never cools (the gap between bolts is under
			# `heat_vent_delay`), which is exactly what makes a burst an exact
			# integer instead of a simulation.
			return _exchange(combat.projectile_damage * damage_mult,
					1.0 / maxf(combat.fire_rate, 0.001), target_from_enemy(enemy),
					stop_at_shield_down, burst_shots(combat), vent_seconds(combat))
		"missile":
			# The launcher's cooldown IS the missile's cadence: unlike the
			# blaster it cannot volley, which is the whole gnat story.
			return _exchange(combat.missile_damage,
					maxf(combat.missile_cooldown, 0.001), target_from_enemy(enemy),
					stop_at_shield_down)
		"flak":
			# PER BODY, exactly like every other column. The fact that one flak
			# burst pays for several bodies at once is NOT lethality — it is a
			# delivery yield (`splash`, BalancePrediction), measured against a
			# real pack rather than asserted here. Layer 1 stays "if this weapon
			# connects with a target, what happens to THAT target", or the
			# state-split and combo arithmetic drawn from it stop being clean.
			#
			# Note the shape this gives the column for free: 10 damage sits under
			# the aegis's 40 break threshold, so flak reports NEVER against a
			# shielded bomber through the same branch that hard-counters the chip
			# gun. P4.3's "useless tonnage against shields" is not special-cased
			# anywhere — it falls out of one number being small.
			return _exchange(combat.flak_damage * damage_mult,
					1.0 / maxf(combat.flak_fire_rate, 0.001), target_from_enemy(enemy),
					stop_at_shield_down)
	push_error("Lethality: unknown weapon '%s'" % weapon)
	return {}


## Replay Health.take at the weapon's cadence: hit at t=0, then every
## `interval` seconds, with shield regen credited for the part of each
## interval after the regen delay expires.
##
## `stop_at_shield_down` ends the replay the moment the shield reaches zero
## instead of continuing into the hull — the strip leg of a combo. It shares
## this loop rather than getting its own so the two can never drift apart on
## the regen rules, which is the whole discipline of this file.
##
## `burst_shots` / `burst_pause` model a heat-limited weapon: after every
## `burst_shots` bolts the clock jumps by `burst_pause` while the gun vents.
## 0 means no limit, which is every weapon but the blaster. The pause lands
## BETWEEN bursts, so a kill inside the first one never pays for a vent it
## never reached — and because the pause goes through the same clock as the
## intervals, shield regen is credited across it for free.
static func _exchange(damage: float, interval: float, target: Dictionary,
		stop_at_shield_down: bool = false, burst_shots: int = 0,
		burst_pause: float = 0.0) -> Dictionary:
	if damage <= 0.0:
		return _never("zero damage", interval)
	var hull: float = float(target["hull"])
	var armor: float = float(target["armor"])
	var shield_max: float = float(target["shield_max"])
	var break_threshold: float = float(target["shield_break_threshold"])
	var regen: float = float(target["shield_regen"])
	var regen_delay: float = float(target["shield_regen_delay"])
	var shield: float = shield_max
	# Seconds until regen resumes. Every arriving hit rewinds it, so staying on a
	# cracked target is what holds the window open.
	var regen_wait: float = 0.0
	# A real clock rather than hits x interval, because a vent makes the two
	# different numbers.
	var elapsed: float = 0.0
	for hit: int in MAX_HITS:
		if hit > 0:
			var gap: float = interval
			if burst_shots > 0 and hit % burst_shots == 0:
				gap += burst_pause
			elapsed += gap
			# Time passes between hits: the wait runs down, then regen runs
			# for whatever is left of the gap.
			var regen_time: float = maxf(gap - regen_wait, 0.0)
			regen_wait = maxf(regen_wait - gap, 0.0)
			if regen_time > 0.0:
				shield = minf(shield + regen * regen_time, shield_max)
		var amount: float = damage
		# ANY arriving hit rewinds the regen clock, on the screen or on the exposed
		# hull — `health.gd`'s rule as of 2026-08-07, and this line has to move with
		# it or the model stops describing the component. `lethality_check` is what
		# noticed: it plants shots into a real `Health` and compares, and the fix to
		# the component alone read as `predicted 8 hits, planted 5`.
		if shield_max > 0.0:
			regen_wait = regen_delay
		if shield > 0.0:
			if amount < break_threshold:
				# Absorbed outright — and since absorbed hits never lower the
				# shield, no number of them ever will. The P4.3 chip-gun story
				# in one branch.
				return _never("%.0f dmg under the %.0f break threshold"
						% [amount, break_threshold], interval)
			var excess: float = amount - shield
			shield = maxf(shield - amount, 0.0)
			if stop_at_shield_down and shield <= 0.0:
				return {"kills": true, "shots": hit + 1,
						"ttk": elapsed, "interval": interval, "why": ""}
			if excess <= 0.0:
				continue
			amount = excess
		elif stop_at_shield_down:
			# Nothing to strip: an unshielded target costs zero shots to open.
			return {"kills": true, "shots": 0, "ttk": 0.0,
					"interval": interval, "why": ""}
		# The hull's flat plating, applied to whatever the shield let through —
		# health.gd's order exactly.
		amount = maxf(amount - armor, 0.0)
		if amount <= 0.0:
			# NEVER only when the weapon's FULL hit cannot get through the
			# plating; that is a kill-or-never verdict of the same kind as the
			# shield threshold, and worth reporting before the loop spends 1000
			# hits rediscovering it. A shield CARRY-THROUGH eaten by armor is a
			# different thing entirely — a wasted sliver on the hit that broke
			# the screen, with the next hit arriving at full damage against a
			# shield that is now down. Verdicting on `amount` here would have
			# called that combination unkillable.
			if damage <= armor:
				return _never("%.0f dmg at or under the %.0f armor"
						% [damage, armor], interval)
			continue
		hull -= amount
		if hull <= 0.0:
			return {"kills": true, "shots": hit + 1,
					"ttk": elapsed, "interval": interval, "why": ""}
	return _never("stalemate: regen outpaces the weapon over %d hits"
			% MAX_HITS, interval)


static func _never(why: String, interval: float = 0.0) -> Dictionary:
	return {"kills": false, "shots": NEVER, "ttk": 0.0,
			"interval": interval, "why": why}
