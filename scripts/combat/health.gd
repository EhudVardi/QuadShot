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
## Flat damage subtracted from whatever reaches the HULL (the P4.1 "armored"
## model; the Atlas's innate durability, P3.3). Layered UNDER the shield, not
## beside it: the shield gate sees the full incoming hit, so armor never
## changes whether a weapon can crack a screen — only what gets through after.
##
## Flat reduction is the whole character of the stat. It is worth most against
## many small hits and least against few big ones, which is why one number
## reproduces the P4.4 frame-pressure story (heavy is ++ against gnat stings,
## unimpressed by a turret's 10s) without a second knob to tune.
@export var armor: float = 0.0
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


func configure_defenses(config: EnemyConfig) -> void:
	armor = config.armor
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


## `shielded` false sends the hit straight past the screen to the plating and the
## hull. Every existing caller leaves it true and is unchanged.
##
## IT EXISTS FOR THE PHALANX (A7), whose screen covers an ARC rather than the
## whole body, and it is one optional argument rather than a second shield
## implementation on purpose. A directional shield that owned its own pool would
## be two physics for one word — the thing `Bomb.blast` was made a shared static
## to avoid — and it would have to re-derive the regen rules, including the one
## corrected earlier today. The DIRECTION is the caller's business, because only
## the caller knows its own geometry; what a shield DOES stays here.
func take(amount: float, shielded: bool = true) -> void:
	if not alive:
		return
	struck.emit(amount)
	# ANY hit that arrives holds the shield down — on the screen or on the exposed
	# hull, it makes no difference. This reset used to live inside the `shield > 0`
	# branch below, and moving it out fixes two defects that were really one.
	#
	# FIRST, it is what the mechanic is FOR. The user stated the intent exactly:
	# *"i need to take its shield down with a missle, then maintain some damage on
	# its hull to degrade it, and if i cannot connect damage to it for X seconds,
	# its shield should rearm"*. Under the old rule, staying on the target did
	# nothing at all — the screen came back `shield_regen_delay` after the last hit
	# that landed while it was still UP, however hard you were hitting the hull.
	#
	# SECOND, and this is the one that made the type unkillable: the regenerated
	# shield reappears as a SLIVER, and the gate is `shield > 0`, not "shield worth
	# anything". Measured before the fix: 4 s after the break, 0.05 points of shield
	# came back, and from that tick on every chip round was absorbed whole and reset
	# the delay — so the sliver could never grow, the hull could never be touched,
	# and the aegis simply stopped being killable by a blaster. Frozen for the rest
	# of the scene. The comment below already names this failure for the
	# OVER-threshold path; it was still live on the under-threshold one.
	if shield_max > 0.0:
		_regen_wait = shield_regen_delay
	if shield > 0.0 and shielded:
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
	# The hull's own layer. A hit the plating eats entirely is silent past
	# `struck` (already emitted above, so the delivery benches still count it as
	# an arrival) — it did nothing, so it announces nothing, and an armor value
	# at or above a weapon's damage means that weapon NEVER kills this target.
	# Same shape as the shield's threshold gate, and Lethality reports it the
	# same way.
	amount = maxf(amount - armor, 0.0)
	if amount <= 0.0:
		return
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
