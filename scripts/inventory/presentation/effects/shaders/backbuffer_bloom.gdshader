// backbuffer_bloom.gdshader - True bloom effect using BackBufferCopy
shader_type canvas_item;

uniform float bloom_intensity : hint_range(0.0, 5.0) = 2.0;
uniform vec4 bloom_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.4;
uniform float blur_radius : hint_range(1.0, 15.0) = 6.0;
uniform float bloom_spread : hint_range(0.5, 3.0) = 1.5;
uniform bool enable_pulse = false;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;

// Gaussian blur weights for smoother bloom
const float blur_weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

vec4 sample_blur(sampler2D tex, vec2 uv, vec2 direction, float radius) {
    vec4 result = texture(tex, uv) * blur_weights[0];
    
    for (int i = 1; i < 5; i++) {
        vec2 offset = direction * float(i) * radius * TEXTURE_PIXEL_SIZE;
        result += texture(tex, uv + offset) * blur_weights[i];
        result += texture(tex, uv - offset) * blur_weights[i];
    }
    
    return result;
}

void fragment() {
    vec2 uv = UV;
    vec4 base_color = texture(TEXTURE, uv);
    
    // Sample the screen buffer for bloom
    vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);
    
    // Extract bright areas
    float brightness = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
    vec4 bright_areas = vec4(0.0);
    
    if (brightness > bloom_threshold) {
        bright_areas = screen_color;
        bright_areas.rgb *= (brightness - bloom_threshold) / (1.0 - bloom_threshold);
    }
    
    // Apply horizontal blur
    vec4 blur_h = sample_blur(SCREEN_TEXTURE, SCREEN_UV, vec2(1.0, 0.0), blur_radius * bloom_spread);
    
    // Apply vertical blur
    vec4 blur_v = sample_blur(SCREEN_TEXTURE, SCREEN_UV, vec2(0.0, 1.0), blur_radius * bloom_spread);
    
    // Combine blurs for radial effect
    vec4 bloom_effect = (blur_h + blur_v) * 0.5;
    
    // Only keep bright parts of the bloom
    float bloom_brightness = dot(bloom_effect.rgb, vec3(0.299, 0.587, 0.114));
    if (bloom_brightness > bloom_threshold) {
        bloom_effect.rgb *= (bloom_brightness - bloom_threshold) / (1.0 - bloom_threshold);
    } else {
        bloom_effect = vec4(0.0);
    }
    
    // Apply pulsing effect
    float pulse_factor = 1.0;
    if (enable_pulse) {
        pulse_factor = 0.7 + 0.3 * sin(TIME * pulse_speed);
    }
    
    // Combine with bloom color and intensity
    vec3 final_bloom = bloom_effect.rgb * bloom_color.rgb * bloom_intensity * pulse_factor;
    
    // Additive blend with base
    vec3 final_color = base_color.rgb + final_bloom;
    
    COLOR = vec4(final_color, base_color.a);
}