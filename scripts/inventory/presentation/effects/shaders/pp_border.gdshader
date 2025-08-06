// pp_border.gdshader - Edge bloom with spear tapering only at ends
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform bool enable_window_edge_bloom = true;
uniform float edge_bloom_width : hint_range(0.0, 100.0) = 30.0;
uniform float edge_bloom_intensity : hint_range(0.0, 4.0) = 1.5;
uniform vec4 edge_bloom_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float edge_bloom_softness : hint_range(0.1, 20.0) = 8.0;
uniform float edge_falloff : hint_range(0.5, 5.0) = 2.0;
uniform float spear_length : hint_range(0.0, 50.0) = 20.0;

// Window size and bloom extend uniforms
uniform vec2 window_size = vec2(800.0, 600.0);
uniform float bloom_extend = 50.0;

// Edge selection uniforms
uniform bool show_left_edge = false;
uniform bool show_right_edge = false;
uniform bool show_top_edge = false;
uniform bool show_bottom_edge = false;

// Calculate smooth spear taper only at the ends
float calculate_end_spear_taper(float distance_along_edge, float edge_length, float spear_len) {
	// Taper at the start (0 to spear_len)
	float start_taper = smoothstep(0.0, spear_len, distance_along_edge);
	
	// Taper at the end (edge_length-spear_len to edge_length)
	float end_taper = smoothstep(edge_length, edge_length - spear_len, distance_along_edge);
	
	// Return the minimum (most restrictive) taper
	// This ensures we have full intensity in the middle and tapers only at ends
	return min(start_taper, end_taper);
}

void fragment() {
	vec2 uv = UV;
	vec2 overlay_size = window_size + vec2(bloom_extend * 2.0);
	vec2 overlay_pos = uv * overlay_size;
	
	// Calculate position relative to window boundaries
	vec2 window_start = vec2(bloom_extend, bloom_extend);
	vec2 window_end = window_start + window_size;
	
	// Calculate distance from each window edge
	float left_dist = overlay_pos.x - window_start.x;
	float right_dist = window_end.x - overlay_pos.x;
	float top_dist = overlay_pos.y - window_start.y;
	float bottom_dist = window_end.y - overlay_pos.y;
	
	float bloom_factor = 0.0;
	
	// Left edge - full height with end tapering
	if (show_left_edge && left_dist <= edge_bloom_width) {
		// Check if we're within the extended vertical bounds (allowing for spear tapering)
		float extended_start = window_start.y - spear_length;
		float extended_end = window_end.y + spear_length;
		
		if (overlay_pos.y >= extended_start && overlay_pos.y <= extended_end) {
			float factor = 1.0 - (abs(left_dist) / edge_bloom_width);
			
			// Calculate end taper based on position along the edge
			float distance_from_top = overlay_pos.y - extended_start;
			float total_edge_length = extended_end - extended_start;
			float spear_taper = calculate_end_spear_taper(distance_from_top, total_edge_length, spear_length);
			
			factor *= spear_taper;
			bloom_factor = max(bloom_factor, factor);
		}
	}
	
	// Right edge - full height with end tapering
	if (show_right_edge && right_dist <= edge_bloom_width) {
		float extended_start = window_start.y - spear_length;
		float extended_end = window_end.y + spear_length;
		
		if (overlay_pos.y >= extended_start && overlay_pos.y <= extended_end) {
			float factor = 1.0 - (abs(right_dist) / edge_bloom_width);
			
			float distance_from_top = overlay_pos.y - extended_start;
			float total_edge_length = extended_end - extended_start;
			float spear_taper = calculate_end_spear_taper(distance_from_top, total_edge_length, spear_length);
			
			factor *= spear_taper;
			bloom_factor = max(bloom_factor, factor);
		}
	}
	
	// Top edge - full width with end tapering
	if (show_top_edge && top_dist <= edge_bloom_width) {
		float extended_start = window_start.x - spear_length;
		float extended_end = window_end.x + spear_length;
		
		if (overlay_pos.x >= extended_start && overlay_pos.x <= extended_end) {
			float factor = 1.0 - (abs(top_dist) / edge_bloom_width);
			
			float distance_from_left = overlay_pos.x - extended_start;
			float total_edge_length = extended_end - extended_start;
			float spear_taper = calculate_end_spear_taper(distance_from_left, total_edge_length, spear_length);
			
			factor *= spear_taper;
			bloom_factor = max(bloom_factor, factor);
		}
	}
	
	// Bottom edge - full width with end tapering
	if (show_bottom_edge && bottom_dist <= edge_bloom_width) {
		float extended_start = window_start.x - spear_length;
		float extended_end = window_end.x + spear_length;
		
		if (overlay_pos.x >= extended_start && overlay_pos.x <= extended_end) {
			float factor = 1.0 - (abs(bottom_dist) / edge_bloom_width);
			
			float distance_from_left = overlay_pos.x - extended_start;
			float total_edge_length = extended_end - extended_start;
			float spear_taper = calculate_end_spear_taper(distance_from_left, total_edge_length, spear_length);
			
			factor *= spear_taper;
			bloom_factor = max(bloom_factor, factor);
		}
	}
	
	// Apply falloff curve
	bloom_factor = pow(clamp(bloom_factor, 0.0, 1.0), edge_falloff);
	
	// Calculate final bloom color
	vec3 bloom_rgb = edge_bloom_color.rgb * edge_bloom_intensity * bloom_factor;
	
	COLOR = vec4(bloom_rgb, bloom_factor);
}