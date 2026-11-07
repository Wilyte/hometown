// 半球光（three.js HemisphereLight）的等价物：
// Godot 没有 HemisphereLight3D，用一张上下渐变的天光贴图 + ambient_light_source=SKY，
// 让环境光按法线方向取到"上方白、下方暖灰"，得到和 three.js 同样的球面渐变。
shader_type sky;

uniform vec3 sky_color : source_color = vec3(1.0);
uniform vec3 ground_color : source_color = vec3(0.72, 0.69, 0.64);
// three.js：diffuse = albedo/PI * 强度 * 颜色；Godot 的环境光是辐照度，
// 所以这里把颜色乘上 强度/PI，两者才对得上。
uniform float radiance_scale = 0.366;

void sky() {
	// HemisphereLight 的权重：0.5 + 0.5 * dot(N, up)
	float t = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	COLOR = mix(ground_color, sky_color, t) * radiance_scale;
}
