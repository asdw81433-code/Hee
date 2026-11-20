shader_type spatial;
// One material for (almost) all static city geometry. Vertex color = base color,
// UV.x = surface type, UV.y = per-object random (window lights, variation).
// Patterns are procedural in world space, so there are no texture fetches (mobile friendly).
//
// Surface types:
//  0 paint/plain  1 brick  2 wood siding  3 sidewalk tiles  4 asphalt  5 grass
//  6 window glass 7 roof shingles 8 emissive sign  9 road paint  10 concrete
//  11 dirt/sand   12 metal  13 water  14 foliage

render_mode diffuse_lambert_wrap, specular_schlick_ggx;

global uniform float night_factor;
global uniform float wetness;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 2D coordinates on the dominant plane of the surface.
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.y > an.x && an.y > an.z) return p.xz;
	if (an.x > an.z) return p.zy;
	return p.xy;
}

void fragment() {
	int kind = int(UV.x + 0.5);
	float rnd = UV.y;
	// Vertex colours are authored in sRGB.
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	vec3 col = base;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec2 uv = plane_uv(world_pos, world_nrm);
	float n1 = vnoise(world_pos.xz * 0.35 + world_pos.y * 0.2);
	float n2 = vnoise(uv * 4.0);
	bool top = world_nrm.y > 0.6;

	if (kind == 1) { // brick
		vec2 b = uv * vec2(4.0, 13.3);
		b.x += step(1.0, mod(b.y, 2.0)) * 0.5;
		vec2 f = fract(b);
		float mortar = step(f.x, 0.06) + step(f.y, 0.1);
		float var = hash12(floor(b)) * 0.18 - 0.09;
		col = mix(base * (1.0 + var), vec3(0.72, 0.7, 0.66), clamp(mortar, 0.0, 1.0));
	} else if (kind == 2) { // wood siding
		float plank = fract(uv.y * 5.0);
		col = base * (0.92 + 0.08 * smoothstep(0.0, 0.15, plank)) * (0.95 + 0.1 * n2);
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.07, plank));
		rough = 0.8;
	} else if (kind == 3) { // sidewalk tiles
		vec2 f = fract(uv * 0.7);
		float joint = step(f.x, 0.03) + step(f.y, 0.03);
		col = base * (0.93 + 0.12 * n2) * (1.0 - 0.18 * clamp(joint, 0.0, 1.0));
		rough = mix(0.9, 0.35, wetness);
		col *= 1.0 - 0.25 * wetness;
	} else if (kind == 4) { // asphalt
		float speck = step(0.82, hash12(floor(world_pos.xz * 22.0)));
		col = base * (0.85 + 0.25 * n1) + speck * 0.05;
		rough = mix(0.92, 0.18, wetness);
		col *= 1.0 - 0.35 * wetness;
	} else if (kind == 5) { // grass
		float n3 = vnoise(world_pos.xz * 1.7);
		col = base * (0.78 + 0.35 * n1) * (0.9 + 0.2 * n3);
		rough = 0.95;
	} else if (kind == 6) { // window glass
		float frame_x = fract(uv.x * 0.62);
		float lit = step(0.45, fract(rnd * 7.31 + floor(uv.x * 0.62) * 0.37 + floor(uv.y * 0.33) * 0.71));
		col = base * 0.6 + vec3(0.05, 0.07, 0.1);
		rough = 0.12;
		metal = 0.35;
		emit = vec3(1.0, 0.82, 0.5) * lit * night_factor * 1.6;
		col *= 1.0 - 0.6 * step(frame_x, 0.04);
	} else if (kind == 7) { // roof shingles
		vec2 r = uv * vec2(3.0, 6.0);
		r.x += step(1.0, mod(r.y, 2.0)) * 0.5;
		vec2 f = fract(r);
		col = base * (0.9 + 0.15 * hash12(floor(r))) * (1.0 - 0.2 * step(f.y, 0.12));
		rough = 0.9;
	} else if (kind == 8) { // emissive sign
		emit = base * (0.6 + 1.6 * night_factor);
		col = base;
		rough = 0.4;
	} else if (kind == 9) { // road paint
		col = base * (0.85 + 0.15 * n2);
		rough = mix(0.7, 0.3, wetness);
		emit = base * 0.06 * night_factor;
	} else if (kind == 10) { // concrete
		col = base * (0.9 + 0.16 * n1) * (0.95 + 0.08 * n2);
		rough = 0.9;
	} else if (kind == 11) { // dirt / sand
		col = base * (0.85 + 0.25 * n1);
		rough = 1.0;
	} else if (kind == 12) { // metal
		col = base;
		rough = 0.45;
		metal = 0.6;
	} else if (kind == 13) { // water
		float w = vnoise(world_pos.xz * 0.8 + TIME * 0.3) * 0.5 + vnoise(world_pos.xz * 2.1 - TIME * 0.4) * 0.5;
		col = base * (0.8 + 0.3 * w);
		rough = 0.08;
		metal = 0.2;
	} else if (kind == 14) { // foliage
		col = base * (0.8 + 0.3 * n2);
		rough = 0.95;
	} else {
		col = base * (0.96 + 0.08 * n2);
	}
	// Ground dirt near the bottom of walls.
	if (!top && kind != 6 && kind != 8) {
		col *= 0.88 + 0.12 * smoothstep(0.0, 0.6, world_pos.y - floor(world_pos.y / 100.0) * 100.0);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
