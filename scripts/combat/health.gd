class_name Health
extends Node

## Reusable hit-point component (roadmap M2). The owner forwards take_hit()
## here; whoever orchestrates the entity (main for the player, turret.gd for
## turrets) connects the signals.
##
## SHIELDS (GAMEPLAY-DESIGN P4.1 "shielded", the Aegis's defining trait) are
## opt-in: shield_max 0 leaves this a plain hit-point pool, which is what the
## player and every other type still use.
##
## The shield is a THRESHOLD GATE, not a second pool to grind down. While it
## is up, any hit landing under break_threshold splashes off entirely — it
## does not chip, so no amount of sustained small-arms fire adds up. Only a
## hit at or above the threshold takes shield points, and the shield only
## regenerates after a quiet spell. That single rule is the whole P4.3 story:
## chip guns are hard-countered, burst weapons and missiles are the answer,
## and cracking the shield opens a timed window where the gun finally matters.

signal damaged(amount: float, remaining: float)
signal died
## Every hit that ARRIVES, before any shield/hull accounting — the delivery
## benches' connect counter. Neither `damaged` nor `shield_absorbed` covers a
## shield-BREAKING hit with no excess (it emits only shield_broken), so
## counting arrivals from the outcome signals undercounts exactly the hits
## the aegis exists to demand.
signal struck(amount: float)
## A hit bounced off the shield — the "why isn't my gun working" telegraph.
signal shield_absorbed(amount: float)
## The shield went down; the hull is exposed until regen brings it back.
signal shield_broken

@export var max_health: float = 100.0
@export var shield_max: float = 0.0
@export var shield_break_threshold: float = 0.0
@export var shield_regen: float = 0.0
@export var shield_regen_delay: float = 0.0

var current: float
var alive: bool = true
var shield: float = 0.0

var _regen_wait: float = 0.0


func _ready() -> void:
	current = max_health
	shield = shield_max
	set_physics_process(shield_max > 0.0)


func configure_shield(config: EnemyConfig) -> void:
	shield_max = config.shield_max
	shield_break_threshold = config.shield_break_threshold
	shield_regen = config.shield_regen
	shield_regen_delay = config.shield_regen_delay
	shield = shield_max
	set_physics_process(shield_max > 0.0)


func shielded() -> bool:
	return shield > 0.0


func _physics_process(delta: float) -> void:
	if not alive or shield >= shield_max:
		return
	_regen_wait = maxf(_regen_wait - delta, 0.0)
	if _regen_wait <= 0.0:
		shield = minf(shield + shield_regen * delta, shield_max)


func take(amount: float) -> void:
	if not alive:
		return
	struck.emit(amount)
	if shield > 0.0:
		_regen_wait = shield_regen_delay
		# Under the threshold: the shield shrugs it off completely. Deliberately
		# not a partial absorb — a shield that leaks would make chip fire a slow
		# win, which is exactly the loadout this type exists to punish.
		if amount < shield_break_threshold:
			shield_absorbed.emit(amount)
			return
		# Over the threshold: spend the shield and carry the EXCESS through to
		# the hull. Letting a 2-point sliver of regenerated shield swallow a
		# whole missile made the answer weapon worse the closer it got to
		# winning, and turned a clean burst into wasted tonnage.
		var excess: float = amount - shield
		shield = maxf(shield - amount, 0.0)
		if shield <= 0.0:
			shield_broken.emit()
		if excess <= 0.0:
			return
		amount = excess
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, current)
	if current <= 0.0:
		alive = false
		died.emit()


func heal(amount: float) -> void:
	if not alive:
		return
	current = minf(current + amount, max_health)


func revive() -> void:
	current = max_health
	shield = shield_max
	_regen_wait = 0.0
	alive = true
