shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

// Exit-gate portal surface: an additive swirling vortex filling the gate's
// opening. Unshaded + energy > 1 so it blooms under the look pass; additive
// blend keeps the world faintly visible through it (it's a doorway, not a
// wall). TIME-driven, no textures.
uniform vec3 color_a: source_color = vec3(0.10, 0.55, 1.0);
uniform vec3 color_b: source_color = vec3(0.55, 0.90, 1.0);
uniform float energy = 2.2;
uniform float swirl = 6.0;
uniform float spin_speed = 2.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float wave = sin(angle * 3.0 + swirl * r - TIME * spin_speed) * 0.5 + 0.5;
	float rim = smoothstep(1.0, 0.55, r);      // fade out toward the frame
	float core = smoothstep(0.95, 0.15, r);    // brighten toward the center
	ALBEDO = mix(color_a, color_b, wave) * energy;
	ALPHA = rim * (0.30 + 0.45 * wave) * (0.35 + 0.65 * core);
}
