// pixel_perfect_border.gdshader - Sharp pixel-perfect borders
shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float border_width : hint_range(1.0, 10.0) = 2.0;
uniform bool anti_alias = false;

void fragment() {
	vec2 uv = UV;
	vec4 tex_color = texture(TEXTURE, uv);
	
	// Calculate distance to edges
	float left = uv.x;
	float right = 1.0 - uv.x;
	float top = uv.y;
	float bottom = 1.0 - uv.y;
	
	float min_dist = min(min(left, right), min(top, bottom));
	float border_factor = 1.0 - step(border_width / 100.0, min_dist);
	
	COLOR = mix(tex_color, border_color, border_factor);
}