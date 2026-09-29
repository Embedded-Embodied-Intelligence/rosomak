shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.95, 0.25, 0.2, 1.0);

void vertex() {
	// Face the camera while keeping the node's world position.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 inner = step(vec2(0.015, 0.14), UV) * step(UV, vec2(0.985, 0.86));
	vec3 color = UV.x < fill ? fill_color.rgb : vec3(0.08);
	ALBEDO = inner.x * inner.y > 0.5 ? color : vec3(0.0);
	ALPHA = 0.92;
}
