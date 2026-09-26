shader_type spatial;
// Vertex-coloured blocks with softly highlighted edges, faking a small bevel
// so every block reads as a chunky toy piece. UV = position on face (metres),
// UV2 = face size (metres), both written by scripts/voxel.gd.
//
// The bevel is anti-aliased with screen-space derivatives: when a bevel gets
// thinner than a few pixels (far away, or at a grazing angle) it fades out
// instead of sparkling on and off as the camera moves.

uniform float bevel_width : hint_range(0.0, 0.2) = 0.06;
uniform float bevel_light : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec2 to_edge = min(UV, UV2 - UV);
	float dist = min(to_edge.x, to_edge.y);
	float width = min(bevel_width, 0.3 * min(UV2.x, UV2.y));
	// Metres covered by one pixel here.
	float px = max(max(fwidth(UV.x), fwidth(UV.y)), 1e-5);
	float soft = max(width, px * 1.5);
	float edge = 1.0 - smoothstep(0.0, soft, dist);
	// Bevels narrower than ~3 pixels fade away (no shimmering highlights).
	edge *= clamp((width / px - 1.5) / 2.0, 0.0, 1.0);
	vec3 base = srgb_to_linear(COLOR.rgb);
	ALBEDO = mix(base, base * 1.3 + 0.025, edge * bevel_light);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.08;
}
