// text_glow.gdshader - EVE-style text glow effect
shader_type canvas_item;

uniform float glow_strength : hint_range(0.0, 3.0) = 1.5;
uniform vec4 glow_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float glow_size : hint_range(1.0, 8.0) = 3.0;
uniform bool enable_pulse = false;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
    vec4 base_color = texture(TEXTURE, UV);
    
    // Create glow by sampling surrounding pixels
    vec4 glow = vec4(0.0);
    float total_weight = 0.0;
    
    // Sample in a circle around the current pixel
    for (float angle = 0.0; angle < 6.28318; angle += 0.785398) { // 8 samples
        for (float radius = 1.0; radius <= glow_size; radius += 1.0) {
            vec2 offset = vec2(cos(angle), sin(angle)) * radius;
            vec2 sample_uv = UV + offset / tex_size;
            
            vec4 sample_color = texture(TEXTURE, sample_uv);
            float weight = 1.0 - (radius / glow_size);
            weight = weight * weight; // Quadratic falloff
            
            glow += sample_color * weight;
            total_weight += weight;
        }
    }
    
    if (total_weight > 0.0) {
        glow /= total_weight;
    }
    
    // Apply pulsing effect if enabled
    float pulse_factor = 1.0;
    if (enable_pulse) {
        pulse_factor = 0.8 + 0.2 * sin(TIME * pulse_speed);
    }
    
    // Combine glow with original
    vec4 final_color = base_color;
    
    // If there's text content, add glow behind it
    if (glow.a > 0.01) {
        vec3 glow_contribution = glow_color.rgb * glow_strength * glow.a * pulse_factor;
        final_color.rgb = mix(glow_contribution, base_color.rgb, base_color.a);
        final_color.a = max(base_color.a, glow.a * glow_color.a * 0.5);
    }
    
    COLOR = final_color;
}