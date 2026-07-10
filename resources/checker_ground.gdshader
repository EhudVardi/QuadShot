shader_type spatial;

// World-space checker: keeps cell size constant regardless of mesh UVs/scale,
// so ground speed stays visually readable everywhere on the plane.
uniform float cell_size = 2.0;
uniform vec3 color_a: source_color = vec3(0.42, 0.44, 0.46);
uniform vec3 color_b: source_color = vec3(0.55, 0.57, 0.59);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float checker = mod(floor(world_pos.x / cell_size) + floor(world_pos.z / cell_size), 2.0);
	ALBEDO = mix(color_a, color_b, checker);
	ROUGHNESS = 1.0;
}
