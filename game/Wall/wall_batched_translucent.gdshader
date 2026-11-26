shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

uniform sampler2D noise;
varying vec3 pos;
varying vec3 wall_size;
varying vec3 wall_color;
varying float dissolve_v;
uniform float texture_size = 0.5;
uniform float sub_texture_size = 0.5;
uniform float texture_noise_cut = 0.5;
uniform float sub_texture_noise_cut = 0.5;
uniform float sub_texture_noise_center_cut = 0.6;
uniform float sub_texture_noise_cut_transition = 2.0;
uniform vec4 albedo_color;
uniform float center_cut_size = 1.0;
uniform float center_cut_offset = 0.0;
uniform float solid_body = 1.0;
uniform float body_brightness = 0.12;
uniform float flat_color = 1.0;   // 1 = map color, 0 = old dim hologram look

// new look (used when flat_color >= 0.5)
uniform float interior_brightness : hint_range(0.0, 1.0) = 0.25;  // wall body
uniform float edge_brightness : hint_range(0.0, 1.0) = 0.85;      // glowing outline
uniform float edge_width = 0.04;                                    // meters

void vertex(){
	wall_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wall_color = INSTANCE_CUSTOM.rgb;
	dissolve_v = INSTANCE_CUSTOM.a;
	pos = VERTEX * wall_size;
}

void fragment(){
	vec3 border_dist = vec3(
		(wall_size.x/2.0)-(pos.x*sign(pos.x)),
		(wall_size.y/2.0)-(pos.y*sign(pos.y)),
		(wall_size.z/2.0)-(pos.z*sign(pos.z))
		);
	if ((pos.x*sign(pos.x))>=(wall_size.x/2.0)-0.0001){border_dist.x=100.0;}
	if ((pos.y*sign(pos.y))>=(wall_size.y/2.0)-0.0001){border_dist.y=100.0;}
	if ((pos.z*sign(pos.z))>=(wall_size.z/2.0)-0.0001){border_dist.z=100.0;}
	float edge_dist = min(border_dist.x, min(border_dist.y, border_dist.z));
	float border_dist_float = clamp((edge_dist*center_cut_size)+center_cut_offset, 0.0, 1.0);
	float new_sub_texture_noise_cut = mix(sub_texture_noise_cut,sub_texture_noise_center_cut,border_dist_float);

	float noise_val = texture(noise,(vec2(pos.y+pos.x,pos.x+pos.z)*texture_size)+TIME/10.0).x;
	float sub_noise_val = texture(noise,(vec2(pos.y+pos.x,pos.x+pos.z)*(sub_texture_size))).x;

	bool hologram_hole = noise_val < texture_noise_cut && sub_noise_val+(noise_val*sub_texture_noise_cut_transition) < new_sub_texture_noise_cut;
	float opacity = 1.0 - dissolve_v;

	if (opacity <= 0.004 || (hologram_hole && solid_body < 0.5)) {
		discard;
	}

	vec3 map_col = wall_color / max(1.0, max(wall_color.r, max(wall_color.g, wall_color.b)));

	vec3 col;
	if (flat_color >= 0.5) {
		float edge = 1.0 - smoothstep(0.0, edge_width, edge_dist);
		col = mix(map_col * interior_brightness, map_col * edge_brightness, edge);
	} else if (hologram_hole) {
		col = map_col * body_brightness;
	} else {
		float lift = 0.1 * max(map_col.r, max(map_col.g, map_col.b));
		col = (vec3(noise_val) * albedo_color.rgb * map_col) / 1.4 + lift;
	}
	col *= mix(0.5, 1.0, float(FRONT_FACING));
	ALBEDO = col;
	// translucent pass: real blending, no dither
	ALPHA = opacity;
}
