shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

// Exit-gate event horizon: a standing pool of light seen face on — the user's
// ask, "like the movie stargate, like a face of a quiet pool".
//
// REPLACES an additive swirling vortex, and the reason is what the two say.
// A whirlpool spins, and spin reads as HAZARD — which is the wrong sentence
// for the one object in the arena that is a reward for clearing a sortie. A
// quiet pool reads as arrival: still, lit from within, and obviously a surface
// rather than a hole. Same fly-through, opposite invitation.
//
// The liquid comes from three cheap things layered, no textures: two
// concentric ripple trains running at different rates and directions so the
// surface never pulses on one beat, a slow domain warp that keeps the rings
// from being perfect circles, and a caustic term that only lights where both
// trains crest at once — which is the highlight that makes water look like
// water instead of like a gradient.
//
// NOT WHAT THE USER AIMED FOR, and the gap is recorded rather than papered
// over (v1.91). The reference is the film's event horizon, and the recipe they
// found for it differs from this one in two structural ways, not in tuning:
//
//   1. POLAR UVs. Convert to (angle, radius) and treat that as the sampling
//      space, so detail wraps seamlessly around the disc. Concentric rings
//      alone — what is here — read as a struck drum; the film's surface has
//      ANGULAR structure that churns as well as radial rings.
//   2. TWO SCROLLING NOISE LAYERS in opposite directions, with the first
//      layer's value DISPLACING the second's UVs. That domain-warped noise is
//      what produces the churning-liquid look. `sin()` trains cannot: they are
//      periodic, and the eye reads periodicity as machinery.
//
// Doing it properly needs a noise source, and the house rule is no external
// assets — so either a `NoiseTexture2D` generated at import (procedural, no
// file, probably acceptable) or a hash-based value-noise function written
// here. That choice is the first decision of the rework, not a detail of it.
// THE BLOOM THRESHOLD IS 1.0, AND THAT IS THE WHOLE BUDGET HERE. The first
// attempt put every one of these above it and the gate rendered as a
// featureless white disc — a pool with no surface on it, because glow had
// eaten the ripples that were the entire point. So: `deep` stays well under
// 1 so the troughs are dark water, `shallow` sits just at it, and only the
// caustic glints and the rim are allowed to bloom.
uniform vec3 deep : source_color = vec3(0.02, 0.09, 0.30);
uniform vec3 shallow : source_color = vec3(0.28, 0.58, 0.88);
uniform float energy = 1.0;
// Rings across the radius — a COUNT, converted to radians below. It read as
// radians at first, which put one and a half broad bands across the whole
// disc: not a rippling pool, a radial gradient. Low is a slow swell, high is
// a struck bell.
uniform float ripple_scale = 5.0;
uniform float ripple_speed = 1.0;
uniform float caustic_gain = 0.55;
// Glints and meniscus are ADDED on top rather than mixed in, which is what
// lets them cross 1.0 while the water underneath stays below it. That split
// is the whole reason the ripples survive: the glow pass blurs whatever it
// catches, so a surface that blooms comes back as a smooth gradient with no
// surface left on it.
uniform float caustic_energy = 1.4;
uniform float rim_energy = 1.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = TIME * ripple_speed;

	// Warp first: rings pushed off-centre read as a disturbed surface, perfect
	// ones read as a target.
	float warp = sin(p.x * 5.0 + t * 0.7) * 0.055 + cos(p.y * 6.0 - t * 0.5) * 0.055;
	float rr = (r + warp) * ripple_scale * 6.28318;
	float wave = sin(rr - t * 2.0) * 0.5 + 0.5;
	float cross_wave = sin(rr * 0.53 + t * 1.3) * 0.5 + 0.5;
	float surface = mix(wave, cross_wave, 0.45);
	// Tight power: glints where both trains crest together, not a general
	// brightening. This is the term that reads as light ON water.
	float caustic = pow(wave * cross_wave, 6.0) * caustic_gain;

	// A faint lift toward the middle, so the pool is subtly *going* somewhere
	// without ever spinning: this is still a doorway.
	float draw_in = smoothstep(1.0, 0.0, r) * 0.06;

	float disc = 1.0 - smoothstep(0.93, 1.0, r);
	// Narrow. A wide rim band plus bloom is a halo, not a meniscus.
	float rim = smoothstep(0.88, 0.98, r) * disc;

	vec3 color = mix(deep, shallow, clamp(surface * 0.9 + draw_in, 0.0, 1.0));
	color += shallow * caustic * caustic_energy;
	color += shallow * rim * rim_energy;
	ALBEDO = color * energy;
	// Opaque: an event horizon is a SURFACE, not a window. The faint ripple
	// left in the alpha is only there to stop the edge reading as a decal.
	ALPHA = clamp(disc * (0.94 + 0.06 * surface), 0.0, 1.0);
}
