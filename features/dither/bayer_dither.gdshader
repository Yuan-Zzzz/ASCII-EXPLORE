shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float color_levels : hint_range(2.0, 32.0, 1.0) = 4.0;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;

// Ordered thresholds remain fixed on screen, avoiding temporal flicker.
const float BAYER_4X4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 source = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	ivec2 cell = ivec2(mod(floor(FRAGCOORD.xy / max(pixel_size, 1.0)), 4.0));
	float threshold = (BAYER_4X4[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float steps = max(floor(color_levels + 0.5) - 1.0, 1.0);
	vec3 dithered = clamp(floor(clamp(source, 0.0, 1.0) * steps + threshold) / steps, 0.0, 1.0);
	COLOR = vec4(mix(source, dithered, strength), 1.0);
}
