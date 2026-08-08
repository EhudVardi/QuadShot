shader_type spatial;
render_mode blend_add, cull_back, unshaded, depth_draw_never, shadows_disabled;

// THE PHALANX'S ROTATING SCREEN, SEEN (GAMEPLAY-DESIGN A.q10).
//
// A.q10 is a READABILITY failure, not a mechanics one: the screen it replaces
// worked exactly as specified and the user reported it as a bug twice, because
// a smooth translucent hemisphere looks the same from almost every angle and
// therefore carries no orientation cue. The player was being asked to infer a
// bearing from a shape that does not express one.
//
// So this shader's whole job is to make the mechanic's state readable at a
// glance and in motion. It draws ONE SHELL of slotted armour on a plain sphere
// mesh and CUTS THE SLOTS OUT OF THE GEOMETRY - the gaps are literal holes you
// can see through, so the shield IS the panels and the opening IS the absence
// of a panel. Nothing has to be inferred.
//
// IT IS DRIVEN BY THE SAME NUMBERS THE HIT TEST USES. `phalanx.gd` passes its
// live phase in here every tick and computes `screen_blocks()` from the same
// phase, so the picture cannot disagree with the mechanic - the war room's rule
// (derive the render from the state, never let it keep its own) applied to a
// shader. A cue that disagrees with the mechanic by a little teaches the player
// the wrong edge, and here the wrong edge is the expensive one.
//
// TWO INSTANCES ARE NESTED, counter-rotating at different rates, and a round
// only lands when a slot in each is on its bearing at the same instant. That is
// why they are tinted differently: telling the two apart in motion is what lets
// a pilot read the pattern rather than memorise a rhythm.
//
// ADDITIVE, deliberately. Two nested transparent spheres cannot be depth-sorted
// against each other - they share a centre - so alpha blending would flicker on
// the order. Additive is order-independent, a screen made of light is the right
// fiction anyway, and it leaves the fortress and its stern vent visible THROUGH
// the shells, which matters because those are what the player is aiming at.
//
// AND BACK FACES ARE CULLED, which was a readability fix rather than a saving.
// Drawing both walls of both shells put FOUR curved surfaces over the same
// pixels, and the far wall's slot edges read exactly like the near wall's - so
// the one question the screen has to answer, "is the surface between me and that
// ship open", was buried under three answers to other bearings. Culling is also
// honest here: the screen does not apply to an attacker inside it
// (`Phalanx.SCREEN_INNER_RADIUS_M`), so there is nothing in there to draw.

// Slots in this shell, evenly spaced. 0 disables the shell entirely.
uniform int gaps: hint_range(0, 12) = 3;
// Half-width of one slot, radians.
uniform float gap_half_rad = 0.45;
// Current rotation of this shell, radians. Written every physics tick.
uniform float phase = 0.0;
// Signed rotation rate, deg/s. Only its SIGN is used, to put the bright leading
// bar on the edge the shell is turning toward.
uniform float phase_rate = 1.0;
// THE STERN APERTURE, half-width in radians, centred on the body's own +Z
// (astern). Cut through BOTH shells while the vent is open, so the weak point
// is a hole you can see rather than a rule that contradicts the picture.
uniform float vent_half_rad = 0.0;
// 0 shut, 1 open. Ramped by the body so the aperture irises rather than blinks.
uniform float vent_open = 0.0;
uniform vec3 tint: source_color = vec3(0.35, 0.75, 1.0);
// Overall brightness, so the body can dim the whole screen in one number.
uniform float energy = 1.0;
// A round splashed on this shell, at this bearing. Localised so the flash names
// WHERE it stopped - a hit that lights the whole sphere says nothing.
uniform vec3 flash_dir = vec3(0.0, 0.0, 1.0);
uniform float flash = 0.0;
// Longitude/latitude seam density. The panel seams exist for one reason: they
// are what stops this reading as another featureless dome.
uniform float seam_lon = 40.0;
uniform float seam_lat = 14.0;

varying vec3 v_local;

const float TAU_ = 6.2831853;


void vertex() {
	v_local = VERTEX;
}


// Signed angular distance from `a` to the nearest slot centre of this shell.
float slot_offset(float a) {
	float sector = TAU_ / float(max(gaps, 1));
	return mod(a - phase + sector * 0.5, sector) - sector * 0.5;
}


void fragment() {
	if (gaps <= 0) {
		discard;
	}
	vec3 n = normalize(v_local);
	// Azimuth about the body's own vertical axis. The hit test is taken on a
	// FLAT bearing, so the slots must run pole to pole - a belt would let a
	// pilot climb three metres and shoot over a shield that still stopped them.
	float a = atan(n.x, n.z);
	float off = slot_offset(a);
	if (abs(off) < gap_half_rad) {
		discard;
	}
	// The stern aperture, cut where the body's own +Z points.
	float vent_edge = vent_half_rad * vent_open;
	if (vent_edge > 0.0001 && abs(a) < vent_edge) {
		discard;
	}
	// How far inside the panel this fragment is, in radians. Zero at a slot edge.
	float edge = abs(off) - gap_half_rad;
	float vent_dist = abs(a) - vent_edge;
	if (vent_edge > 0.0001) {
		edge = min(edge, vent_dist);
	}
	// EDGE GLOW. THE SLOT EDGES CARRY THE INFORMATION, so they are far brighter
	// than anything else here. The panel body is kept dim on purpose: this shader
	// is additive, so a bright panel washes out the fortress behind it, and the
	// first version did exactly that — a glowing globe with the ship lost inside
	// it. A pilot has to see what they are shooting at THROUGH the screen.
	float rim = exp(-edge * 11.0);
	// A brighter bar on the side the shell is turning TOWARD, so the direction of
	// rotation is legible from a still frame and not only from watching. `sign`
	// of the offset says which side of the slot centre this fragment is on.
	float lead = (off * sign(phase_rate) > 0.0) ? exp(-edge * 24.0) : 0.0;
	// Panel staves: longitude ribs only. The latitude bands the first version
	// drew turned the shell into a wireframe globe, which is a shape with no
	// direction — the exact failure A.q10 was opened for.
	// THE STAVES ARE WHAT MAKES A PANEL LOOK LIKE A PANEL. Without them a dim
	// additive shell and an empty slot are both black, so the one thing a pilot
	// has to read — is this bearing armoured or open — was invisible. Measured
	// by looking: the first two passes had a legible edge and an unreadable face.
	float ribs = 0.0;
	if (seam_lon > 0.0) {
		float lon = abs(fract(a * seam_lon / TAU_) - 0.5) * 2.0;
		ribs = 1.0 - smoothstep(0.0, 0.16, lon);
	}
	// Fresnel, so the shell's limb reads against the sky instead of dissolving
	// into it. `abs` because the far wall of the sphere is drawn too.
	float facing = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	// The splash, spread over a bearing rather than a point: it says WHICH panel
	// stopped the round. Flattened, because the hit test is flat.
	vec2 here = vec2(n.x, n.z);
	vec2 there = vec2(flash_dir.x, flash_dir.z);
	float aligned = 0.0;
	if (length(here) > 0.001 && length(there) > 0.001) {
		aligned = dot(normalize(here), normalize(there));
	}
	float local_flash = flash * pow(max(aligned, 0.0), 12.0);
	float body = 0.05 + ribs * 0.30 + facing * 0.18 + rim * 0.80 + lead * 0.9
			+ local_flash * 2.2;
	ALBEDO = tint * body * energy;
	EMISSION = tint * body * energy * 1.3;
	ALPHA = 1.0;
}
