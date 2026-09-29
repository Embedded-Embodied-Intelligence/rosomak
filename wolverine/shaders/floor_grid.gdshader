shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.24, 0.25, 0.27);
uniform vec3 line_color : source_color = vec3(0.34, 0.33, 0.33);
uniform vec3 ring_color : source_color = vec3(0.55, 0.3, 0.16);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 2 m grid lines help read distance and speed on an otherwise flat floor.
	vec2 cell = abs(fract(world_position.xz * 0.5) - 0.5);
	float line = smoothstep(0.47, 0.5, max(cell.x, cell.y));
	float radius = length(world_position.xz);
	float ring = 1.0 - smoothstep(0.0, 0.1, abs(radius - 6.0));
	vec3 color = mix(base_color, line_color, line);
	ALBEDO = mix(color, ring_color, ring * 0.8);
	ROUGHNESS = 1.0;
}
