shader_type spatial;

// Neon-panel structures: a dark base with emissive panel seams on every face.
// World-space, so seam spacing stays constant across every box/tower size
// from one shared material. The in-plane axes are chosen from the geometric
// world normal (screen-space derivatives of world position), so the seams lie
// flat on each face regardless of the box's dimensions or orientation. Seams
// bloom under the dev-room glow and read as tech paneling without it. A soft
// height gradient darkens the base of tall structures for grounding.
uniform vec3 base_color: source_color = vec3(0.11, 0.12, 0.15);
uniform vec3 seam_color: source_color = vec3(0.20, 0.70, 1.0);
uniform float seam_energy = 1.8;
uniform float panel_size = 3.0;
// Seam thickness in screen-derivative units (higher = fatter).
uniform float seam_width = 1.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = base_color;
	ROUGHNESS = 0.9;

	// Geometric world-space normal from derivatives — stable on flat faces.
	vec3 n = abs(normalize(cross(dFdx(world_pos), dFdy(world_pos))));
	// The two world axes spanning this face (drop the dominant-normal axis).
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = world_pos.xz;
	} else if (n.x >= n.z) {
		uv = world_pos.zy;
	} else {
		uv = world_pos.xy;
	}

	vec2 coord = uv / panel_size;
	vec2 aa = max(fwidth(coord), vec2(0.0001));
	vec2 to_edge = abs(fract(coord - 0.5) - 0.5) / aa;
	float seam = 1.0 - min(min(to_edge.x, to_edge.y) / seam_width, 1.0);
	EMISSION = seam_color * seam_energy * seam;
}
