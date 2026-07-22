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
## regen between shots makes the shielded case genuinely stateful (the regen
## clock resets only on shield-TOUCHING hits; hull hits leave it running,
## exactly as health.gd does it). That is still config arithmetic in the
## BALANCE.md sense: deterministic, instant, and verified against the shipped
## Health node by the planted-shot bench (scripts/tests/lethality_check.gd).
##
## Deliberately NOT modeled: EnemyConfig.armor (declared but applied nowhere
## in the damage pipeline — this file mirrors the CODE, not the schema) and
## anything about hitting (that is Layer 2, delivery).

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
## `damage_mult` is the RunMods layer; the baseline table uses 1.0. It applies
## to the two GUN-family weapons only (blaster, flak) — missile.gd reads
## missile_damage raw, and this mirrors that, faithfully including the asymmetry.
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


static func _fire(weapon: String, combat: CombatConfig, enemy: EnemyConfig,
		damage_mult: float, stop_at_shield_down: bool) -> Dictionary:
	match weapon:
		"blaster":
			return _exchange(combat.projectile_damage * damage_mult,
					1.0 / maxf(combat.fire_rate, 0.001), enemy,
					stop_at_shield_down)
		"missile":
			# The launcher's cooldown IS the missile's cadence: unlike the
			# blaster it cannot volley, which is the whole gnat story.
			return _exchange(combat.missile_damage,
					maxf(combat.missile_cooldown, 0.001), enemy,
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
					1.0 / maxf(combat.flak_fire_rate, 0.001), enemy,
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
static func _exchange(damage: float, interval: float, enemy: EnemyConfig,
		stop_at_shield_down: bool = false) -> Dictionary:
	if damage <= 0.0:
		return _never("zero damage", interval)
	var hull: float = enemy.hull
	var shield: float = enemy.shield_max
	# Seconds until regen resumes; only shield-touching hits rewind it.
	var regen_wait: float = 0.0
	for hit: int in MAX_HITS:
		if hit > 0:
			# Time passes between hits: the wait runs down, then regen runs
			# for whatever is left of the interval.
			var regen_time: float = maxf(interval - regen_wait, 0.0)
			regen_wait = maxf(regen_wait - interval, 0.0)
			if regen_time > 0.0:
				shield = minf(shield + enemy.shield_regen * regen_time,
						enemy.shield_max)
		var amount: float = damage
		if shield > 0.0:
			regen_wait = enemy.shield_regen_delay
			if amount < enemy.shield_break_threshold:
				# Absorbed outright — and since absorbed hits never lower the
				# shield, no number of them ever will. The P4.3 chip-gun story
				# in one branch.
				return _never("%.0f dmg under the %.0f break threshold"
						% [amount, enemy.shield_break_threshold], interval)
			var excess: float = amount - shield
			shield = maxf(shield - amount, 0.0)
			if stop_at_shield_down and shield <= 0.0:
				return {"kills": true, "shots": hit + 1,
						"ttk": float(hit) * interval, "interval": interval,
						"why": ""}
			if excess <= 0.0:
				continue
			amount = excess
		elif stop_at_shield_down:
			# Nothing to strip: an unshielded target costs zero shots to open.
			return {"kills": true, "shots": 0, "ttk": 0.0,
					"interval": interval, "why": ""}
		hull -= amount
		if hull <= 0.0:
			return {"kills": true, "shots": hit + 1,
					"ttk": float(hit) * interval, "interval": interval,
					"why": ""}
	return _never("stalemate: regen outpaces the weapon over %d hits"
			% MAX_HITS, interval)


static func _never(why: String, interval: float = 0.0) -> Dictionary:
	return {"kills": false, "shots": NEVER, "ttk": 0.0,
			"interval": interval, "why": why}
