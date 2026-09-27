shader_type canvas_item;
// Danger vignette: the screen edges blur (fake depth of field), lose colour,
// darken and tint red, pulsing like a heartbeat. `intensity` 0..1 from the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.02, 0.04, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // round, not oval
	float r = length(c);
	float strength = intensity * (0.85 + 0.15 * pulse);
	// Clear centre, effect ramps up towards the edges; the clear area shrinks with strength.
	float inner = mix(0.62, 0.22, strength);
	float edge = smoothstep(inner, inner + 0.42, r) * strength;

	vec3 sharp = texture(screen_tex, uv).rgb;
	vec3 blurred = textureLod(screen_tex, uv, edge * 4.5).rgb;
	vec3 col = mix(sharp, blurred, clamp(edge * 1.6, 0.0, 1.0));
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), edge * 0.7);
	col = mix(col, col * tint.rgb * 1.6, edge * 0.8);
	col *= 1.0 - edge * 0.75;
	COLOR = vec4(col, 1.0);
}
