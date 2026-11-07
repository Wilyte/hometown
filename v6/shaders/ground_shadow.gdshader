// 接触阴影（对应页面的 ShadowMaterial 地面盘）：
// 页面在模型最低点放一张 radius*11 的 ShadowMaterial(opacity .18) 圆盘，
// three.js 把主光的阴影画在它上面，模型才"落地"而不是浮着。
// Godot 没有 shadow-only 材质，这里改成：启动时用一盏同样的平行光把阴影
// 烘到一张正交贴图上（见 main.gd::_build_contact_shadow），再按光空间投影贴回地面。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D mask_tex : filter_linear, repeat_disable;
// 主光相机 global_transform 的逆（世界 → 光相机空间）
uniform mat4 light_inv;
// 正交相机纵向视野的一半（米）；视口是正方形，横向同样
uniform float half_extent = 100.0;
uniform float opacity = 0.18;
// 见光处的亮度（白盘 * 光强 * dotNL），用来把贴图归一化成 1/0
uniform float lit_max = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 lp = (light_inv * vec4(world_pos, 1.0)).xyz;
	vec2 uv = vec2(lp.x / half_extent * 0.5 + 0.5, 0.5 - lp.y / half_extent * 0.5);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float lit = clamp(texture(mask_tex, uv).r / max(lit_max, 0.001), 0.0, 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = clamp((1.0 - lit) * opacity * inside, 0.0, 1.0);
}
