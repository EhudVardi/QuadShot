class_name ObjectiveAsset
extends StaticBody3D

## The thing you came to destroy (GAMEPLAY-DESIGN Iteration 12, W5).
##
## A Strike's objective, and the only piece of genuine CONTENT the bridge
## needed: `SortieComposer` has emitted `objective_assets: 1..4` since v1.71 and
## nothing in the project could build one. `target.tscn` is a floating score
## pickup that respawns; this is a structure whose death is the sortie.
##
## THE OBJECTIVE IS THE CAPTURE GATE, NOT THE FIGHT (P2.9, and W5's stated
## trap). An asset that dies instantly makes the garrison decoration; one that
## takes a minute makes the sortie a health bar with scenery. The fight is the
## garrison you have to survive WHILE spending time on this, so the hull is
## sized to be a commitment rather than a duel.
##
## HOT WHITE, and the palette had a hole exactly this shape (W.q5, steered).
## Cyan is navigation, red is threat, orange is score, amber is pylons and
## flak, green is pads, violet is missiles, yellow is your own fire — nothing
## claimed "the thing you came for". Red was rejected on a specific ground: a
## building and a raider must never read the same at a glance, because that is
## the one confusion that wastes a whole sortie. P2.7 forbids quest markers, so
## the structure has to announce itself by looking like nothing else does.
##
## IT LEAVES A HUSK. A destroyed asset goes dark and KEEPS its collision, for
## the same reason a spent resupply gate stays in the world: a thing that
## vanishes teaches nothing about where you have already been, and a wrecked
## hall is still cover you can mask behind on the way out. Egress is a real
## phase now (W.q3), so the ruins you made are terrain you get to use.

signal destroyed(points: float)
## The trigger P2.3 actually cares about: a Strike's reserve scrambles on
## `objective_damaged`, which is what turns the objective from a task into a
## decision about WHEN. You may scout, position and kill the pickets first,
## because the clock starts when you touch the thing you came for.
signal first_damaged

## Hot white, above the 1.0 bloom threshold so it blooms rather than just
## reads bright.
const LIVE_COLOR := Color(1.0, 0.98, 0.92)
const LIVE_ENERGY: float = 2.6
## What is left standing afterwards: unlit, desaturated, unmistakably spent.
const DEAD_COLOR := Color(0.20, 0.20, 0.22)

## PROVISIONAL, and this is pacing (handoff section 14). 200 is eight blaster
## bolts, or four flak shells inside the burst, or two thirds of a missile.
## Three of them is most of a heat magazine, which makes a Strike the first
## MANDATORY sink the ammunition economy has ever had — Iteration 10 built
## magazines and then only ever asked you to spend them on things that shoot
## back. Worth feeling before it is trusted.
@export var hull: float = 200.0
@export var points: float = 300.0
## Footprint. Big enough to find from an ingress, small enough that three of
## them are three targets rather than a wall.
@export var size := Vector3(7.0, 9.0, 7.0)

## Read by projectiles: this is the enemy's infrastructure, so the player's
## rounds bite and the garrison's do not.
var team: StringName = &"enemy"

var _health: Health
var _material: StandardMaterial3D
var _hit_once: bool = false


func _ready() -> void:
	add_to_group(&"objectives")
	_build()


func alive() -> bool:
	return _health != null and _health.alive


## Projectiles call this on whatever they hit (the shared combat contract).
func take_hit(damage: float) -> void:
	if _health == null or not _health.alive:
		return
	_health.take(damage)
	if not _hit_once:
		_hit_once = true
		first_damaged.emit()


func _build() -> void:
	_health = Health.new()
	_health.max_health = hull
	_health.died.connect(_on_died)
	add_child(_health)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.34, 0.34, 0.38)
	_material.emission_enabled = true
	_material.emission = LIVE_COLOR
	_material.emission_energy_multiplier = LIVE_ENERGY
	# Only the seams and the crown glow; a solid glowing block reads as a lamp
	# rather than as a building, and loses its silhouette against the bloom.
	_material.emission_texture = null

	var hall := BoxMesh.new()
	hall.size = size
	var body := MeshInstance3D.new()
	body.mesh = hall
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	var hull_material := StandardMaterial3D.new()
	hull_material.albedo_color = Color(0.24, 0.25, 0.29)
	body.material_override = hull_material
	add_child(body)

	# The crown is what you actually pick out at 200 m: a lit band across the
	# top, so the asset is findable from an ingress without a HUD marker.
	var crown := BoxMesh.new()
	crown.size = Vector3(size.x * 1.12, 0.55, size.z * 1.12)
	var cap := MeshInstance3D.new()
	cap.mesh = crown
	cap.position = Vector3(0.0, size.y + 0.2, 0.0)
	cap.material_override = _material
	add_child(cap)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(collision)


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position + Vector3.UP * size.y * 0.5, 2.4)
	# Dark, but still standing and still solid: a husk is cover on the way out.
	_material.emission_enabled = false
	_material.albedo_color = DEAD_COLOR
	destroyed.emit(points)
