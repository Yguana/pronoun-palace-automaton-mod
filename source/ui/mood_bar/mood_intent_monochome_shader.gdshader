shader_type canvas_item;
uniform bool set_to_monochrome = false;

void fragment() {
	if (set_to_monochrome) {
	COLOR.r = COLOR.g;
	COLOR.g = COLOR.g;
	COLOR.b = COLOR.g;
	}
}
