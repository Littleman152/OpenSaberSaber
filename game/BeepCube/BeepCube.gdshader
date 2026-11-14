shader_type spatial;
render_mode cull_disabled,diffuse_burley,specular_schlick_ggx;

uniform vec4 color : source_color;
uniform sampler2D texture_emission : hint_default_black;

uniform float metallic;
uniform float roughness;
uniform float sub_emission_energy;

uniform bool cutted = false;
uniform float cut_vanish = 0.0;
uniform float cut_white_margin = 0.04;

uniform bool is_dot = false;
uniform bool arrows_enabled = true;
uniform bool is_chain_head = false;

// ---- Dissolve (fake / uninteractable notes, Noodle _dissolve) ----
// 0 = solid, 1 = fully gone. Noise-threshold cutout with a glowing edge, like Beat Saber's.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_arrow : hint_range(0.0, 1.0) = 0.0;   // fades only the arrow / dot
uniform float dissolve_noise_scale = 6.0;    // bigger = finer pattern
uniform float dissolve_edge_width = 0.08;    // thickness of the glowing rim
uniform float dissolve_edge_energy = 3.0;    // brightness of the glowing rim

// cheap 3D value noise (8 hashes), only evaluated while a note is dissolving
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x00 = mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x);
	float x10 = mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x);
	float x01 = mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x);
	float x11 = mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

uniform vec3 cut_plane_normal = vec3(0,0,0);
uniform float cut_plane_dist = 0;

varying float cut_interp;
varying float chain_interp;
varying vec3 obj_pos;
void vertex() {
	obj_pos = VERTEX;
	if (is_chain_head) {
		chain_interp = 0.1 + VERTEX.y;
	}
	if (cutted) {
		cut_interp = dot(VERTEX, cut_plane_normal) - cut_plane_dist - cut_vanish;
	}
}

void fragment() {
	// Discard all pixels "in the cut"
	if (
		(cutted && cut_interp < 0.0)
		|| (is_chain_head && chain_interp < 0.0)
	) {
		discard;
	}

	// Dissolve: pixels whose noise value is below the threshold disappear,
	// pixels just above it glow, which gives the burning-away rim.
	float dissolve_glow = 0.0;
	if (dissolve > 0.0) {
		float n = smoothstep(0.15, 0.85, value_noise(obj_pos * dissolve_noise_scale));
		float edge = n - dissolve * (1.0 + dissolve_edge_width);
		if (edge < 0.0) {
			discard;
		}
		// fade the rim in over the first 5% so it doesn't pop when dissolve starts
		dissolve_glow = (1.0 - smoothstep(0.0, dissolve_edge_width, edge)) * smoothstep(0.0, 0.05, dissolve);
	}

	ALBEDO = color.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	if (FRONT_FACING) {
		vec2 dot_uv = vec2(UV.x+0.5, UV.y);
		if (is_dot || arrows_enabled)
			EMISSION = (color.rgb * sub_emission_energy) + texture(texture_emission, is_dot ? dot_uv : UV).rgb * (1.0 - dissolve_arrow);
		else
			EMISSION = (color.rgb * sub_emission_energy);

		if (is_chain_head) {
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,chain_interp) );
		}

		if (cutted){
			// soft white margin
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,cut_interp) );
			// hard white margin
			//EMISSION += vec3( float(cut_white_margin < cut_interp) );
		}
	} else {
		EMISSION = vec3(1.0);
	}

	// glowing rim, slightly whitened version of the note color
	EMISSION += mix(color.rgb, vec3(1.0), 0.3) * dissolve_edge_energy * dissolve_glow;
}
