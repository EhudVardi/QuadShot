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

	float fade = 1.0 - smoothstep(0.0, fade_distance, distance(world_pos, CAMERA_POSITION_WORLD));
	EMISSION = grid_color * grid_energy * line * fade;
}
