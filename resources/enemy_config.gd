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

@export_group("Behavior")
## Standoff distance the type holds while attacking (orbit radius for flyers).
@export var preferred_range: float = 18.0
## Seconds before a destroyed instance returns. 0 = never (wave-spawned types).
@export var respawn_delay: float = 0.0

@export_group("Strategic")
@export var points: float = 150.0
## Garrison strength one body of this type represents in the war-sim manifest
## (P4.7). Recorded now, consumed when the manifest projection lands.
@export var strength_cost: float = 1.0


func save_path() -> String:
	return "user://enemy_%s.tres" % type_id


func defaults_path() -> String:
	return "res://resources/default_enemy_%s.tres" % type_id
