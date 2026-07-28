class_name Screamer
extends CharacterBody3D

## Screamer — EW escort (GAMEPLAY-DESIGN P4.2, roster type SIX).
##
## The first roster member whose entire effect is a MULTIPLIER on the player's
## delivery, and the reason S14 had to be settled before it could be built. Run
## it through the three balance layers and it disappears from two of them:
##
##   Layer 1 (lethality)  nothing. `damage` 0 — it carries no weapon.
##   Layer 3a (incoming)  nothing. `mode: none` — it prices no frame's durability.
##   Layer 2 (delivery)   EVERYTHING. The jam is a degradation of aim_quality and
##                        an outright refusal of the missile lock.
##
## So its harness rows look strange on purpose (0 damage taken, "cannot price
## durability"), and the number that actually describes it lives one layer over.
##
## WHAT IT DOES: emits a jam field (jamming.gd) that fades with distance. Inside
## `jam_full_range` the gun director is silent, the missile lock refuses, and the
## flak fuse degrades to contact-only; out to `jam_range` each of those is
## partial, and the video feed breaks up in proportion the whole way. The audio
## cue and the feed breakup ARE the jam level, not a separate telegraph — what you
## hear is exactly what your gear is suffering.
##
## WHAT IT DOESN'T DO: shoot. It is "tissue once reached" (P4.2) and every part of
## this file is arranged around that sentence — it holds a wide standoff, backs
## off when pressed, and dies to two chip-gun bolts. The fight it creates is not
## a duel, it is a decision: your gear gets worse the closer you get to the thing
## you have to close on. That tension is why the jam is a GRADIENT and not a
## bubble (S.q8, the user's call).
##
## Counter-web position (P4.3 row): chip gun `+` (the iron trigger still works),
## burst `++`, lob `0`, missile `--` (there is no lock to be had), flak `0` (its
## fuse is the thing being jammed), terrain `+` (cover lets you close unseen).
## Frame pressure (P3.4): Dart `+`, Kestrel `0`, Atlas `-`, Shade `++`.
##
## THE JAM IGNORES LINE OF SIGHT; the screamer's AWARENESS does not. That split is
## what makes P4.3's terrain `+` real: hiding behind a building does not switch
## the jam off (radio interference through a wall is not a thing you dodge), but
## it does stop the screamer repositioning away from you, so cover is how you
## close. A jam that cover defeated would make the whole type a non-event.

signal destroyed(points: float)

## Combat-AI feel constants (not flight/input physics), in the same spirit as
## EnemyDrone's: shape constants describing the manoeuvre, while every number a
## designer would TUNE lives in EnemyConfig.
##
## Sideways slide around the standoff circle — the same idiom the raider flies,
## because a station-keeping body that only ever moved radially would read as a
## balloon on a string.
const ORBIT_TANGENT_BIAS: float = 10.0
## How far above the player it prefers to sit. It wants to SEE the fight from the
## edge, and height is the cheapest way to keep line of sight over a city block.
const STANDOFF_HEIGHT: float = 6.0
## Floor.
const MIN_ALTITUDE: float = 3.0
## Radius of the wander it flies with nobody to escort. Leashed to its spawn for
## the reason the falx's patrol circuit exists (v1.81): a body with no target and
## no leash flies out of the level, and the harness cannot tell that apart from a
## tough enemy. This one wanders rather than circles because it is raider-slow —
## the falx needed a circuit because at 25 m/s a random walk IS a departure.
const WANDER_RADIUS: float = 22.0
## Seconds per full sweep of the dish. Cosmetic, and the readability the type
## needs: a thing that is doing something to you should visibly be doing it.
const DISH_SPIN_S: float = 2.6

@export var enemy_config: EnemyConfig
## Fixed RNG seed for the harness (P4.8 determinism): -1 randomizes. Must be set
## before the node enters the tree.
@export var ai_seed: int = -1

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _visual: Node3D = $Visual
@onready var _dish: Node3D = $Visual/Dish
@onready var _emitter: MeshInstance3D = $Visual/Dish/Emitter
@onready var _health: Health = $Health
@onready var _tone: AudioStreamPlayer3D = $JamTone

var _player: FlightController
var _home: Vector3
var _wander_target: Vector3
var _orbit_sign: float = 1.0
var _rng := RandomNumberGenerator.new()
var _emitter_material: StandardMaterial3D


func _ready() -> void:
	_home = global_position
	if ai_seed >= 0:
		_rng.seed = ai_seed
	else:
		_rng.randomize()
	_orbit_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_health.max_health = enemy_config.hull
	_health.configure_defenses(enemy_config)
	_health.revive()
	_health.died.connect(_on_died)
	_pick_wander_target()
	# Per-instance material so one screamer lighting up does not light up a pair.
	if _emitter.mesh != null and _emitter.mesh.material is StandardMaterial3D:
		_emitter_material = (_emitter.mesh.material as StandardMaterial3D).duplicate() \
				as StandardMaterial3D
		_emitter.material_override = _emitter_material
	_start_tone()


func take_hit(damage: float) -> void:
	_health.take(damage)


## THE JAM FIELD, and the only thing this type does to anybody. Read through
## `Jamming.level_at`, never directly, so a second EW type composes with this one
## instead of racing it.
##
## Note that it does NOT check `_can_engage`: the field is on whenever the body
## is, armed player or not. A jammer that only jams once it has noticed you is a
## jammer whose effect is gated on its own AI, and the player would experience
## that as the interference flickering for reasons nothing on screen explains.
func jam_level_at(point: Vector3) -> float:
	return Jamming.falloff(global_position.distance_to(point),
			enemy_config.jam_full_range, enemy_config.jam_range)


func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as FlightController
	var desired_point: Vector3
	if _can_engage():
		desired_point = _standoff_point()
	else:
		if global_position.distance_to(_wander_target) < 3.0:
			_pick_wander_target()
		desired_point = _wander_target
	desired_point.y = maxf(desired_point.y, MIN_ALTITUDE)
	_steer_toward(desired_point, delta)
	move_and_slide()
	_face_velocity(delta)
	_update_telegraph(delta)


## It repositions only against a player it can SEE (see the header's LOS note).
## Losing sight of you does not weaken the jam; it just stops the screamer from
## backing away, which is how a masked approach beats it.
func _can_engage() -> bool:
	if _player == null:
		return false
	# visible=false is the player's death state (main.gd).
	if not _player.armed or not _player.visible:
		return false
	if global_position.distance_to(_player.global_position) \
			> enemy_config.sight_range:
		return false
	return _has_line_of_sight()


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position,
			_player.global_position)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == _player


## The standoff slot: `preferred_range` out from the player, high, sliding
## sideways. The raider's orbit with a much larger radius — and the radius is the
## design, not a tuning choice. It is sized so that the screamer's OWN station
## sits in the fading part of its jam field: engaging it at all costs you a
## fraction of your FCS, and taking it off the board costs you all of it.
##
## It is also why the type cannot simply run: the slot is a POSITION, and
## `_steer_toward` eases into it, so a player pressing in pushes the screamer back
## at its own walking pace rather than triggering a sprint. It is answered by
## being closed on, exactly as P4.2 says.
func _standoff_point() -> Vector3:
	var from_player: Vector3 = global_position - _player.global_position
	var flat := Vector3(from_player.x, 0.0, from_player.z)
	if flat.length_squared() < 0.25:
		flat = Vector3.FORWARD
	var radial: Vector3 = flat.normalized()
	var tangent: Vector3 = radial.cross(Vector3.UP) * _orbit_sign
	return _player.global_position + radial * enemy_config.preferred_range \
			+ tangent * ORBIT_TANGENT_BIAS + Vector3.UP * STANDOFF_HEIGHT


func _steer_toward(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	# Arrive: full speed far out, ease in over the last few meters.
	var desired_speed: float = minf(offset.length() * 1.5, enemy_config.speed)
	var desired_velocity: Vector3 = offset.normalized() * desired_speed
	velocity = velocity.move_toward(desired_velocity, enemy_config.accel * delta)


func _face_velocity(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var blend: float = 1.0 - exp(-5.0 * delta)
	if flat.length() > 1.5:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), blend)
	var local_velocity: Vector3 = global_basis.inverse() * velocity
	_visual.rotation.z = lerpf(_visual.rotation.z,
			clampf(-local_velocity.x * 0.02, -0.35, 0.35), blend)


func _pick_wander_target() -> void:
	_wander_target = _home + Vector3(
			_rng.randf_range(-WANDER_RADIUS, WANDER_RADIUS),
			_rng.randf_range(2.0, 12.0),
			_rng.randf_range(-WANDER_RADIUS, WANDER_RADIUS))


## THE CUE IS THE JAM LEVEL. Both the dish emitter's glow and the tone's loudness
## are driven by the same number the player's gear is being degraded by, sampled
## at the PLAYER — so "it gets louder as you close on it" (the user's steering) is
## not an approximation of the effect, it is the effect, read aloud.
##
## Deliberately NOT left to 3D attenuation, which would have been free: distance
## falloff and the jam falloff are two different curves, and a cue that disagrees
## with the mechanic by even a little teaches the player the wrong edge.
func _update_telegraph(delta: float) -> void:
	var level: float = 0.0
	if _player != null and is_instance_valid(_player):
		level = jam_level_at(_player.global_position)
	_dish.rotate_y(TAU / DISH_SPIN_S * delta)
	if _emitter_material != null:
		_emitter_material.emission_energy_multiplier = lerpf(
				_emitter_material.emission_energy_multiplier,
				0.5 + 5.0 * level, 1.0 - exp(-5.0 * delta))
	if _tone == null or _tone.stream == null:
		return
	# Silent outside the field entirely, rather than fading to inaudible: a bus
	# playing -60 dB into every scene is a leak with a volume slider on it.
	if level <= 0.001:
		_tone.volume_db = -60.0
		return
	_tone.volume_db = lerpf(-34.0, -6.0, level)
	_tone.pitch_scale = 0.8 + 0.5 * level


func _start_tone() -> void:
	# Headless: active playbacks leak at quit() under the Dummy audio driver, and
	# no bench hears them (motor_audio.gd's rule, same reason).
	if _tone == null or DisplayServer.get_name() == "headless":
		return
	_tone.stream = SoundBank.make_jam_loop()
	_tone.volume_db = -60.0
	_tone.play()


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position, 1.4)
	destroyed.emit(enemy_config.points)
	queue_free()
