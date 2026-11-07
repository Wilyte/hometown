// 半球光（three.js HemisphereLight）的等价物：
// Godot 没有 HemisphereLight3D，用一张上下渐变的天光贴图 + ambient_light_source=SKY，
// 让环境光按法线方向取到"上方白、下方暖灰"，得到和 three.js 同样的球面渐变。
shader_type sky;

uniform vec3 sky_color : source_color = vec3(1.0);
uniform vec3 ground_color : source_color = vec3(0.72, 0.69, 0.64);
// three.js：diffuse = albedo/PI * 强度 * 颜色；Godot 的环境光是辐照度，
// 所以这里把颜色乘上 强度/PI，两者才对得上。
uniform float radiance_scale = 0.366;
// gl_compatibility 的 sky 管线把 COLOR 当 sRGB 解码（Forward+/mobile 按线性用）。
// main.gd 在兼容渲染器上置 true，这里先编码成 sRGB，解码后仍是同一条线性辐射。
uniform bool srgb_output = false;

// sky shader 里没有内置的 linear_to_srgb，这里按标准 sRGB 曲线补一个。
vec3 _linear_to_srgb(vec3 c) {
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(lo, hi, step(vec3(0.0031308), c));
}

void sky() {
	// HemisphereLight 的权重：0.5 + 0.5 * dot(N, up)
	float t = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(ground_color, sky_color, t) * radiance_scale;
	COLOR = srgb_output ? _linear_to_srgb(col) : col;
}
