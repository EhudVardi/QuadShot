class_name Bomb
extends Node3D

## A bomb that FALLS (GAMEPLAY-DESIGN v2.20 — the ordnance half of A2).
##
## v2.19 built a bomber that carries a payload, spends it and goes home. It did
## not build a bomb. `Aegis._drop_bomb` called `Effects.explosion` at the route
## waypoint, and that waypoint carries `BOMB_RUN_HEIGHT` (26 m) — so the blast
## went off in mid-air at the bomber's own position and nothing ever reached the
## ground. Flown 2026-08-05: *"i think it dropped a bomb but the bomb immediately
## exploded. i didnt see anything dropped and explode on the ground."* The splash
## was applied correctly; it is the READING that was missing, and P4.4's
## readability rule says a telegraph the player cannot see is not a telegraph.
##
## So this is a real body. It is released with the bomber's own momentum,
## integrated under gravity with a segment raycast per step — the house pattern
## `projectile.gd` and `flak_shell.gd` already use, and it exists so that a fast
## body can never tunnel through thin geometry — and it explodes on whatever it
## meets first, which is normally the ground.
##
## IT OUTLIVES ITS BOMBER, and that is a design decision rather than an accident
## of ownership. A bomber killed before release drops nothing; a bomber killed
## after release still lands the bomb it let go of. So interception has a
## DEADLINE and the deadline is the release, not the kill — which is the same
## shape as the flak shell already in flight when its pod dies.
##
## The blast lives here rather than on the bomber for the same reason: once it is
## off the rack it is not the bomber's any more. That is the whole difference
## between a bomber and a kamikaze, expressed as which node owns the explosion.

## Where it went off. The event a check can assert against a ground plane, and
## the one the old code could never have emitted because nothing ever landed.
signal exploded(at: Vector3)

## Fallback fuse, in seconds. "It reaches the ground" is a promise the world can
## break — a bomb released over the edge of the greybox floor would otherwise
## fall forever as a body nothing resolves. Generous enough that it never
## pre-empts a real impact: a 26 m drop takes about 2.3 s.
const LIFETIME_S: float = 20.0
## Released from slightly below the hull so the first tick's raycast starts in
## clear air rather than inside the bomber's own collision box.
const RELEASE_DROP: float = 1.2
## Explosion visual scale, in the units `Effects.explosion` takes. Read off the
## blast radius so a bigger bomb looks bigger without a second number to keep in
## step with the first.
const BLAST_VISUAL_SCALE: float = 0.34

var _config: EnemyConfig
var _team: StringName = &"enemy"
var _velocity: Vector3
var _exclude: Array[RID] = []
var _life: float = LIFETIME_S
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## Release one bomb into the world. A static factory for the same reason
## `Salvage.maybe_drop` is one: every caller comes through here, so the release
## offset and the momentum inheritance cannot drift between call sites.
static func release(parent: Node, scene: PackedScene, at: Vector3,
		velocity: Vector3, config: EnemyConfig, team: StringName,
		exclude: Array[RID]) -> Bomb:
	if parent == null or scene == null or config == null:
		return null
	var bomb := scene.instantiate() as Bomb
	if bomb == null:
		return null
	bomb._config = config
	bomb._team = team
	# IT INHERITS THE BOMBER'S VELOCITY, which is what makes it read as DROPPED
	# rather than as fired: it leaves the rack travelling exactly as fast as the
	# aircraft and then falls away behind and below it.
	bomb._velocity = velocity
	bomb._exclude = exclude
	parent.add_child(bomb)
	bomb.global_position = release_point(at)
	return bomb


## Where a bomb let go by an aircraft at `at` actually starts. Shared with the
## bomber's aim so the two cannot disagree about a metre.
static func release_point(at: Vector3) -> Vector3:
	return at + Vector3.DOWN * RELEASE_DROP


## WHERE A BOMB RELEASED FROM `from` AT `velocity` WILL LAND, on the plane
## y = `ground_y`. Public and static because the BOMBER needs it to know when to
## let go, and ballistics restated at the release site would be a second copy of
## these two lines that drifts from the one the bomb actually flies.
##
## IT TAKES THE FULL VELOCITY RATHER THAN A SPEED, and that is not tidiness. The
## first version of the release solved `t = sqrt(2h/g)` — the fall time of a bomb
## let go from level flight — and it was right on the first pass and 23 m wide on
## the next two, because a bomber coming back off a re-attack leg is DESCENDING
## and its bomb starts the fall already moving downward. Any aim that ignores
## `velocity.y` is exactly one bombing pattern wide.
static func predicted_impact(from: Vector3, velocity: Vector3, ground_y: float,
		gravity_scale: float = 1.0) -> Vector3:
	var gravity: float = maxf(
			float(ProjectSettings.get_setting("physics/3d/default_gravity"))
			* gravity_scale, 0.001)
	var drop: float = maxf(from.y - ground_y, 0.0)
	# The positive root of  drop + v.y*t - 0.5*g*t^2 = 0.
	var fall: float = (velocity.y
			+ sqrt(velocity.y * velocity.y + 2.0 * gravity * drop)) / gravity
	return Vector3(from.x + velocity.x * fall, ground_y, from.z + velocity.z * fall)


func _ready() -> void:
	add_to_group(&"bombs")
	if _config != null:
		_gravity *= maxf(_config.bomb_fall_gravity_scale, 0.01)
	_orient()


func _physics_process(delta: float) -> void:
	_velocity += Vector3.DOWN * (_gravity * delta)
	var step: Vector3 = _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + step)
	query.exclude = _exclude
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		# Contact detonation on the FIRST thing it meets. Normally the ground;
		# a roof, a building or a pilot who flew underneath it all count, which
		# is the honest reading of a falling bomb and needs no special case.
		global_position = hit["position"]
		_detonate()
		return
	global_position += step
	_orient()
	_life -= delta
	if _life <= 0.0:
		_detonate()


## THE BLAST, shared. A distance test over the two groups rather than a physics
## query — the same reasoning `gnat_swarm`'s sting and the aegis's old splash
## used, and a bomb that only hurt bodies with colliders on the right layer would
## be a bomb that mostly did nothing.
##
## Static and public because the LANCE detonates too (A5): a suicider is ordnance
## that flies itself, so "what one blast does" must have exactly one definition
## or the two types would drift into different physics for the same word.
static func blast(tree: SceneTree, at: Vector3, config: EnemyConfig,
		team: StringName) -> void:
	if tree == null or config == null:
		return
	var radius: float = maxf(config.bomb_radius, 0.001)
	for node: Node in tree.get_nodes_in_group(&"player") \
			+ tree.get_nodes_in_group(&"objectives"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.get(&"team") == team:
			continue
		var distance: float = (node as Node3D).global_position.distance_to(at)
		if distance > radius:
			continue
		# Linear falloff, so standing at the edge of a blast is meaningfully
		# better than standing on it.
		if node.has_method(&"take_hit"):
			node.call(&"take_hit", config.bomb_damage * (1.0 - distance / radius))
	Effects.explosion(tree.root, at, radius * BLAST_VISUAL_SCALE)
	SoundBank.play_at(&"explosion", at, -4.0, 0.6)


func _detonate() -> void:
	var at: Vector3 = global_position
	blast(get_tree(), at, _config, _team)
	exploded.emit(at)
	queue_free()


func _orient() -> void:
	if _velocity.length_squared() < 0.01:
		return
	var direction: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(direction, up)
