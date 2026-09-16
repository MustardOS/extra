// Name: PC Mode - EGA Alt.
// Author: MustardOS
// Version: 2

vec2 snap_uv(vec2 uv) {
    vec2 native = max(u_native_resolution, vec2(1.0));
    return (floor(uv * native) + 0.5) / native;
}

void main() {
    vec3 c = texture2D(u_tex, snap_uv(v_uv)).rgb;
    c = floor(c * 3.0 + 0.5) / 3.0;
    gl_FragColor = vec4(c, 1.0);
}
