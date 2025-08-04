// bloom_glow.gdshader - Enhanced EVE Online style bloom with superior falloff
shader_type canvas_item;

uniform float bloom_intensity : hint_range(0.0, 4.0) = 2.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.15;
uniform float outer_radius : hint_range(0.0, 2.0) = 0.6;
uniform vec4 glow_color : source_color = vec4(0.6, 0.8, 1.0, 0.8);
uniform bool enable_pulse = false;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float falloff_power : hint_range(1.0, 6.0) = 3.0;
uniform float edge_softness : hint_range(0.1, 2.0) = 0.8;

// Enhanced smooth circle with multiple falloff options
float enhanced_smooth_circle(vec2 uv, vec2 center, float radius, float softness, float power) {
	float dist = distance(uv, center);
	
	// Smooth transition with customizable power curve
	float factor = 1.0 - smoothstep(radius - softness, radius + softness, dist);
	
	// Apply power curve for different falloff shapes
	factor = pow(factor, power);
	
	return factor;
}

// Multi-layer bloom with different characteristics
float layered_bloom(vec2 uv, vec2 center, float inner_r, float outer_r, float softness, float power) {
	// Core bright center
	float core = enhanced_smooth_circle(uv, center, inner_r, softness * 0.3, power * 0.8);
	
	// Mid-range glow
	float mid = enhanced_smooth_circle(uv, center, mix(inner_r, outer_r, 0.6), softness * 0.6, power);
	
	// Outer soft halo
	float outer = enhanced_smooth_circle(uv, center, outer_r, softness, power * 1.2);
	
	// Combine layers with different intensities
	float result = outer * 0.3;
	
	// Smooth falloff at the edges
	result *= smoothstep(outer_r + softness, outer_r - softness * 0.2, distance(uv, center));
	
	return clamp(result, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5, 0.5);
	
	// Calculate enhanced bloom with layered falloff
	float bloom_factor = layered_bloom(uv, center, inner_radius, outer_radius, edge_softness, falloff_power);
	
	// Add subtle pulse effect
	if (enable_pulse) {
		float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed);
		bloom_factor *= pulse;
	}
	
	// Apply color with enhanced blending
	vec4 bloom_color = glow_color * bloom_intensity * bloom_factor;
	
	// Subtle color variation based on distance for more organic look
	float dist_to_center = distance(uv, center);
	vec3 color_variation = mix(
		glow_color.rgb * 1.1, // Slightly brighter center
		glow_color.rgb * 0.9, // Slightly dimmer edges
		smoothstep(inner_radius, outer_radius, dist_to_center)
	);
	
	bloom_color.rgb = color_variation * bloom_intensity * bloom_factor;
	
	COLOR = vec4(bloom_color.rgb, bloom_color.a * bloom_factor);
}