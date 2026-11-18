// Calque CRT très léger, posé au-dessus de tout l'écran (n'intercepte pas le toucher).
// - lignes de balayage à ~4 % et vignettage doux, en permanence ;
// - heat (0 à 1,3) : au-delà de 0,75, vignettage rouge qui pulse (Surchauffe proche).
shader_type canvas_item;

uniform float heat = 0.0;
uniform float scan_strength = 0.045;

void fragment() {
	float scan = scan_strength * (0.5 + 0.5 * sin(FRAGCOORD.y * 1.5708));
	float d = distance(UV, vec2(0.5));
	float vig = smoothstep(0.42, 0.9, d);
	float hot = clamp((heat - 0.75) * 2.0, 0.0, 1.0) * (0.65 + 0.35 * sin(TIME * 4.0));
	vec3 col = mix(vec3(0.0), vec3(1.0, 0.08, 0.12), hot);
	float a = scan + vig * 0.35 + hot * vig * 0.9;
	COLOR = vec4(col, clamp(a, 0.0, 0.9));
}
