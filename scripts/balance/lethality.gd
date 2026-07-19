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
const WEAPONS: Array[String] = ["blaster", "missile"]


## One cell of the Layer 1 table. Returns:
##   kills: bool     — can this weapon kill this enemy at all
##   shots: int      — hits to kill (NEVER when kills is false)
##   ttk: float      — seconds from first hit to kill at the weapon's own
##                     cadence, first shot at t=0 (0.0 when kills is false)
##   why: String     — human-readable note when kills is false
## `damage_mult` is the RunMods layer; the baseline table uses 1.0. It applies
## to the blaster only — missile.gd reads missile_damage raw, and this mirrors
## that, faithfully including the asymmetry.
static func versus(weapon: String, combat: CombatConfig, enemy: EnemyConfig,
		damage_mult: float = 1.0) -> Dictionary:
	match weapon:
		"blaster":
			return _exchange(combat.projectile_damage * damage_mult,
					1.0 / maxf(combat.fire_rate, 0.001), enemy)
		"missile":
			return _exchange(combat.missile_damage,
					maxf(combat.missile_cooldown, 0.001), enemy)
	push_error("Lethality.versus: unknown weapon '%s'" % weapon)
	return {}


## Replay Health.take at the weapon's cadence: hit at t=0, then every
## `interval` seconds, with shield regen credited for the part of each
## interval after the regen delay expires.
static func _exchange(damage: float, interval: float,
		enemy: EnemyConfig) -> Dictionary:
	if damage <= 0.0:
		return _never("zero damage")
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
						% [amount, enemy.shield_break_threshold])
			var excess: float = amount - shield
			shield = maxf(shield - amount, 0.0)
			if excess <= 0.0:
				continue
			amount = excess
		hull -= amount
		if hull <= 0.0:
			return {"kills": true, "shots": hit + 1,
					"ttk": float(hit) * interval, "why": ""}
	return _never("stalemate: regen outpaces the weapon over %d hits"
			% MAX_HITS)


static func _never(why: String) -> Dictionary:
	return {"kills": false, "shots": NEVER, "ttk": 0.0, "why": why}
