// Name: PC Mode - CGA
// Author: MustardOS
// Version: 2

vec2 snap_uv(vec2 uv) {
    vec2 native = max(u_native_resolution, vec2(1.0));
    return (floor(uv * native) + 0.5) / native;
}

void main() {
    const vec3 LUMA = vec3(0.299, 0.587, 0.114);
    const vec3 p0 = vec3(0.0, 0.0, 0.0);
    const vec3 p1 = vec3(0.0, 1.0, 1.0);
    const vec3 p2 = vec3(1.0, 0.0, 1.0);
    const vec3 p3 = vec3(1.0, 1.0, 1.0);

    float l = dot(texture2D(u_tex, snap_uv(v_uv)).rgb, LUMA);
    vec3 col = mix(p0, p1, step(0.25, l));
    col = mix(col, p2, step(0.50, l));
    col = mix(col, p3, step(0.75, l));

    gl_FragColor = vec4(col, 1.0);
}
