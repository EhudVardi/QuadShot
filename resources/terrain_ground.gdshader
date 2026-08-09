shader_type spatial;

// THE GROUND (GAMEPLAY-DESIGN P1.9), and it is deliberately quiet.
//
// NEON IS RESERVED FOR GAMEPLAY. Neon is this game's signal for *a thing you interact with*: gates, weak points, enemy
// mounts, pickups. Ground wearing the same glow competes with all of it, and in
// a map kilometres across that competition gets worse, not better — a landing
// pad has to be findable against six kilometres of scenery. So the ground is
// matte and the neon is spent on gameplay.
//
// WHAT IT READS BY INSTEAD, chosen because these are the cues that survive
// distance in a vast map:
//
//   SLOPE   — dune faces catch a different tone from dune tops, which is what
//             makes rolling ground legible as rolling rather than as a flat
//             expanse of one colour.
//   HEIGHT  — low sand, mid sand, high crest, so relief reads from kilometres
//             out where surface detail is long gone.
//   GRAIN   — a faint large-scale mottle, so a big empty desert is not a
//             perfectly uniform sheet. Cheap, and it is the difference between
//             "open" and "unfinished".
//
// No textures and no external assets: everything here is arithmetic on world
// position and the surface normal.

uniform vec3 color_low: source_color = vec3(0.44, 0.34, 0.22);
uniform vec3 color_mid: source_color = vec3(0.66, 0.53, 0.35);
uniform vec3 color_high: source_color = vec3(0.80, 0.70, 0.52);
// Slopes steeper than this show rock/shadowed sand rather than open dune top.
uniform vec3 color_slope: source_color = vec3(0.38, 0.30, 0.21);
uniform float height_low = -30.0;
uniform float height_high = 70.0;
// Where the slope tint starts and finishes taking over, as surface flatness.
uniform float slope_start = 0.86;
uniform float slope_end = 0.55;
uniform float grain_scale = 0.0032;
uniform float grain_strength = 0.06;
// Kept so the mesh builder has somewhere to report its sampling scale.
uniform float cell_size = 4.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Cheap value noise from world position. Hash-based rather than a texture, so
// there is no asset and nothing to load.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float lift = clamp((world_pos.y - height_low)
			/ max(height_high - height_low, 0.001), 0.0, 1.0);
	// Two bands rather than one gradient: a single lerp across the whole range
	// washes everything to the midpoint, and the crests stop reading.
	vec3 sand = lift < 0.5
			? mix(color_low, color_mid, lift * 2.0)
			: mix(color_mid, color_high, (lift - 0.5) * 2.0);

	// 1 on flat ground, 0 on a wall. The mesh carries analytic normals from the
	// height field, so this is smooth across ring boundaries where face normals
	// would visibly step.
	float flatness = clamp(world_normal.y, 0.0, 1.0);
	float steep = 1.0 - smoothstep(slope_end, slope_start, flatness);
	sand = mix(sand, color_slope, steep * 0.75);

	float grain = value_noise(world_pos.xz * grain_scale)
			+ 0.5 * value_noise(world_pos.xz * grain_scale * 3.7);
	sand *= 1.0 + (grain / 1.5 - 0.5) * grain_strength * 2.0;

	ALBEDO = sand;
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
