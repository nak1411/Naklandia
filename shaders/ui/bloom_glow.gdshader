// eve_bloom_glow.gdshader - EVE Online style bloom glow effect
shader_type canvas_item;

uniform float bloom_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float bloom_radius : hint_range(0.1, 10.0) = 2.0;
uniform vec4 glow_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float edge_softness : hint_range(0.1, 5.0) = 1.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform bool enable_pulse : hint_range(0.0, 1.0) = true;

// EVE-style gradient for bloom falloff
float eve_gradient(float distance, float radius) {
	float normalized = distance / radius;
	return exp(-normalized * 3.0) * (1.0 - smoothstep(0.0, 1.0, normalized));
}

void fragment() {
	vec2 uv = UV;
	vec4 original_color = texture(TEXTURE, uv);
	
	vec2 center = vec2(0.5, 0.5);
	float dist_from_center = distance(uv, center);
	
	float bloom_factor = eve_gradient(dist_from_center, bloom_radius);
	
	float pulse = 1.0;
	if (enable_pulse) {
		pulse = 0.8 + 0.2 * sin(TIME * pulse_speed);
	}
	
	vec4 bloom_contribution = glow_color * bloom_intensity * bloom_factor * pulse;
	
	vec4 final_color = original_color;
	if (length(original_color.rgb) > bloom_threshold) {
		final_color += bloom_contribution;
	}
	
	final_color.a = original_color.a;
	COLOR = final_color;
}