shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.75, 0.02, 0.0);

void fragment() {
	float edge = smoothstep(0.3, 0.78, distance(UV, vec2(0.5)));
	COLOR = vec4(tint, strength * edge);
}
