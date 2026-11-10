#version 450
// The in-game menu (vk_menu.c): a rounded rectangle by its signed distance, or a glyph from the distance-field atlas (128 on the outline, menu_font.py).
// A rectangle of kind 2 (MN_FADE, the selection) takes the fade's colours from left to right: #FF3D8E -> #D23CF0 -> #8A3FFC
layout(set = 0, binding = 0) uniform sampler2D atlas;
layout(location = 0) in vec2 uv;
layout(location = 1) in vec2 local;
layout(location = 2) flat in vec4 shape;
layout(location = 3) flat in vec4 col;
layout(location = 0) out vec4 o;
void main() {
    float a; vec3 rgb = col.rgb;
    if (shape.w > 0.5) {
        vec2 q = abs(local) - shape.xy + shape.z;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - shape.z;
        a = clamp(0.5 - d, 0.0, 1.0);   // a pixel of soft edge
        if (shape.w > 1.5) {
            float t = clamp(local.x / max(2.0 * shape.x, 1.0) + 0.5, 0.0, 1.0);
            const vec3 c0 = vec3(1.0, 0.239, 0.557), c1 = vec3(0.824, 0.235, 0.941), c2 = vec3(0.541, 0.247, 0.988);
            rgb = t < 0.5 ? mix(c0, c1, t * 2.0) : mix(c1, c2, t * 2.0 - 1.0);
        }
    } else {
        float d = texture(atlas, uv).r, w = max(fwidth(d), 1e-4) * 0.7;   // the edge a pixel wide at any text size
        a = smoothstep(0.5 - w, 0.5 + w, d);
    }
    o = vec4(rgb, col.a * a);
}
