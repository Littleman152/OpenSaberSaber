shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Visual-only notes (fake / uninteractable) drawn in one MultiMesh.
// Per instance: INSTANCE_CUSTOM = (note color r, g, b, dissolve). Only the arrow / dot is drawn.

uniform sampler2D texture_emission : hint_default_black;
uniform float metallic = 0.3;
uniform float roughness = 0.2;
uniform float sub_emission_energy = 0.18;
uniform bool is_dot = false;
uniform bool arrows_enabled = true;
uniform float dissolve_noise_scale = 6.0;
uniform float dissolve_edge_width = 0.08;
uniform float dissolve_edge_energy = 3.0;

varying vec3 obj_pos;
varying vec4 inst;

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

void vertex() {
	obj_pos = VERTEX;
	inst = INSTANCE_CUSTOM;
}

void fragment() {
	float dissolve_amount = clamp(inst.a, 0.0, 1.0);
	float dissolve_glow = 0.0;
	if (dissolve_amount > 0.0) {
		float n = smoothstep(0.15, 0.85, value_noise(obj_pos * dissolve_noise_scale));
		float edge = n - dissolve_amount * (1.0 + dissolve_edge_width);
		if (edge < 0.0) {
			discard;
		}
		dissolve_glow = (1.0 - smoothstep(0.0, dissolve_edge_width, edge)) * smoothstep(0.0, 0.05, dissolve_amount);
	}

	// cut the cube body away, keep only the arrow / dot pixels of the emission texture
	vec2 glyph_uv = is_dot ? vec2(UV.x + 0.5, UV.y) : UV;
	if (!FRONT_FACING || texture(texture_emission, glyph_uv).r < 0.2) {
		discard;
	}

	vec3 col = inst.rgb;
	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	vec3 em = col * sub_emission_energy;
	if (is_dot || arrows_enabled) {
		em += texture(texture_emission, glyph_uv).rgb;
	}
	EMISSION = em + mix(col, vec3(1.0), 0.3) * dissolve_edge_energy * dissolve_glow;
}
