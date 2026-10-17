shader_type spatial;
render_mode unshaded, depth_draw_never, specular_disabled;

// Overlay pass: quantize the opaque model after Godot has lit it.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform float u_color_levels : hint_range(2.0, 16.0, 1.0) = 2.0;
uniform float u_pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
// 光照权重：屏幕里还没有抖动的画面（含太阳、黑洞等所有原生光源）作为亮度乘数，
// 叠加到字符颜色上，所以多个光源可以同时照亮模型，抖动只量化表面颜色。
uniform sampler2D lit_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform float lit_weight = 0.0;
// 光源的原始亮度（合成前 HDR），超过 1 的部分截到 1 避免过曝。
uniform float lit_exposure = 1.0;
const float BAYER_4X4[16] = float[16](
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0
);
void fragment() {
    vec3 source = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
    if (lit_weight > 0.5) {
        source *= textureLod(lit_texture, SCREEN_UV, 0.0).rgb * lit_exposure;
    }
    ivec2 cell = ivec2(mod(floor(FRAGCOORD.xy / max(u_pixel_size, 1.0)), 4.0));
    float threshold = (BAYER_4X4[cell.y * 4 + cell.x] + 0.5) / 16.0;
    float levels = max(floor(u_color_levels + 0.5) - 1.0, 1.0);
    ALBEDO = clamp(floor(clamp(source, 0.0, 1.0) * levels + threshold) / levels, 0.0, 1.0);
}
