class_name CombatConfig
extends TunableConfig

## Combat/balance tunables (roadmap M1/M2), live-editable in the overlay
## exactly like FlightConfig. Shared instance: weapon, targets and main all
## export the same default_combat_config.tres.
##
## PLAYER SIDE ONLY (GAMEPLAY-DESIGN P4.8): the enemy_* and turret_* groups
## moved out to per-type EnemyConfig .tres files, so the bestiary is tuned one
## row at a time and CombatConfig means "the player's weapons and the run".
## Saved user configs carrying the old fields load fine — copy_from only reads
## properties this class still declares.

@export_group("Weapon")
@export var fire_rate: float = 10.0
@export var muzzle_speed: float = 90.0
@export var projectile_damage: float = 25.0
@export var projectile_lifetime: float = 3.0
## Fraction of normal gravity applied to projectiles — a little drop makes
## leading targets a skill.
@export var projectile_gravity_scale: float = 0.3
## Fraction of the shooter's velocity added to the projectile.
@export var inherit_velocity: float = 1.0
## Fire-control assist: the blaster auto-fires when a hostile's predicted
## ballistic miss distance falls under this (meters). 0 = off (manual trigger
## only). Prototype of the FCS equipment family (GAMEPLAY-DESIGN.md, P3) —
## a dev knob today, an acquirable asset later.
@export var fire_assist_miss_m: float = 0.0
## Hostiles beyond this range are ignored by the fire assist.
@export var fire_assist_range: float = 55.0

@export_subgroup("Heat")
## THE BLASTER'S CHARGE METER (Iteration 10 R.q1, the user's call over my
## "leave it infinite"). The blaster is the only weapon that is never resupplied
## and never runs out — what it has instead is a DUTY CYCLE. That distinction is
## the whole design: heat never strands you the way an empty magazine would, it
## paces you, so it belongs to trigger discipline rather than to the economy
## the resupply gates serve.
##
## Sustained fire never cools, because the gap between bolts (0.1 s at
## fire_rate 10) is under `heat_vent_delay`. That is deliberate and it is what
## makes the arithmetic honest enough for Layer 1 to model: a held trigger is
## exactly `heat_capacity / heat_per_shot` bolts, then a vent.
@export var heat_per_shot: float = 1.0
## Heat the sink holds before it locks out. In bolts, since heat_per_shot is 1.
@export var heat_capacity: float = 30.0
## Heat shed per second once venting starts.
@export var heat_cool_rate: float = 12.0
## Quiet seconds before venting begins — long enough that firing at any usable
## cadence never cools.
@export var heat_vent_delay: float = 0.35
## Once overheated the gun stays locked until heat falls to this FRACTION of
## capacity. A lockout that cleared the instant heat dipped below the ceiling
## would let a mashed trigger stutter along at the ceiling forever, which is
## the failure mode that makes overheat feel broken rather than tactical.
@export_range(0.0, 0.9, 0.01) var heat_reset_fraction: float = 0.3

@export_group("Magazines")
## THE TWO RESOURCES THE GATES SERVE (Iteration 10 R.q2/R.q3). Unlike heat,
## these do not come back on their own: they are a SORTIE resource, refilled by
## flying through a resupply gate, by a drop, or by clearing a wave.
##
## The blaster deliberately has no entry here. It is the floor — a pilot out of
## everything must still be able to fight, or a dry run is an unwinnable
## stalemate with the exit gate shut. What the blaster has instead is heat.
##
## 0 disables the magazine entirely (infinite), which is what every bench that
## predates this feature expects and what `bench_unlimited` states explicitly.
@export var flak_magazine: float = 24.0
@export var missile_rack: float = 6.0
## R.q3 originally answered "free re-arm on wave clear", and it was RETRACTED
## after three rounds of play (v1.93). I had flagged that R.q2 and R.q3 together
## moved the unit of scarcity from the sortie to the wave; the user flew it and
## agreed the gates went slack — "lets drop the wave clear refills, and only
## keep the gates/kills to provide ammo".
##
## So ammunition is a genuine SORTIE resource again, and the only ways to put
## rounds back are the two that cost you something: fly a gate, or go and take
## a drop off something you killed. Nothing here re-arms for free.
##
## Running dry is still never fatal, and that is the whole reason the blaster
## was left as the floor with heat instead of a magazine.

@export_group("Flak pod")
## The slice's third weapon (GAMEPLAY-DESIGN P3.1 / P4.10): a proximity-fused
## burst shell that detonates into a fragment cloud. Its whole reason to exist
## is the P4.3 flak column — `++` on gnats, `--` on shields — and the shape of
## that answer lives in these numbers rather than in any special-case code:
## small per-body damage (under the aegis's 40 break threshold, so it splashes
## off exactly like the chip gun) delivered to EVERY body in a radius.
@export var flak_fire_rate: float = 2.5
@export var flak_muzzle_speed: float = 70.0
## Heavier, slower shell than a bolt: more drop, which is what keeps flak a
## short-range weapon without a hard range cutoff.
@export var flak_shell_gravity_scale: float = 0.4
## Flight time before the shell airbursts on its own — the effective range.
@export var flak_shell_lifetime: float = 1.4
## Travel before the fuse arms, meters. Without it the shell would detonate on
## a hostile the muzzle is already touching.
@export var flak_arm_distance: float = 5.0
## Proximity fuse: burst when a hostile comes within this range of the shell.
## Deliberately SMALLER than the burst radius so the shell flies INTO a cloud
## before it goes off — fragments from the middle of the pack, not its face.
@export var flak_fuse_radius: float = 3.5
## Everything hostile inside this radius of the burst takes flak_damage.
@export var flak_burst_radius: float = 6.0
## Damage per body caught in the burst. Flat, not falloff — see flak_shell.gd.
@export var flak_damage: float = 10.0

@export_group("Player")
# player_max_health left with FrameConfig.hull (P3.9): the hull belongs to the
# airframe you are flying, not to "the player" — a distinction that could not be
# made while there was one frame. The frame now applies it in
# FlightController._ready, so the benches see it too.
## CRASH DAMAGE IS PEAK DECELERATION (GAMEPLAY-DESIGN Iteration 17 / E6, as
## corrected by the E steering). The user's model, and it replaced kinetic
## energy before anything was built: *"damage like trauma is caused by the abrupt
## acceleration, where all parts feel a devestating force that shakes the
## integrity of the entire frame."*
##
## `crash_crush_m` is the effective stopping distance of an impact — how far the
## airframe and the thing it hit give way TOGETHER before the aircraft is
## stopped. It is the only place a crash's abruptness is stated, and everything
## else here follows from it: peak deceleration is `v^2 / (2 * s * g)`.
##
## IT IS ONE NUMBER FOR EVERY FRAME, DELIBERATELY, and that is the whole
## anti-invulnerability clause. Letting it scale with airframe size would be
## defensible on its own terms (a 3 m structure has more depth to crush than a
## 0.28 m one) and would hand the Roc a 10.7x discount on every wall it ever
## meets — which is precisely the *"no amount of redundancy makes a Roc a
## battering ram"* the design forbids. Mass appears nowhere in the law at all,
## which is E6's other half: *"a Roc and a Kestrel stopping from the same speed
## over the same distance pull the same g."*
@export var crash_crush_m: float = 0.1
## Impacts under this peak deceleration (in g) are free; above it they hurt.
##
## 73.5 g is exactly the old 12 m/s free threshold expressed in the new law
## (`12^2 / (2 * 0.1 * 9.8)`), because the Kestrel's crash behaviour is signed
## off and the free band must not move. A set-down measures 4 g on a Kestrel and
## 40 g on a Roc, so every landing the roster can make is still free.
@export var crash_damage_g: float = 73.5
## Damage per g beyond the free threshold.
##
## Calibrated on the one number a pilot actually feels: the speed at which a
## crash kills a full-health Kestrel. That was 28.67 m/s under the old linear
## law and it is 28.67 m/s under this one. Below that speed the new law is
## slightly gentler and above it far harsher, which is E6's *"can even die if
## faster"* arriving as arithmetic rather than as a special case.
@export var crash_damage_per_g: float = 0.2892
@export var respawn_delay: float = 2.5

@export_group("Targets")
@export var target_points: float = 100.0
@export var target_respawn_delay: float = 8.0

@export_group("Missiles")
@export var missile_lock_range: float = 60.0
## Half-angle of the lock cone around the camera axis.
@export var missile_lock_cone_deg: float = 12.0
## Seconds the target must stay in the cone to lock.
@export var missile_lock_time: float = 0.9
@export var missile_speed: float = 50.0
@export var missile_turn_rate_deg: float = 180.0
@export var missile_damage: float = 60.0
@export var missile_cooldown: float = 3.0
## Detonation distance to the locked target.
@export var missile_prox_radius: float = 2.5
@export var missile_lifetime: float = 7.0
## Missile director (FCS): with missile_auto_switch on, a full lock held
## stable for this long auto-launches. The HUD winds an arc around the lock
## diamond while it counts.
@export var missile_auto_hold_s: float = 0.4

@export_group("Waves")
@export var wave_base_enemies: float = 2.0
## Extra enemies added per wave.
@export var wave_growth: float = 1.0
@export var wave_intermission: float = 8.0
## Waves per sortie; clearing them lights the exit gate (roadmap M4).
@export var sortie_waves: float = 3.0
## Extra enemies per wave for each sortie beyond the first.
@export var sortie_enemy_bonus: float = 1.0
## Kills within this window raise the score multiplier.
@export var combo_window: float = 4.0
@export var combo_max: float = 5.0


const SAVE_PATH: String = "user://combat_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_combat_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH


## The project's own gravity, so there is exactly ONE gravity in the game and no
## second constant to drift from it. Read once, lazily, on first class access —
## the same value `FlightController` falls under, rather than the 9.80665 the
## unit "g" formally means, because a crash should be measured in the gravity of
## the world it happened in.
static var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## Peak deceleration, in g, of an impact arriving at `impact_speed` (m/s).
##
## `v^2 / (2 * s)` is the standard crash-pulse figure and it is the quantity the
## PHYSICS TICK CANNOT GIVE US, which is why the stopping distance has to be
## authored. Godot's solver removes the whole velocity in one step whatever the
## step is, so the raw per-tick deceleration is `v / dt` — a number that triples
## if someone raises the tick rate and says nothing about the airframe. Measured,
## not assumed: a Kestrel, a Condor and a Roc all report their full impact speed
## as a single-tick delta-v, at every speed from 3 to 131 m/s.
##
## Two properties fall straight out of the formula, and they are the two E6 asks
## for. Mass is absent, so a heavy frame is not a safer one. And it is QUADRATIC
## in speed, so doubling the speed quadruples the g — *"faster is worse"* without
## a threshold having to fake the curve.
func impact_g(impact_speed: float) -> float:
	if crash_crush_m <= 0.0:
		return 0.0
	return impact_speed * impact_speed / (2.0 * crash_crush_m * _gravity)


## Hull damage from an impact arriving at `impact_speed` (m/s). Zero under the
## free threshold, which is what keeps landings free.
func crash_damage(impact_speed: float) -> float:
	return maxf(impact_g(impact_speed) - crash_damage_g, 0.0) * crash_damage_per_g


## The speed at which a crash exactly kills `hull` points of airframe — the one
## crash number a pilot learns by feel, and therefore the one the law is
## calibrated on. Inverse of `crash_damage`; INF when the law cannot reach it.
func crash_lethal_speed(hull: float) -> float:
	if crash_damage_per_g <= 0.0 or crash_crush_m <= 0.0:
		return INF
	return sqrt((hull / crash_damage_per_g + crash_damage_g)
			* 2.0 * crash_crush_m * _gravity)
