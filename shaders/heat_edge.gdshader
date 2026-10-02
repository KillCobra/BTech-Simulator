shader_type canvas_item;
// Heat: a soft coloured glow round the screen edge. `intensity` 0..1 and `tint` come from the HUD.
// No screen texture, so it is cheap on Low quality and does not clash with the danger vignette.

uniform vec4 tint : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c * vec2(1.0, 0.85));
	float a = smoothstep(0.22, 0.68, r) * clamp(intensity, 0.0, 1.0);
	COLOR = vec4(tint.rgb, a);
}
