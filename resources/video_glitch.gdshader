shader_type canvas_item;

// FPV feed-breakup overlay (GAMEPLAY-DESIGN Iteration 7 / D4). Two layers: a
// smooth ambient wash that scales with `glitch`, and — above a threshold — a
// set of SUDDEN tear/dropout bands that punch on when a hit spikes `glitch`,
// then vanish as it decays. That gives each hit an abrupt, unexpected signal
// break rather than a gentle fade. Guardrail: capped alpha — informs, never
// blinds (Dq4).

uniform float glitch = 0.0;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float g = clamp(glitch, 0.0, 1.0);
	vec2 uv = UV;
	float t = TIME;

	// Ambient layer: scanlines + fine static, scales smoothly with damage.
	float scan = step(0.5, fract(uv.y * 220.0)) * 0.10 * g;
	float stat = step(0.55, rand(uv * vec2(260.0, 150.0) + vec2(t * 40.0, t * 17.0)))
			* 0.20 * g;

	// Punch layer: gated so it SNAPS on when a hit drives glitch past ~0.25,
	// then collapses as glitch decays — the abrupt, sudden break.
	float punch = smoothstep(0.25, 0.55, g);
	float band = floor(uv.y * 26.0);
	// Whole horizontal bands flash near-opaque (signal dropout), reshuffled fast.
	float dropout = step(0.72, rand(vec2(band, floor(t * 20.0)))) * punch;
	// A few bands tear sideways with a hard colored streak.
	float tear = step(0.86, rand(vec2(band, floor(t * 27.0) + 3.0))) * punch;

	// Red wash creeping from the edges as the feed degrades.
	float edge = smoothstep(0.30, 0.5, distance(uv, vec2(0.5)));

	float a = scan + stat + dropout * 0.75 + tear * 0.5 + edge * 0.30 * g;
	vec3 tint = mix(vec3(0.7, 0.9, 1.0), vec3(1.0, 0.25, 0.2), edge);
	tint = mix(tint, vec3(1.0), dropout * 0.7);          // dropouts flash hot
	tint = mix(tint, vec3(1.0, 0.4, 0.9), tear * 0.8);   // tears streak magenta
	COLOR = vec4(tint, clamp(a, 0.0, 0.9));
}
