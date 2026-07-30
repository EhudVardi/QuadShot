shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled;

// Screamer cloak (GAMEPLAY-DESIGN v1.89, the user's ask: "like the predator
// from the movie, where reality is ever so slightly distorted") — built the
// only way the house rules allow: no textures, no assets, just the screen
// behind the surface, sampled at an offset.
//
// THE WHOLE TRICK IS THAT ZERO DISTORTION MEANS INVISIBLE. At `shimmer` 0 the
// offset is zero, so every fragment samples exactly the pixel it is covering
// and the body disappears perfectly — not faded, not ghosted, gone. Turn
// `shimmer` up and the same surface starts bending what is behind it. So one
// number spans "cannot be seen at all" to "unmissable heat-haze", and the
// script hands that number the JAM LEVEL: the interference that ruins your
// gear is the same thing that shows you where it is coming from.
//
// The offset is weighted by the view-space NORMAL, so the refraction runs
// around the silhouette rather than sliding uniformly — and by a fresnel term,
// so the edges bend hardest. That is what makes it read as a shape you can
// almost see instead of a smeared rectangle.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 = perfectly invisible, 1 = maximum haze. Driven from the jam field.
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
// 1 = the cloak is down and the hull is solid. Punched to 1 on every hit, or
// the player has no way to know their rounds are landing on a thing they
// cannot see.
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
// Peak screen-UV displacement at full shimmer. The single strongest feel knob
// in the file: too low and the cloak is perfect at every range, too high and
// it fights the video-breakup overlay for the same screen.
uniform float distortion : hint_range(0.0, 0.2) = 0.045;
// How hard the effect concentrates at grazing angles. Higher = a thinner, more
// defined outline; lower = a rounder blob.
uniform float edge_power : hint_range(1.0, 8.0) = 2.5;
// A slow boil, so the lens breathes. A perfectly steady refraction reads as a
// glass prop rather than as something actively working to hide.
uniform float boil_speed : hint_range(0.0, 12.0) = 2.4;
// Palette rule (CLAUDE.md): red = threat, and a fully colourless enemy has no
// role written on it. A faint hot rim rides the silhouette, and it only
// appears where the cloak is already shimmering — so it never gives away a
// screamer the jam has not already announced.
uniform vec3 edge_tint : source_color = vec3(1.0, 0.18, 0.12);
uniform float edge_energy : hint_range(0.0, 3.0) = 0.55;
// What the hull looks like with the cloak down. Lifted slightly above the
// 0.13/0.12/0.15 of the StandardMaterial3D it replaces, because `unshaded`
// means no light ever reaches it: the raw albedo that read as a dark grey box
// under the sun reads as a black cut-out on its own. Raise it further if the
// reveal should look less like a silhouette.
uniform vec3 body_color : source_color = vec3(0.20, 0.18, 0.23);
uniform float cloak_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Grazing angles refract hardest — this is the term that turns a lens into
	// a silhouette.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = pow(1.0 - facing, edge_power);
	float wobble = 0.65 + 0.35 * sin(TIME * boil_speed + VERTEX.y * 6.0);

	// NORMAL is view space in fragment(), so its xy is already the screen-plane
	// direction the surface faces — exactly the axis a refraction should push
	// along. No extra basis maths, and it stays correct as the camera rolls,
	// which on a quad is most of the time.
	vec2 offset = NORMAL.xy * distortion * shimmer * wobble * (0.25 + edge);
	vec3 refracted = texture(screen_tex, SCREEN_UV + offset).rgb;
	refracted += edge_tint * edge * shimmer * edge_energy;

	ALBEDO = mix(refracted, body_color, reveal);
	ALPHA = mix(cloak_alpha, 1.0, reveal);
}
