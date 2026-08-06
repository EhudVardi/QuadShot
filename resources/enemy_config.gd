class_name EnemyConfig
extends TunableConfig

## Per-type enemy stat block (GAMEPLAY-DESIGN P4.8): one .tres per bestiary
## type, replacing CombatConfig's enemy_*/turret_* groups so CombatConfig can
## go back to meaning "the player's side". Field blocks mirror the P4.1 design
## axes — durability, mobility, sensor, weapon, behavior, strategic — so every
## roster type is described in the same vocabulary and the counter-matrix
## (P4.3) has one place per row to be tuned from.
##
## Unlike the other configs this class has MANY instances, so the save and
## defaults paths are derived from `type_id` rather than being class
## constants: raider -> user://enemy_raider.tres, and the overlay's BESTIARY
## section gives each type its own preset bar.
##
## Not every field applies to every type (a turret has no speed, a raider has
## no shield). Irrelevant fields stay at their inert defaults — a union schema
## keeps the roster comparable at a glance, which is the point of the axes.

@export_group("Identity")
## Slug used for the save/defaults paths and the overlay label.
@export var type_id: StringName = &"enemy"

@export_group("Durability")
@export var hull: float = 40.0
## Flat damage subtracted from every hit (the P4.1 "armored" model). 0 = none.
@export var armor: float = 0.0
## Regenerating shield pool that GATES the hull (the P4.1 "shielded" model,
## the Aegis's defining trait). 0 = unshielded; the fields below are inert.
@export var shield_max: float = 0.0
## Hits landing BELOW this are absorbed by the shield and regenerate away —
## this single number is why chip fire cannot win against a shielded type and
## burst weapons can (P4.3: chip-gun -- / burst ++).
@export var shield_break_threshold: float = 0.0
## Shield points restored per second, once the regen delay has elapsed.
@export var shield_regen: float = 0.0
## Quiet seconds after taking a hit before the shield starts regenerating.
@export var shield_regen_delay: float = 0.0

@export_group("Mobility")
@export var speed: float = 14.0
@export var accel: float = 18.0
## Rotation rate — a turret's head slew, a flyer's turn authority (deg/s).
@export var turn_speed_deg: float = 120.0

@export_group("Sensor")
## Engagement range: beyond it the player is not a target. Also sizes the
## type's projectile lifetimes.
@export var sight_range: float = 60.0

@export_group("Weapon")
@export var damage: float = 8.0
@export var fire_rate: float = 1.5
@export var muzzle_speed: float = 45.0
## Random cone added to this type's aim — the dodgeability knob (P4.q2: what
## veterancy tightens, and the one thing it may never tighten past the stated
## ceiling).
@export var aim_jitter_deg: float = 3.0

@export_group("Swarm")
## Bodies per pack. Inert for non-swarm types — the Gnat is the one roster
## member whose UNIT is the cloud, not the body (P4.q5), so its numbers
## describe a flock rather than a fighter.
@export var pack_size: float = 0.0
## Spacing each body tries to keep from its neighbours, meters.
@export var swarm_spacing: float = 3.0
## Push away from neighbours inside the spacing radius.
@export var swarm_separation_gain: float = 1.6
## Pull toward the pack's center of mass — what makes it read as one cloud.
@export var swarm_cohesion_gain: float = 0.5
## Pull toward the player: the pack's actual attack.
@export var swarm_pursuit_gain: float = 1.0
## Random wander added per body — the boil. 0 = a sterile lattice.
@export var swarm_jitter: float = 0.35
## Contact range at which a body stings and detonates, meters.
@export var swarm_sting_radius: float = 1.6

@export_group("Electronic warfare")
## Outer edge of this type's jam field, meters. 0 = not a jammer, which is every
## roster type but the Screamer — the union-schema rule above, applied to EW.
##
## The jam FADES between here and `jam_full_range` rather than switching at an
## edge (S.q8, the user's call over my binary lean): a sensor warning is where a
## gradient belongs, and it makes the approach itself cost something, since
## closing to kill the screamer is closing into a stronger jam.
@export var jam_range: float = 0.0
## Inside this the jam is TOTAL: gun director silent, missile lock refused, flak
## fuse degraded to contact-only. Sized against the type's own standoff so that
## engaging it at all costs you part of your FCS and killing it costs you all of
## it. See `Jamming.falloff`.
@export var jam_full_range: float = 0.0
## How completely this type hides itself, 0..1. 0 = no cloak, which is every
## roster type but the Screamer.
##
## THE DIFFICULTY AXIS (the user's suggestion, v1.90): a cloak is not on or
## off, it is a dial, and this is the dial. It pulls two things together so
## they can never disagree — the floor under the hull's shimmer, and how far
## the dish emitter is allowed to dim. At 0 the dish burns at its old
## brightness and the hull is faintly visible even outside the field; at 1 the
## only thing a distant screamer gives you is the audio and the feed breakup,
## and you hunt it by flying toward the interference.
@export_range(0.0, 1.0, 0.01) var cloak_strength: float = 0.0

@export_group("Behavior")
## Standoff distance the type holds while attacking (orbit radius for flyers).
@export var preferred_range: float = 18.0
## Seconds before a destroyed instance returns. 0 = never (wave-spawned types).
@export var respawn_delay: float = 0.0

@export_group("Payload")
## BOMBS CARRIED (GAMEPLAY-DESIGN Iteration 14, A2 / A.q2). A bomber flies one
## pass per bomb and LEAVES when the last one is gone.
##
## **0 means "not a bomber"**, which is how every other type in the roster keeps
## its behaviour without knowing this field exists, and how the aegis's original
## ticking-bomb form is still reachable from a config.
##
## A.q2 decided this is a MAGAZINE, in the same vocabulary Iteration 10 built for
## the player's flak and missiles: `rounds`, spend, refuse when dry. One
## mechanism covers both, so "a bomber out of bombs" is legible in exactly the
## way "a pilot out of flak" already is.
@export var payload: int = 0
## Damage one bomb does to what it lands on.
##
## **ZERO BY DEFAULT, and that is load-bearing rather than tidy.** It shipped at
## 45.0, which meant every weaponless type in the roster silently carried a
## 45-damage blast it never used — invisible until `Lethality.incoming` grew a
## branch keyed on "does this type have a blast" (A5) and promptly priced the
## SCREAMER as a contact threat. A damage field that defaults to a number is a
## claim every config makes by saying nothing.
@export var bomb_damage: float = 0.0
## Blast radius of one bomb.
@export var bomb_radius: float = 9.0
## PROXIMITY FUSE, metres. A committed suicider detonates when the player is
## inside this and has stopped getting closer — the classic closest-approach
## fuse, and 0 means contact-only.
##
## IT IS THE COUNTERPLAY, EXPRESSED AS A DISTANCE. Without it the answer to a
## Lance is binary and far too cheap: the user flew it and found that *"if i fly
## towards it and side step slightly, it just passes me and explode in the
## original location"*. A committed run should still catch a near miss, or
## "commit to a point in space" quietly means "commit to missing".
##
## Sized ABOVE `bomb_radius` on purpose. Inside the blast you take real damage;
## between the blast and the fuse it goes off beside you and the falloff makes it
## a graze. So the dodge has a gradient instead of an edge, which is the same
## reasoning `flak_fuse_radius` and `flak_burst_radius` are two numbers.
@export var blast_fuse_radius: float = 0.0
## How fast a released bomb falls, as a multiple of project gravity.
##
## THIS IS THE TELEGRAPH LENGTH, which is why it is a knob rather than a
## constant. The fall is the only part of a bomb run the pilot can still react
## to, and how long it lasts decides whether "bombs away" is a warning or a
## result — 1.0 is about 2.3 s from the 26 m run height. It also sets how far
## ahead of the aim point the bomber has to release, because the bomber computes
## its own lead from these same ballistics (`Bomb.fall_time`).
@export var bomb_fall_gravity_scale: float = 1.0

@export_group("Strategic")
@export var points: float = 150.0
## Garrison strength one body of this type represents in the war-sim manifest
## (P4.7). Recorded now, consumed when the manifest projection lands.
@export var strength_cost: float = 1.0


func identity_fields() -> PackedStringArray:
	return PackedStringArray(["type_id"])


func save_path() -> String:
	return "user://enemy_%s.tres" % type_id


func defaults_path() -> String:
	return "res://resources/default_enemy_%s.tres" % type_id
