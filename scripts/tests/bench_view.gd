class_name BenchView
extends RefCounted

## Shared watch mode for every headless bench (v1.25, standing policy at the
## user's call: "essential, not just a nice-to-have").
##
## Any bench in this folder runs headless by default and prints numbers. Drop
## `--headless` and it should instead RENDER, so the human can check with
## their own eyes what the numbers claim. That is not a luxury here — it is
## how this project's founding tenet applies to its instruments. The aegis
## ramming bug (v1.25) is the case in point: the numbers said "1.0 missiles
## launched, timeout" for days' worth of reasoning, and thirty seconds of
## watching would have said "it flew into the bomber."
##
## Every new bench should call `watching()`, `setup()` and `build_scenery()`
## rather than rolling its own, so watch mode arrives with the bench instead
## of being retrofitted after something goes unexplained.
##
## The scenery is VISUAL ONLY and deliberately so: the floor is a mesh with NO
## collider, so a watched run is physically identical to a measured one. An
## instrument must not read differently when observed.

## True when a display is attached (i.e. `--headless` was omitted).
static func watching() -> bool:
	return DisplayServer.get_name() != "headless"


## Call once at bench start. Mutes audio — a rig that restarts a run every few
## seconds turns motor tone into a stuttering drone with no mixing around it,
## which makes watching a chore. This is a measurement instrument; the game is
## where sound belongs.
static func setup(label: String) -> void:
	if not watching():
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	print("[%s] WATCH MODE — audio muted, rendering from the rig's camera."
			% label)


## Minimum scenery needed to SEE: a sun, a sky, and a grid floor for motion
## reference. The measured arena is deliberately bare (headless rendering
## costs time and proves nothing), but watching a bare arena means staring
## into a black void with an unlit drone in it.
static func build_scenery(parent: Node3D) -> void:
	if not watching():
		return
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.1
	parent.add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_horizon_color = Color(0.35, 0.38, 0.45)
	sky_material.ground_horizon_color = Color(0.12, 0.13, 0.16)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(600.0, 600.0)
	var floor_material := ShaderMaterial.new()
	floor_material.shader = load("res://resources/checker_ground.gdshader")
	floor_mesh.material = floor_material
	var ground := MeshInstance3D.new()
	ground.mesh = floor_mesh
	parent.add_child(ground)


## Ride along with the rig: its own gun camera is the honest view of what the
## aim loop is doing.
static func follow(drone: Node) -> void:
	if not watching() or drone == null:
		return
	var view: Camera3D = drone.get_node_or_null("FpvCamera") as Camera3D
	if view != null:
		view.current = true
