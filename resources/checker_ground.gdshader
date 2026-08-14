shader_type spatial;

// World-space neon grid. Constant cell size regardless of mesh UVs/scale, so
// ground speed stays readable everywhere on the plane. A dark checker gives
// base contrast; emissive grid lines at cell boundaries give the neon-
// greybox look — they bloom under the dev-room glow and just read as thin
// lines without it. Lines are anti-aliased with fwidth and faded with camera
// distance so the far plane never moires.
uniform float cell_size = 2.0;
uniform vec3 color_a: source_color = vec3(0.16, 0.17, 0.20);
uniform vec3 color_b: source_color = vec3(0.19, 0.20, 0.24);
uniform vec3 grid_color: source_color = vec3(0.20, 0.75, 1.0);
uniform float grid_energy = 2.5;
// Line thickness, in screen-derivative units (higher = fatter).
uniform float grid_width = 1.5;
// Grid emission fades to nothing by this camera distance (kills far moire).
uniform float fade_distance = 130.0;

// A SECOND, COARSER GRID every `major_every` cells — off at 0, which is every
// scene that existed before the scale yard needed it. One grid is a texture;
// two are a RULER, because the eye can count ten small cells into one big one
// and read a distance off the ground without a HUD. It carries its own fade
// because the whole point is that it survives to a range where the fine grid
// has long since dissolved into moire.
uniform float major_every = 0.0;
uniform vec3 major_color: source_color = vec3(0.55, 0.90, 1.0);
uniform float major_energy = 3.5;
uniform float major_width = 2.5;
uniform float major_fade_distance = 2400.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float checker = mod(floor(world_pos.x / cell_size) + floor(world_pos.z / cell_size), 2.0);
	ALBEDO = mix(color_a, color_b, checker);
	ROUGHNESS = 1.0;

	// Anti-aliased distance to the nearest cell boundary, in cells.
	vec2 coord = world_pos.xz / cell_size;
	vec2 aa = max(fwidth(coord), vec2(0.0001));
	vec2 to_edge = abs(fract(coord - 0.5) - 0.5) / aa;
	float line = 1.0 - min(min(to_edge.x, to_edge.y) / grid_width, 1.0);

	float camera_m = distance(world_pos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(0.0, fade_distance, camera_m);
	EMISSION = grid_color * grid_energy * line * fade;

	if (major_every > 0.5) {
		vec2 mcoord = world_pos.xz / (cell_size * major_every);
		vec2 maa = max(fwidth(mcoord), vec2(0.0001));
		vec2 mto_edge = abs(fract(mcoord - 0.5) - 0.5) / maa;
		float mline = 1.0 - min(min(mto_edge.x, mto_edge.y) / major_width, 1.0);
		float mfade = 1.0 - smoothstep(0.0, major_fade_distance, camera_m);
		EMISSION += major_color * major_energy * mline * mfade;
	}
}
