shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D noise;
varying vec3 pos;
varying float noise_cut;
uniform float texture_size = 0.5;
uniform float sub_texture_size = 0.5;
uniform float texture_noise_cut = 0.5;
uniform float sub_texture_noise_cut = 0.5;
uniform float sub_texture_noise_center_cut = 0.6;
uniform float sub_texture_noise_cut_transition = 2.0;
uniform vec4 albedo_color;
uniform vec3 size;
uniform float center_cut_size = 1.0;
uniform float center_cut_offset = 0.0;

void vertex(){
	pos = VERTEX;
}

void fragment(){
	
	vec3 border_dist = vec3(
		(size.x/2.0)-(pos.x*sign(pos.x)),
		(size.y/2.0)-(pos.y*sign(pos.y)),
		(size.z/2.0)-(pos.z*sign(pos.z))
		);
	if ((pos.x*sign(pos.x))>=(size.x/2.0)-0.0001){border_dist.x=100.0;}
	if ((pos.y*sign(pos.y))>=(size.y/2.0)-0.0001){border_dist.y=100.0;}
	if ((pos.z*sign(pos.z))>=(size.z/2.0)-0.0001){border_dist.z=100.0;}
	float border_dist_float = clamp(
		(min(border_dist.x,min(border_dist.y,border_dist.z))*center_cut_size)+center_cut_offset,
		0.0,1.0);
	float new_sub_texture_noise_cut = mix(sub_texture_noise_cut,sub_texture_noise_center_cut,border_dist_float);
//	ALBEDO.rgb = vec3(border_dist_float);
	
	float noise_val = texture(noise,(vec2(pos.y+pos.x,pos.x+pos.z)*texture_size)+TIME/10.0).x;
	float sub_noise_val = texture(noise,(vec2(pos.y+pos.x,pos.x+pos.z)*(sub_texture_size))).x;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	if (noise_val < texture_noise_cut && sub_noise_val+(noise_val*sub_texture_noise_cut_transition) < new_sub_texture_noise_cut){
		ALPHA = 0.0;
	}else{
		ALBEDO = (vec3(noise_val)*albedo_color.rgb)/1.4+0.1;
		ALBEDO *= max(0.2, float(FRONT_FACING));
	}
	
}