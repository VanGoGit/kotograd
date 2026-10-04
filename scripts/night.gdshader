shader_type canvas_item;
// Небо Лос-Анджелеса поверх мира: солнце днём, розовые рассветы, яркие закаты
// и тёплая ночь, которую «прорезают» окна, фонари и фары.

uniform float dark = 0.0;   // ночь
uniform float dusk = 0.0;   // закат
uniform float dawn = 0.0;   // рассвет
uniform float sun = 0.0;    // яркое дневное солнце
uniform vec2 size = vec2(1280.0, 800.0);
uniform int count = 0;
uniform vec3 lights[128];

// наложение слоя (c, a) поверх уже накопленного (dc, da)
vec4 over(vec4 dst, vec3 c, float a) {
	float oa = a + dst.a * (1.0 - a);
	vec3 oc = (c * a + dst.rgb * dst.a * (1.0 - a)) / max(oa, 0.0001);
	return vec4(oc, oa);
}

void fragment() {
	vec2 p = UV * size;
	float lit = 0.0;
	for (int i = 0; i < 128; i++) {
		if (i >= count) {
			break;
		}
		vec3 l = lights[i];
		float k = 1.0 - smoothstep(0.0, l.z, distance(p, l.xy));
		lit = max(lit, k);
	}
	vec4 acc = vec4(0.0);

	// закат: сверху сиреневое небо, ниже коралловое, у самой земли золотое
	if (dusk > 0.0) {
		float yy = UV.y;
		vec3 top = vec3(0.62, 0.32, 0.72);
		vec3 mid = vec3(1.0, 0.38, 0.52);
		vec3 bot = vec3(1.0, 0.52, 0.22);
		vec3 sc = yy < 0.5 ? mix(top, mid, yy * 2.0) : mix(mid, bot, (yy - 0.5) * 2.0);
		acc = over(acc, sc, dusk * (0.7 + 0.3 * yy));
		// низкое солнце у горизонта (справа внизу) — тёплое сияние
		float aspect = size.x / size.y;
		vec2 q = UV * vec2(aspect, 1.0);
		float sd = distance(q, vec2(aspect * 0.88, 1.08));
		float glow = 1.0 - smoothstep(0.0, 0.75, sd);
		acc = over(acc, vec3(1.0, 0.78, 0.42), dusk * 1.6 * glow * glow);
	}
	// рассвет: нежно-розовый и персиковый
	if (dawn > 0.0) {
		vec3 dc = mix(vec3(1.0, 0.62, 0.72), vec3(1.0, 0.82, 0.62), UV.y);
		acc = over(acc, dc, dawn);
	}
	// ночь — тёплая фиолетовая, с огнями
	if (dark > 0.0) {
		vec3 night = vec3(0.16, 0.1, 0.32);
		vec3 warm = vec3(1.0, 0.67, 0.31);
		float a_night = dark * (1.0 - 0.95 * lit);
		float a_warm = dark * lit * 0.35;
		float a = clamp(a_night + a_warm, 0.0, 1.0);
		vec3 col = (night * a_night + warm * a_warm) / max(a_night + a_warm, 0.0001);
		acc = over(acc, col, a);
	}
	// солнце: блик в правом верхнем углу и мягкие лучи
	if (sun > 0.0) {
		float aspect = size.x / size.y;
		vec2 q = UV * vec2(aspect, 1.0);
		float g = 1.0 - smoothstep(0.0, 1.1, distance(q, vec2(aspect * 0.95, -0.05)));
		float rays = 0.5 + 0.5 * sin((UV.x * 0.8 - UV.y) * 16.0 + TIME * 0.25);
		float a = sun * (0.2 * g * g + 0.05 * rays * g);
		acc = over(acc, vec3(1.0, 0.95, 0.75), a);
	}
	COLOR = acc;
}
