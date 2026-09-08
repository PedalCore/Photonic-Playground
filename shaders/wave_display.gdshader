shader_type canvas_item;
render_mode unshaded;

uniform sampler2D energy_texture : filter_linear;
uniform float exposure : hint_range(0.2, 8.0) = 2.3;
uniform int view_mode = 0;

void fragment() {
	vec3 wave = texture(TEXTURE, UV).rgb;
	vec3 energy = texture(energy_texture, UV).rgb;
	vec3 color;
	if (view_mode == 1) {
		color = vec3(1.0) - exp(-energy * exposure * 4.0);
	} else if (view_mode == 2) {
		float signed_wave = wave.r + wave.g + wave.b;
		color = (signed_wave > 0.0 ? vec3(0.30, 0.93, 0.79) : vec3(0.68, 0.42, 0.95)) * (1.0 - exp(-abs(signed_wave) * exposure));
	} else {
		color = (vec3(1.0) - exp(-abs(wave) * exposure * 1.8)) * 0.78;
		color += (vec3(1.0) - exp(-energy * exposure * 2.0)) * 0.3;
	}
	// Three numerical bands shown as red, green and blue; display is false color.
	vec3 base = vec3(0.033, 0.057, 0.081);
	COLOR = vec4(base + color, 1.0);
}
