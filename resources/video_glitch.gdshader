shader_type canvas_item;

// FPV feed-breakup overlay (GAMEPLAY-DESIGN Iteration 7 / D4). Alpha-blended
// scanlines, static, tear bands and an edge red-wash, all scaled by `glitch`
// [0,1] — the diegetic cost of damage. An overlay (not a screen-displacement)
// so it renders robustly over the 3D feed while the HUD stays crisp on top.
// Guardrail: capped alpha — the wound informs, it never blinds (Dq4).

uniform float glitch = 0.0;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float g = clamp(glitch, 0.0, 1.0);
	vec2 uv = UV;
	float t = TIME;

	// Rolling scanlines.
	float scan = step(0.5, fract(uv.y * 200.0)) * 0.12 * g;
	// Sparse moving static.
	float n = rand(uv * vec2(220.0, 140.0) + vec2(t * 30.0, t * 13.0));
	float noise = step(0.6, n) * 0.18 * g;
	// Occasional horizontal tear bands.
	float band = step(0.985 - 0.02 * g, rand(vec2(floor(uv.y * 24.0), floor(t * 9.0))));
	float tear = band * 0.25 * g;
	// Red wash creeping in from the edges as the feed degrades.
	float edge = smoothstep(0.32, 0.5, distance(uv, vec2(0.5)));

	float a = scan + noise + tear + edge * 0.28 * g;
	vec3 tint = mix(vec3(0.7, 0.9, 1.0), vec3(1.0, 0.2, 0.15), edge);
	COLOR = vec4(tint, clamp(a, 0.0, 0.82));
}
